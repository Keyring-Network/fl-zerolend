// SPDX-License-Identifier: MIT
pragma solidity 0.8.12;

import {IPool} from "@zerolend/interfaces/IPool.sol";
import {IPoolAddressesProviderRegistry} from "@zerolend/interfaces/IPoolAddressesProviderRegistry.sol";
import {IPoolAddressesProvider} from "@zerolend/interfaces/IPoolAddressesProvider.sol";
import {IERC20Detailed as IERC20} from "@zerolend/dependencies/openzeppelin/contracts/IERC20Detailed.sol";
import {AToken} from "@zerolend/protocol/tokenization/AToken.sol";
import {IScaledBalanceToken} from "@zerolend/interfaces/IScaledBalanceToken.sol";
import {IPoolFlashLoanReceiver} from "@zerolend/interfaces/IPoolFlashLoanReceiver.sol";

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


contract LeveragePositionManager is IPoolFlashLoanReceiver {
    error TokenNotSupported(address tokenAddress);
    error InsufficientLentTokenBalance(address tokenAddress, uint256 balance);
    error LTVTooHigh(uint256 requestedLTV, uint256 maxPoolLTV);
    IPoolAddressesProviderRegistry public immutable poolAddressesProviderRegistry;


    
    constructor(address _poolAddressesProviderRegistry) {
        poolAddressesProviderRegistry = IPoolAddressesProviderRegistry(_poolAddressesProviderRegistry);
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
        if (aLentToken.balanceOf(address(this)) < lentTokenAmount) {
            revert InsufficientLentTokenBalance(address(aLentToken), lentTokenAmount);
        }

        IPool pool = aToken.POOL();

        uint256 maxLTV = pool.MAX_LTV();

        if (targetLtv > maxLTV) {
            revert LtvTooHigh(targetLtv, maxLTV);
        }

        targetLtv = targetLtv == 0 ? maxLTV : targetLtv;

        uint256 currentLtv = pool.getUserAccountData(user).ltv;

        if (currentLtv == targetLtv) {
            revert LtvTooLow(targetLtv, currentLtv);
        }

        // @dev: get the current collateral in base
        uint256 totalCollateralBase = pool.getUserAccountData(user).totalCollateralBase;

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
        uint256 tokenPrice = pool.getPriceOracle().getAssetPrice(address(aToken.UNDERLYING()));
        uint256 collateralToGetFromFlashloanInToken = collateralToGetFromFlashloanBase / tokenPrice * 1e18;

        // @dev: safe transfer the lent token to the contract
        aLentToken.underlying().safeTransferFrom(msg.sender, address(this), lentTokenAmount);

        // @dev: prepare the flashloan
        // @notice: we need to approve the pool to spend the collateral token
        aLentToken.underlying().approve(address(pool), collateralToGetFromFlashloanInToken);

        // @dev: execute the flashloan
        pool.flashLoan(address(this), address(aLentToken.underlying()), collateralToGetFromFlashloanInToken, "");
        

    }

}
