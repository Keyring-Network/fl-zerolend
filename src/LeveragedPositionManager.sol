// SPDX-License-Identifier: MIT
pragma solidity 0.8.12;

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
import "forge-std/console.sol";
/// For a brand new position (0 collateral, 0 borrowed), given a LTV, a user with an amount X of tokens can take the following position:
/// - Leverage factor = 1 / (1 - LTV)
/// - Total lent = X * leverage factor
/// - Total borrowed = X * leverage factor * LTV
///
/// EG with LTV = 0.8 and X = 1000 USD:
/// - Leverage factor = 1 / (1 - 0.8) = 5
/// - Total lent = 1000 * 5 = 5000 USD
/// - Total borrowed = 5000 * 0.8 = 4000 USD
/// The X amount covers the difference between the total lent and the total borrowed.

contract LeveragedPositionManager is IFlashLoanReceiver {
    using SafeERC20 for IERC20;

    error TokenNotSupported(address tokenAddress);
    error TokenPriceZeroOrUnknown(address tokenAddress);
    error InsufficientLentTokenBalance(address tokenAddress, uint256 balance);
    error LTVTooHigh(uint256 requestedLTV, uint256 maxPoolLTV);
    error LTVTooLow(uint256 targetLTV, uint256 currentLTV);
    error TransientStorageMismatch();
    // @dev: fake transient storage to ensure EVM backward compatibility
    IPool public transientPool;
    IPoolAddressesProvider public transientAddressesProvider;
    address public transientUser;

    IPoolAddressesProviderRegistry public immutable poolAddressesProviderRegistry;

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

    /// @param aToken The AToken to validate
    /// @param targetLtv The desired LTV value
    /// @param user The address of the user whose LTV is being validated
    /// @return The validated target LTV (might be adjusted to max LTV if not specified)
    function validateLtv(AToken aToken, uint256 targetLtv, address user) public view returns (uint256) {
        IPool pool = AToken(address(aToken)).POOL();
        address underlyingAsset = aToken.UNDERLYING_ASSET_ADDRESS();
        DataTypes.ReserveData memory reserveData = pool.getReserveData(underlyingAsset);
        uint256 maxLTV = (reserveData.configuration.data & 0xFFFF);

        if (targetLtv > maxLTV) {
            revert LTVTooHigh(targetLtv, maxLTV);
        }

        // @dev: if the targetLtv is 0, set it to the maxLTV
        targetLtv = targetLtv == 0 ? maxLTV : targetLtv;

        // @dev: get the current LTV from user account data
        (uint256 totalCollateralBase, uint256 totalDebtBase,,,,) = pool.getUserAccountData(user);
        uint256 currentLtv = totalDebtBase == 0 ? 0 : (totalDebtBase * 10000) / totalCollateralBase;

        /// @dev: if the current LTV is greater than the target LTV, revert
        if (currentLtv >= targetLtv) {
            revert LTVTooLow(targetLtv, currentLtv);
        }

        return targetLtv;
    }

    // @param aToken: aToken of the lent token
    // @param aBorrowedToken: aToken of the borrowed token
    // @param interestRateMode: Mode of the interest rate: Mode stable (MODE 1) or Mode variable (MODE 2)
    // @param targetLtv: Target LTV to reach with a mantissa of 10000. Leave empty to use the max LTV of the pool
    // @notice: args expecting ATokens to be able to check their existence in the protocol
    // @notice: this function is used to take a leveraged position by looping lending and borrowing using the same token
    // @notice: not all prerequisites are checked here (pool liquidity availability, token used as collateral, IRMode, etc.) as it will be called by the core contracts. Only basic prerequisites are checked here (token user's balance and ltv limit to have early revert)
    function takePosition(AToken aToken, uint256 lentTokenAmount, uint256 targetLtv, uint256 interestRateMode) public {


        // @dev: revert if the token is not supported
        revertIfATokenNotSupported(aToken);

        // @dev: check if the token amount held by the user is above the amount to lend
        IERC20(aToken.UNDERLYING_ASSET_ADDRESS()).transferFrom(msg.sender, address(this), lentTokenAmount);

        // @dev: set the transient storage
        if (address(transientPool) == address(0) && address(transientAddressesProvider) == address(0) && address(transientUser) == address(0)) {
            transientPool = aToken.POOL();
            transientAddressesProvider = transientPool.ADDRESSES_PROVIDER();
            transientUser = msg.sender;
        } else {
            revert TransientStorageMismatch();
        }

        // @dev: validate the target LTV and get the final target LTV
        targetLtv = validateLtv(aToken, targetLtv, msg.sender);

        // @dev: get the amount of collateral to get from flashloan 
        uint256 collateralToGetFromFlashloanInToken =
            getCollateralToGetFromFlashloanInToken(aToken, lentTokenAmount, targetLtv, msg.sender);
        
        // @dev: execute the flashloan
        address[] memory assets = new address[](1);
        assets[0] = aToken.UNDERLYING_ASSET_ADDRESS();
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = collateralToGetFromFlashloanInToken;
        uint256[] memory interestRateModes = new uint256[](1);
        interestRateModes[0] = 0;
        address onBehalfOf = msg.sender;
        bytes memory params = abi.encode(msg.sender, aToken.POOL(), targetLtv, interestRateMode);
        uint16 referralCode = 0;

        console.log("user balance BEFORE", IERC20(aToken.UNDERLYING_ASSET_ADDRESS()).balanceOf(transientUser));
        console.log("This balance BEFORE", IERC20(aToken.UNDERLYING_ASSET_ADDRESS()).balanceOf(address(this)));
        
        aToken.POOL().flashLoan(address(this), assets, amounts, interestRateModes, address(this), params, referralCode);
    }

    // @param aToken: aToken to to loop with
    // @param lentTokenAmount: amount of the lent token
    // @param targetLtv: target LTV to reach with a mantissa of 10000
    // @notice: returns the amount of tokens to get from flashloan in tokens
    function getCollateralToGetFromFlashloanInToken(
        AToken aToken,
        uint256 lentTokenAmount,
        uint256 targetLtv,
        address user
    ) public view returns (uint256) {
        
        // @dev: get the target collateral in tokens. This is the lentTokenAmount x the leverage factor
        // TODO: check if this is correct
        uint256 targetCollateralInToken = lentTokenAmount / (10000 - targetLtv) * 10000;
        console.log("targetCollateralInToken", targetCollateralInToken);

        // @dev: get the current collateral in base
        (uint256 totalCollateralBase,,,,,) = aToken.POOL().getUserAccountData(user);
        console.log("totalCollateralBase", totalCollateralBase);

        // @dev: get the price of the token in base currency
        // @notice: Eth mantissa is 18. `getAssetPrice` mantissa is 18 as well
        // @notice: eg:
        // - 1 ETH (base currency) = 2000 USDeq.
        // - 1 BTC = 80000 USDeq.
        // => getAssetPrice(BTC) = 80000 / 2000 x 10^18 = 4000000000000000000000000
        IPriceOracle priceOracle = IPriceOracle(aToken.POOL().ADDRESSES_PROVIDER().getPriceOracle());

        uint256 tokenPrice = priceOracle.getAssetPrice(aToken.UNDERLYING_ASSET_ADDRESS());
        if (tokenPrice == 0) {
            revert TokenPriceZeroOrUnknown(address(aToken));
        }
        console.log("tokenPrice", tokenPrice);

        // @dev: get the current collateral in tokens
        uint256 totalCollateralInToken = totalCollateralBase / tokenPrice * 10 ** 18;
        console.log("totalCollateralInToken", totalCollateralInToken);

        uint256 collateralToGetFromFlashloanInToken;
        if (totalCollateralInToken >= targetCollateralInToken) {
            // @dev: if the total collateral in tokens is greater than the target collateral in tokens, we don't need to get any collateral from flashloan
            collateralToGetFromFlashloanInToken = 0;
        } else {
            // @dev: get the amount of collateral to get from flashloan
            // @notice: we need to subtract the lentTokenAmount from the total collateral in tokens because it will contribute to the collateral in the next flashloan
            collateralToGetFromFlashloanInToken = targetCollateralInToken - totalCollateralInToken;
        }
        console.log("collateralToGetFromFlashloanInToken", collateralToGetFromFlashloanInToken);
        
        return collateralToGetFromFlashloanInToken;
    }

    function executeOperation(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address initiator,
        bytes calldata params
    ) external returns (bool) {
        (address user, IPool pool, uint256 targetLtv, uint256 interestRateMode) = abi.decode(params, (address, IPool, uint256, uint256));
        require(msg.sender == address(transientPool), "Caller must be pool");
        require(user == transientUser, "User must be the same");
        require(assets.length == 1, "Only single asset flash loan supported");
        require(initiator == address(this), "Initiator must be this contract");
        require(pool == transientPool, "Pool must be the same");

        IERC20 token = IERC20(assets[0]);
        uint256 amount = amounts[0];
        uint256 premium = premiums[0];

        console.log("user balance A", token.balanceOf(transientUser) / 10 ** 18);
        console.log("this balance A", token.balanceOf(address(this)) / 10 ** 18);
        console.log("amount borrowed", amount / 10 ** 18);
        console.log("premium to pay", premium / 10 ** 18);
        
        // TODO: remove
        //amount = 1000;

        // @dev: approve the token to be spent by the pool
        token.approve(address(pool), type(uint256).max);

        // @dev: take the position
        pool.supply(address(token), amount, user, uint16(interestRateMode));

        // @dev: get the amount to repay
        uint256 amountToRepay = amount + premium;
        console.log("amountToRepay", amountToRepay / 10 ** 18);

        // @dev: get the amount to borrow
        uint256 amountToBorrow = amountToRepay - token.balanceOf(address(this));
        console.log("amountToBorrow", amountToBorrow / 10 ** 18);

        // @dev: borrow the token
        pool.borrow(address(token), amountToBorrow, interestRateMode, 0, user);
        console.log("user balance B", token.balanceOf(transientUser) / 10 ** 18);
        console.log("this balance B", token.balanceOf(address(this)) / 10 ** 18);

        // @dev: repay the flashloan
        console.log("interestRateMode", interestRateMode);
        token.transfer(address(pool), amountToRepay);
        console.log("user balance C", token.balanceOf(transientUser) / 10 ** 18);
        console.log("this balance C", token.balanceOf(address(this)) / 10 ** 18);

        // @dev: remove the approval
        token.approve(address(pool), 0);
        
        return true;
    }

    function ADDRESSES_PROVIDER() external view returns (IPoolAddressesProvider) {
        if (address(transientAddressesProvider) == address(0)) {
            revert TransientStorageMismatch();
        }
        return transientAddressesProvider;
    }

    function POOL() external view returns (IPool) {
        if (address(transientPool) == address(0)) {
            revert TransientStorageMismatch();
        }
        return transientPool;
    }
}
