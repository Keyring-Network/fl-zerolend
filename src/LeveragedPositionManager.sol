// SPDX-License-Identifier: MIT
pragma solidity 0.8.12;

import "forge-std/console.sol";
import "../dependencies/zerolend-1.0.0/contracts/interfaces/IPool.sol";
import "../dependencies/zerolend-1.0.0/contracts/interfaces/IPoolAddressesProviderRegistry.sol";
import "../dependencies/zerolend-1.0.0/contracts/interfaces/IPoolAddressesProvider.sol";
import "../dependencies/zerolend-1.0.0/contracts/dependencies/openzeppelin/contracts/IERC20.sol";
import "../dependencies/zerolend-1.0.0/contracts/dependencies/openzeppelin/contracts/SafeERC20.sol";
import "../dependencies/zerolend-1.0.0/contracts/protocol/tokenization/AToken.sol";
import "../dependencies/zerolend-1.0.0/contracts/interfaces/IScaledBalanceToken.sol";
import "../dependencies/zerolend-1.0.0/contracts/flashloan/interfaces/IFlashLoanReceiver.sol";
import "../dependencies/zerolend-1.0.0/contracts/protocol/libraries/types/DataTypes.sol";
import "../dependencies/zerolend-1.0.0/contracts/interfaces/IPriceOracle.sol";
/// For a brand new position (0 collateral, 0 borrowed), given a Ltv, a user with an amount X of tokens can take the following position:
/// - Leverage factor = 1 / (1 - Ltv)
/// - Total lent = X * leverage factor
/// - Total borrowed = X * leverage factor * Ltv
///
/// EG with Ltv = 0.8 and X = 1000 USD:
/// - Leverage factor = 1 / (1 - 0.8) = 5
/// - Total lent = 1000 * 5 = 5000 USD
/// - Total borrowed = 5000 * 0.8 = 4000 USD
/// The X amount covers the difference between the total lent and the total borrowed.

