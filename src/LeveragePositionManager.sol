// SPDX-License-Identifier: MIT
pragma solidity 0.8.12;

import {IPool} from "@zerolend/interfaces/IPool.sol";
import {IPoolAddressesProviderRegistry} from "@zerolend/interfaces/IPoolAddressesProviderRegistry.sol";
import {IPoolAddressesProvider} from "@zerolend/interfaces/IPoolAddressesProvider.sol";
import {IERC20Detailed as IERC20} from "@zerolend/dependencies/openzeppelin/contracts/IERC20Detailed.sol";
import {AToken} from "@zerolend/protocol/tokenization/AToken.sol";
import {IScaledBalanceToken} from "@zerolend/interfaces/IScaledBalanceToken.sol";

contract LeveragePositionManager {
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

    function getMaxEthToSupplyForMaxLTV(address user) public view returns (uint256) {
        // IPool pool = aLentToken.POOL();
        // (uint256 totalCollateralBase, uint256 totalDebtBase, uint256 availableBorrowsBase,) =
        //     pool.getUserAccountData(user);

        // uint256 maxLTV = pool.getConfiguration(address(aLentToken)).getLtv();
        // uint256 ltv = pool.getLtv(address(aLentToken));
        // uint256 maxLTV = pool.MAX_LTV();
        // uint256 ltv = pool.getLtv(address(aLentToken));
        // uint256 maxLTV = pool.MAX_LTV();
        // uint256 ltv = pool.getLtv(address(aLentToken));
    }

    // @param aLentToken: aToken of the lent token
    // @param aBorrowedToken: aToken of the borrowed token
    // @param interestRateMode: true if the interest rate mode is variable, false otherwise: Mode stable (MODE 1) or Mode variable (MODE 2)
    // @notice: args expecting ATokens to be able to check their existence in the protocol
    // @notice: this function is used to take a leveraged position by looping lending and borrowing using the same token
    // @notice: not all prerequisites are checked here (pool liquidity availability, token used as collateral, IRMode, etc.) as it will be called by the core contracts. Only basic prerequisites are checked here (token user's balance and ltv limit to have early revert)
    function takePositionByLentTokenAmount(AToken aToken, uint256 lentTokenAmount, bool interestRateMode) public {

        // @dev: revert if the token is not supported
        revertIfATokenNotSupported(aToken);

        // @dev: check if the token amount held by the user is above the amount to lend
        if (aLentToken.balanceOf(address(this)) < lentTokenAmount) {
            revert InsufficientLentTokenBalance(address(aLentToken), lentTokenAmount);
        }

       // @dev: get the pool address
        IPool pool = aToken.POOL();

        // @dev: get the ltv
        uint256 maxLTV = pool.MAX_LTV();
        
        // @dev: get the resulting ltv for this lent token amount
        uint256 inferedLtv = _getLTVToTargetForThisLentTokenAmount(aToken, msg.sender, lentTokenAmount);

        if (inferedLtv > maxLTV) {
            revert LTVTooHigh(inferedLtv, maxLTV);
        }

        
        // @dev: safe transfer the lent token to the contract
        // aLentToken.underlying().safeTransferFrom(msg.sender, address(this), lentTokenAmount);

        // // @dev: get the pool address

        // // @dev: approve the lent token to be spent by the pool
        // aLentToken.approve(address(pool), lentTokenAmount);

        // // @dev: deposit the lent token into the pool
        // pool.deposit(address(this), lentTokenAmount, msg.sender, 0);

        // uint256 lentTokenAmount = lentToken.balanceOf(address(this));
        // lentToken.approve(address(pool), lentTokenAmount);
        // pool.deposit(address(this), lentTokenAmount, msg.sender, 0);
    }



    //***
    // INTERNAL FUNCTIONS - VIEWERS
    //***


    // @param aToken: aToken to check if it is supported
    // @param ltv: ltv to check. Leave it empty if you want to stick to the max ltv
    // @notice: returns the amount of lent token needed to reach the requested ltv
    // @notice: for the sake of simplicity, the premium for the flashloan is not assessed here. Hence the actual ltv might be lower than expected when the position is taken
    function _getLentTokenAmountToTargetForThisLTV(AToken aToken, address user, uint256 ltv) internal view returns (uint256) {

        revertIfATokenNotSupported(aToken);

        // @dev: get the pool address
        IPool pool = aToken.POOL();

        // @dev: get the ltv
        uint256 maxLTV = pool.MAX_LTV();

        if (ltv > maxLTV) {
            revert LTVTooHigh(ltv, maxLTV);
        }

        if (ltv == 0) {
            ltv = maxLTV;
        }

        // @dev: get the amount of available borrows in base
        uint256 availableBorrowsBase = pool.getUserAccountData(user).availableBorrowsBase;

        // @dev: get the price of the token
        uint256 tokenPrice = priceOracle.getAssetPrice(address(aToken.UNDERLYING()));

        // @dev: get the amount of available borrows in token
        uint256 availableBorrowsInToken = tokenPrice * availableBorrowsBase;

        // @dev: get the amount of lent token to target to reach the ltv
        uint256 inferedTokenAmount = (availableBorrowsInToken * ltv) / (10000 * (10 ** aToken.DECIMALS()));

        return inferedTokenAmount;
    
    }


    // @param aToken: aToken to check if it is supported
    // @param user: user to check
    // @param lentTokenAmount: amount of lent token to check
    // @notice: returns the ltv that will be reached for this lent token amount
    // @notice: for the sake of simplicity, the premium for the flashloan is not assessed here. Hence the actual ltv might be lower than expected when the position is taken
    function _getLTVToTargetForThisLentTokenAmount(AToken aToken, address user, uint256 lentTokenAmount) internal view returns (uint256) {

        revertIfATokenNotSupported(aToken);

        // @dev: get the pool address
        IPool pool = aToken.POOL();
    }
}
