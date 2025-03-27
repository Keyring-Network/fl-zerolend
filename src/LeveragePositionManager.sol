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


contract LeveragePositionManager is IFlashLoanReceiver {
    using SafeERC20 for IERC20;

    error TokenNotSupported(address tokenAddress);
    error InsufficientLentTokenBalance(address tokenAddress, uint256 balance);
    error LTVTooHigh(uint256 requestedLTV, uint256 maxPoolLTV);
    error LTVTooLow(uint256 targetLTV, uint256 currentLTV);

    IPoolAddressesProviderRegistry public immutable poolAddressesProviderRegistry;
    IPoolAddressesProvider public immutable ADDRESSES_PROVIDER;
    IPool public immutable POOL;

    constructor(address _poolAddressesProviderRegistry, address _addressesProvider, address _pool) {
        poolAddressesProviderRegistry = IPoolAddressesProviderRegistry(_poolAddressesProviderRegistry);
        ADDRESSES_PROVIDER = IPoolAddressesProvider(_addressesProvider);
        POOL = IPool(_pool);
    }

    // @param aToken: aToken to check if it is supported
    // @notice: returns true if the aToken is supported, false otherwise
    function revertIfATokenNotSupported(AToken aToken) public view {
        IPool pool = aToken.POOL();
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

    // @param aLentToken: aToken of the lent token
    // @param aBorrowedToken: aToken of the borrowed token
    // @param interestRateMode: Mode of the interest rate: Mode stable (MODE 1) or Mode variable (MODE 2)
    // @param targetLtv: Target LTV to reach with a mantissa of 10000. Leave empty to use the max LTV of the pool
    // @notice: args expecting ATokens to be able to check their existence in the protocol
    // @notice: this function is used to take a leveraged position by looping lending and borrowing using the same token
    // @notice: not all prerequisites are checked here (pool liquidity availability, token used as collateral, IRMode, etc.) as it will be called by the core contracts. Only basic prerequisites are checked here (token user's balance and ltv limit to have early revert)
    function takePosition(AToken aToken, uint256 lentTokenAmount, uint256 targetLtv, bool interestRateMode) public {
        // @dev: revert if the token is not supported
        revertIfATokenNotSupported(aToken);

        // @dev: check if the token amount held by the user is above the amount to lend
        if (aToken.balanceOf(address(this)) < lentTokenAmount) {
            revert InsufficientLentTokenBalance(address(aToken), lentTokenAmount);
        }

        IPool pool = aToken.POOL();
        address underlyingAsset = aToken.UNDERLYING_ASSET_ADDRESS();
        DataTypes.ReserveData memory reserveData = pool.getReserveData(underlyingAsset);
        uint256 maxLTV = (reserveData.configuration.data & 0xFFFF);

        if (targetLtv > maxLTV) {
            revert LTVTooHigh(targetLtv, maxLTV);
        }

        targetLtv = targetLtv == 0 ? maxLTV : targetLtv;

        DataTypes.UserConfigurationMap memory userConfig = pool.getUserConfiguration(msg.sender);
        uint256 currentLtv = (userConfig.data & 0xFFFF);

        if (currentLtv == targetLtv) {
            revert LTVTooLow(targetLtv, currentLtv);
        }

        // @dev: get the current collateral in base
        (uint256 totalCollateralBase,,,,,) = pool.getUserAccountData(msg.sender);

        // @dev: get the target collateral in base. This is the lentTokenAmount x the leverage factor
        uint256 targetCollateralBase = lentTokenAmount / (10000 - targetLtv) * 10000;

        // @dev: get the amount of collateral to get from flashloan
        uint256 collateralToGetFromFlashloanBase = targetCollateralBase - totalCollateralBase;

        // @dev: get the price of the token in base currency
        // @notice: Eth mantissa is 18. `getAssetPrice` mantissa is 18 as well
        // @notice: eg: 
            // - 1 ETH (base currency) = 2000 USD
            // - 1 BTC = 80000 USD
            // => getAssetPrice(BTC) = 80000 / 2000 x 10^18 = 4000000000000000000000000
        IPriceOracle priceOracle = IPriceOracle(pool.ADDRESSES_PROVIDER().getPriceOracle());
        uint256 tokenPrice = priceOracle.getAssetPrice(underlyingAsset);
        uint256 collateralToGetFromFlashloanInToken = collateralToGetFromFlashloanBase / tokenPrice * 1e18;

        // @dev: safe transfer the lent token to the contract
        IERC20(underlyingAsset).safeTransferFrom(msg.sender, address(this), lentTokenAmount);

        // @dev: prepare the flashloan
        // @notice: we need to approve the pool to spend the collateral token
        IERC20(underlyingAsset).approve(address(pool), collateralToGetFromFlashloanInToken);

        // @dev: execute the flashloan
        address[] memory assets = new address[](1);
        assets[0] = underlyingAsset;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = collateralToGetFromFlashloanInToken;
        uint256[] memory interestRateModes = new uint256[](1);
        interestRateModes[0] = 0; // NONE mode for regular flashloan
        address onBehalfOf = msg.sender;
        bytes memory params = "";
        uint16 referralCode = 0;
        pool.flashLoan(
            address(this),
            assets,
            amounts,
            interestRateModes,
            onBehalfOf,
            params,
            referralCode
        );
    }

    function executeOperation(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address initiator,
        bytes calldata params
    ) external override returns (bool) {
        require(msg.sender == address(POOL), "Caller must be pool");
        require(assets.length == 1, "Only single asset flash loan supported");
        require(initiator == address(this), "Initiator must be this contract");

        address asset = assets[0];
        uint256 amount = amounts[0];
        uint256 premium = premiums[0];

        // Supply the borrowed amount to the pool
        IERC20(asset).approve(address(POOL), amount);
        POOL.supply(asset, amount, address(this), 0);

        // Approve the pool to spend the borrowed amount plus premium
        IERC20(asset).approve(address(POOL), amount + premium);

        return true;
    }
}
