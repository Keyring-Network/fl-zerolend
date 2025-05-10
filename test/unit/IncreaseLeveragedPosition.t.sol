// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";

import {console} from "forge-std/console.sol";

import {ILeveragedPositionManager} from "@src/interfaces/ILeveragedPositionManager.sol";
import {ICreditDelegationToken} from "@src/vendors/aaveV3/interfaces/ICreditDelegationToken.sol";

import {TestBase} from "@test/utils/TestBase.sol";

contract IncreaseLeveragedPositionTests is TestBase {
    function test_openLeveragedPosition() external {
        uint256 wethAmount = 5 * 10 ** (IERC20Metadata(weth).decimals() - 1);
        uint256 usdcAmount = 1_200 * 10 ** IERC20Metadata(usdc).decimals();
        uint256 expectedWethFeeAmount = (wethAmount * 2 * leveragedPositionManager.getFeeInBps()) / BPS;

        ILeveragedPositionManager.TakeLeveragedPosition memory params = ILeveragedPositionManager.TakeLeveragedPosition({
            user: user1,
            supplyToken: weth,
            borrowToken: usdc,
            amountSupplyToken: wethAmount,
            bufferAmount: wethAmount,
            amountBorrowToken: usdcAmount,
            uniswapV2Pair: uniswapUsdcWethPair,
            aaveV3Pool: aaveV3Pool,
            interestRateMode: 2,
            additionalData: ""
        });

        _increaseLeveragedPosition(params, user1);

        uint256 wethSupplied = IERC20(aWeth).balanceOf(user1);
        uint256 usdcBorrowed = IERC20(variableDebtUsdcToken).balanceOf(user1);
        uint256 tolerablePrecisionLoss = 100;

        assertApproxEqAbs(wethSupplied, (wethAmount * 2) - expectedWethFeeAmount, tolerablePrecisionLoss);
        assertApproxEqAbs(usdcBorrowed, usdcAmount, tolerablePrecisionLoss);
    }

    function test_addToOpenLeveragedPosition() external {
        uint256 wethAmount = 5 * 10 ** (IERC20Metadata(weth).decimals() - 1);
        uint256 usdcAmount = 1_200 * 10 ** IERC20Metadata(usdc).decimals();
        uint256 expectedWethFeeAmount = (wethAmount * 4 * leveragedPositionManager.getFeeInBps()) / BPS;

        ILeveragedPositionManager.TakeLeveragedPosition memory params = ILeveragedPositionManager.TakeLeveragedPosition({
            user: user1,
            supplyToken: weth,
            borrowToken: usdc,
            amountSupplyToken: wethAmount,
            bufferAmount: wethAmount,
            amountBorrowToken: usdcAmount,
            uniswapV2Pair: uniswapUsdcWethPair,
            aaveV3Pool: aaveV3Pool,
            interestRateMode: 2,
            additionalData: ""
        });

        _increaseLeveragedPosition(params, user1);
        _increaseLeveragedPosition(params, user1);

        uint256 wethSupplied = IERC20(aWeth).balanceOf(user1);
        uint256 usdcBorrowed = IERC20(variableDebtUsdcToken).balanceOf(user1);
        uint256 tolerablePrecisionLoss = 100;

        assertApproxEqAbs(wethSupplied, (wethAmount * 4) - expectedWethFeeAmount, tolerablePrecisionLoss);
        assertApproxEqAbs(usdcBorrowed, usdcAmount * 2, tolerablePrecisionLoss);
    }
}