contract LeveragedPositionManager is IFlashLoanReceiver {
    using SafeERC20 for IERC20;

    error TokenNotSupported(address tokenAddress);
    error TokenPriceZeroOrUnknown(address tokenAddress);
    error InsufficientLentTokenBalance(address tokenAddress, uint256 balance);
    error LtvTooHigh(uint256 requestedLtv, uint256 maxPoolLtv);
    error LtvTooLow(uint256 targetLtv, uint256 currentLtv);
    error TransientStorageMismatch();
    error CallerNotPool(address caller, address expectedPool);
    error UserMismatch(address provided, address expected);
    error MultipleAssetsNotSupported(uint256 assetCount);
    error InitiatorMismatch(address provided, address expected);
    error PoolMismatch(address provided, address expected);
    error NonZeroAllowance(uint256 currentAllowance);
    error BalanceMismatch(uint256 current, uint256 expected);
    error InvalidFlashLoanAmount(uint256 amount, uint256 premium);
    error InvalidBorrowAmount(uint256 amountToBorrow, uint256 amountToRepay, uint256 currentBalance);
    error InvalidResultingCollateral();
    
    
    // @dev: transient storage as persistent storage to ensure EVM backward compatibility
    IPool public transientPool;
    IPoolAddressesProvider public transientAddressesProvider;
    address public transientUser;

    IPoolAddressesProviderRegistry public immutable poolAddressesProviderRegistry;

    uint256 public immutable LTV_BASE = 10000;

    constructor(address _poolAddressesProviderRegistry) {
        poolAddressesProviderRegistry = IPoolAddressesProviderRegistry(_poolAddressesProviderRegistry);
    }

    // @param aToken: aToken to check if it is supported
    // @notice: returns true if the aToken is supported, false otherwise
    function revertIfATokenNotSupported(AToken aToken) public view {
        IPool pool = AToken(address(aToken)).POOL();
        IPoolAddressesProvider addressesProvider = pool.ADDRESSES_PROVIDER();
        address[] memory poolAdressesProviders = poolAddressesProviderRegistry.getAddressesProvidersList();

        bool isSupported = false;
        for (uint256 i = 0; i < poolAdressesProviders.length; i++) {
            if (address(addressesProvider) == poolAdressesProviders[i]) {
                isSupported = true;
                break;
            }
        }

        if (!isSupported) {
            revert TokenNotSupported(address(aToken));
        }
    }

    /// @param aToken: aToken to get the price of
    /// @return tokenPrice: price of the token
    function getTokenPrice(AToken aToken) public view returns (uint256) {
        IPriceOracle priceOracle = IPriceOracle(aToken.POOL().ADDRESSES_PROVIDER().getPriceOracle());

        uint256 tokenPrice = priceOracle.getAssetPrice(aToken.UNDERLYING_ASSET_ADDRESS());
        if (tokenPrice == 0) {
            revert TokenPriceZeroOrUnknown(address(aToken));
        }

        return tokenPrice;
    }

    /// @param aToken: aToken to convert
    /// @param baseAmount: amount of the base currency to convert
    /// @return tokenAmount: amount of the token
    function convertBaseToToken(AToken aToken, uint256 baseAmount) public view returns (uint256) {
        uint256 tokenAmount = baseAmount * (10 ** aToken.decimals()) / getTokenPrice(aToken);
        return tokenAmount;
    }

    /// @param aToken The AToken to validate
    /// @param targetLtv The desired Ltv value
    /// @param user The address of the user whose Ltv is being validated
    /// @return The validated target Ltv (might be adjusted to max Ltv if not specified)
    function validateLtv(AToken aToken, uint256 targetLtv, address user) public view returns (uint256) {
        IPool pool = AToken(address(aToken)).POOL();
        address underlyingAsset = aToken.UNDERLYING_ASSET_ADDRESS();
        DataTypes.ReserveData memory reserveData = pool.getReserveData(underlyingAsset);
        uint256 maxLtv = (reserveData.configuration.data & 0xFFFF);

        if (targetLtv > maxLtv) {
            revert LtvTooHigh(targetLtv, maxLtv);
        }

        // @dev: if the targetLtv is 0, set it to the maxLtv
        targetLtv = targetLtv == 0 ? maxLtv : targetLtv;

        // @dev: get the current Ltv from user account data
        (uint256 totalCollateralBase, uint256 totalDebtBase,,,,) = pool.getUserAccountData(user);
        uint256 currentLtv = totalDebtBase == 0 ? 0 : (totalDebtBase * LTV_BASE) / totalCollateralBase;

        /// @dev: if the current Ltv is greater than the target Ltv, revert
        if (currentLtv >= targetLtv) {
            revert LtvTooLow(targetLtv, currentLtv);
        }

        return targetLtv;
    }

    /**
     * @notice Computes the flash loan amount needed to adjust a position to a target LTV.
     * @param targetLtv The desired resulting LTV after the operation (scaled by 10000, must be < 10000).
     * @param tokenAmount The signed amount of tokens being added (positive) or withdrawn (negative).
     * @return flashLoanAmount The flash loan amount:
     *         - Positive value means you need to borrow that extra amount to "top up" your debt.
     *         - Negative value means you need to repay that amount from your debt.
     *         - Zero indicates no extra debt adjustment is required.
     *
     * The invariant assumed is that after the flash loan:
     *      existingDebt + flashLoanAmount = targetLtv * (existingCollateral + tokenAmount + flashLoanAmount) / LTV_BASE
     *
     * Solving for flashLoanAmount (X):
     *      X = [targetLtv * (existingCollateral + tokenAmount) / LTV_BASE - existingDebt] / (1 - targetLtv/LTV_BASE)
     */
    function getAmountToBorrowInFlashLoan(AToken aToken, int256 tokenAmount, uint256 targetLtv, address user)
        public
        view
        returns (int256)
    {
        (uint256 existingCollateralBase, uint256 existingDebtBase,,,,) = aToken.POOL().getUserAccountData(user);
        uint256 existingCollateralInToken = convertBaseToToken(aToken, existingCollateralBase);
        uint256 existingDebtInToken = convertBaseToToken(aToken, existingDebtBase);
        
        int256 newCollateralInToken = int256(existingCollateralInToken) + tokenAmount;
        console.log("newCollateralInToken", newCollateralInToken);
        if (newCollateralInToken <= 0) {
            revert InvalidResultingCollateral();
        }

        int256 numerator = (int256(targetLtv) * newCollateralInToken) / int256(LTV_BASE) - int256(existingDebtInToken);
        int256 denominator = int256(LTV_BASE) - int256(targetLtv);

        return (numerator * int256(LTV_BASE)) / denominator;
        
    }

    // @param aToken: aToken of the lent token
    // @param tokenAmount: amount of the token to take or remove from the position
    // @param targetLtv: Target Ltv to reach with a mantissa of LTV_BASE. Leave empty to use the max Ltv of the pool
    // @param interestRateMode: Mode of the interest rate: Mode stable (MODE 1) or Mode variable (MODE 2)
    // @notice: args expecting ATokens to be able to check their existence in the protocol
    // @notice: this function is used to take a leveraged position by looping lending and borrowing using the same token
    // @notice: not all prerequisites are checked here (pool liquidity availability, token used as collateral, IRMode, etc.) as it will be called by the core contracts. Only basic prerequisites are checked here (token user's balance and ltv limit to have early revert)
    function takePosition(AToken aToken, int256 tokenAmount, uint256 targetLtv, uint256 interestRateMode) public {
        // @dev: revert if the token is not supported
        revertIfATokenNotSupported(aToken);

        /// @dev: Pre-flashloan balances, captured to prevent the contract from being unusable if someone sends tokens to this contract
        //uint256 underlyingBalanceBeforeFlashLoan = IERC20(aToken.UNDERLYING_ASSET_ADDRESS()).balanceOf(address(this));
        //uint256 aTokenBalanceBeforeFlashLoan = aToken.balanceOf(address(this));

        IERC20 token = IERC20(aToken.UNDERLYING_ASSET_ADDRESS());

        // @dev: set the transient storage
        if (
            address(transientPool) == address(0) && address(transientAddressesProvider) == address(0)
                && address(transientUser) == address(0)
        ) {
            transientPool = aToken.POOL();
            transientAddressesProvider = transientPool.ADDRESSES_PROVIDER();
            transientUser = msg.sender;
        } else {
            revert TransientStorageMismatch();
        }

        // @dev: validate the target Ltv and get the final target Ltv
        targetLtv = validateLtv(aToken, targetLtv, msg.sender);

        // @dev: get the amount to get from flashloan
        int256 amountToBorrowInFlashLoan = getAmountToBorrowInFlashLoan(aToken, tokenAmount, targetLtv, msg.sender);

        // @dev: execute the flashloan
        address[] memory assets = new address[](1);
        assets[0] = aToken.UNDERLYING_ASSET_ADDRESS();
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amountToBorrowInFlashLoan > 0 ? uint256(amountToBorrowInFlashLoan) : uint256(-amountToBorrowInFlashLoan);
        uint256[] memory interestRateModes = new uint256[](1);
        interestRateModes[0] = 0;
        bytes memory params = abi.encode(msg.sender, aToken.POOL(), interestRateMode, amountToBorrowInFlashLoan > 0, tokenAmount);
        uint16 referralCode = 0;

        /// @dev: revert if the allowance is not 0
        if (token.allowance(address(this), address(aToken.POOL())) != 0) {
            revert NonZeroAllowance(token.allowance(address(this), address(aToken.POOL())));
        }

        /// @dev: execute the flashloan
        aToken.POOL().flashLoan(address(this), assets, amounts, interestRateModes, address(this), params, referralCode);

        // /// @dev: post-flashloan check that the balances of underlying are the same
        // if (token.balanceOf(address(this)) != underlyingBalanceBeforeFlashLoan) {
        //     revert BalanceMismatch(token.balanceOf(address(this)), underlyingBalanceBeforeFlashLoan);
        // }

        // /// @dev: post-flashloan check that the balances of aToken are the same
        // if (aToken.balanceOf(address(this)) != aTokenBalanceBeforeFlashLoan) {
        //     revert BalanceMismatch(aToken.balanceOf(address(this)), aTokenBalanceBeforeFlashLoan);
        // }

        // /// @dev: post-flashloan check that the allowance is 0
        // if (token.allowance(address(this), address(aToken.POOL())) != 0) {
        //     revert NonZeroAllowance(token.allowance(address(this), address(aToken.POOL())));
        // }
        transientPool = IPool(address(0));
        transientAddressesProvider = IPoolAddressesProvider(address(0));
        transientUser = address(0);
    }

    /// @inheritdoc IFlashLoanReceiver
    function executeOperation(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address initiator,
        bytes calldata params
    ) external returns (bool) {
        (address user, IPool pool, uint256 interestRateMode, bool isBorrow, int256 tokenAmount) =
            abi.decode(params, (address, IPool, uint256, bool, int256));
        if (msg.sender != address(transientPool)) {
            revert CallerNotPool(msg.sender, address(transientPool));
        }
        if (user != transientUser) {
            revert UserMismatch(user, transientUser);
        }
        if (assets.length != 1) {
            revert MultipleAssetsNotSupported(assets.length);
        }
        if (initiator != address(this)) {
            revert InitiatorMismatch(initiator, address(this));
        }
        if (pool != transientPool) {
            revert PoolMismatch(address(pool), address(transientPool));
        }

        IERC20 token = IERC20(assets[0]);
        uint256 amountBorrowed = amounts[0];
        uint256 premium = premiums[0];

        if (tokenAmount > 0) {
            token.safeTransferFrom(user, address(this), uint256(tokenAmount));
            token.approve(address(pool), uint256(tokenAmount));
            pool.supply(address(token), uint256(tokenAmount), user, uint16(interestRateMode));
        }

        token.approve(address(pool), amountBorrowed);
        if (isBorrow) {
            pool.supply(address(token), amountBorrowed, user, uint16(interestRateMode));
            pool.borrow(address(token), amountBorrowed + premium, interestRateMode, 0, user);
            if (tokenAmount < 0) {
                pool.borrow(address(token), uint256(-tokenAmount), interestRateMode, 0, user);
                token.transfer(user, uint256(-tokenAmount));
            }
        } else {
            pool.repay(address(token), amountBorrowed, interestRateMode, user);
            pool.withdraw(address(token), amountBorrowed + premium, user);
            if (tokenAmount < 0) {
                pool.withdraw(address(token), uint256(-tokenAmount), user);
                token.transfer(user, uint256(-tokenAmount));
            }
        }

        token.approve(address(pool), amountBorrowed + premium);

        return true;
    }

    /// @inheritdoc IFlashLoanReceiver
    function ADDRESSES_PROVIDER() external view returns (IPoolAddressesProvider) {
        if (address(transientAddressesProvider) == address(0)) {
            revert TransientStorageMismatch();
        }
        return transientAddressesProvider;
    }

    /// @inheritdoc IFlashLoanReceiver
    function POOL() external view returns (IPool) {
        if (address(transientPool) == address(0)) {
            revert TransientStorageMismatch();
        }
        return transientPool;
    }


    // function getNetBalance(AToken aToken, address user) public view returns (uint256) {
    //       DataTypes.ReserveData memory reserve = IPool(ADDRESSES_PROVIDER.getPool()).getReserveData(
    //   asset
    // );

    // DataTypes.UserConfigurationMap memory userConfig = IPool(ADDRESSES_PROVIDER.getPool())
    //   .getUserConfiguration(user);

    // currentATokenBalance = IERC20Detailed(reserve.aTokenAddress).balanceOf(user);
    // currentVariableDebt = IERC20Detailed(reserve.variableDebtTokenAddress).balanceOf(user);
    // currentStableDebt = IERC20Detailed(reserve.stableDebtTokenAddress).balanceOf(user);
    // principalStableDebt = IStableDebtToken(reserve.stableDebtTokenAddress).principalBalanceOf(user);
    // scaledVariableDebt = IVariableDebtToken(reserve.variableDebtTokenAddress).scaledBalanceOf(user);
    // liquidityRate = reserve.currentLiquidityRate;
    // stableBorrowRate = IStableDebtToken(reserve.stableDebtTokenAddress).getUserStableRate(user);
    // stableRateLastUpdated = IStableDebtToken(reserve.stableDebtTokenAddress).getUserLastUpdated(
    //   user
    // );
    }
    

