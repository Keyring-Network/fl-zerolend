// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";

import {console} from "forge-std/console.sol";

import {ILeveragedPositionManager} from "@src/interfaces/ILeveragedPositionManager.sol";
import {ICreditDelegationToken} from "@src/vendors/aaveV3/interfaces/ICreditDelegationToken.sol";

import {TestBase} from "@test/utils/TestBase.sol";

contract IncreaseLeveragedPositionTests is TestBase {
    function test_openLeveragedPosition() external {
        ILeveragedPositionManager.TakeLeveragedPosition memory params = ILeveragedPositionManager.TakeLeveragedPosition({
            user: user1,
            supplyToken: WETH,
            borrowToken: USDC,
            amountSupplyToken: sampleIncreaseLeveragedPositionParams.wethAmount,
            bufferAmount: sampleIncreaseLeveragedPositionParams.bufferAmount,
            amountBorrowToken: sampleIncreaseLeveragedPositionParams.usdcAmount,
            uniswapV2Pair: UNISWAP_V2_USDC_WETH_PAIR,
            aaveV3Pool: AAVE_V3_POOL,
            interestRateMode: VARIABLE_INTEREST_RATE_MODE,
            additionalData: ""
        });

        _increaseLeveragedPosition(params, sampleIncreaseLeveragedPositionParams.expectedFeeAmount, user1);

        uint256 wethSupplied = IERC20(aWeth).balanceOf(user1);
        uint256 usdcBorrowed = IERC20(variableDebtUsdcToken).balanceOf(user1);
        uint256 wethFeeCollected = IERC20(WETH).balanceOf(leveragedPositionManager.getFeeCollector());
        uint256 user1WethBalance = IERC20(WETH).balanceOf(user1);

        assertEq(
            wethSupplied,
            (sampleIncreaseLeveragedPositionParams.wethAmount + sampleIncreaseLeveragedPositionParams.bufferAmount)
        );
        assertEq(usdcBorrowed, sampleIncreaseLeveragedPositionParams.usdcAmount);
        assertEq(wethFeeCollected, sampleIncreaseLeveragedPositionParams.expectedFeeAmount);
        assertEq(user1WethBalance, 0);
    }

    function test_addToOpenLeveragedPosition() external {
        ILeveragedPositionManager.TakeLeveragedPosition memory params = ILeveragedPositionManager.TakeLeveragedPosition({
            user: user1,
            supplyToken: WETH,
            borrowToken: USDC,
            amountSupplyToken: sampleIncreaseLeveragedPositionParams.wethAmount,
            bufferAmount: sampleIncreaseLeveragedPositionParams.bufferAmount,
            amountBorrowToken: sampleIncreaseLeveragedPositionParams.usdcAmount,
            uniswapV2Pair: UNISWAP_V2_USDC_WETH_PAIR,
            aaveV3Pool: AAVE_V3_POOL,
            interestRateMode: VARIABLE_INTEREST_RATE_MODE,
            additionalData: ""
        });

        _increaseLeveragedPosition(params, sampleIncreaseLeveragedPositionParams.expectedFeeAmount, user1);
        _increaseLeveragedPosition(params, sampleIncreaseLeveragedPositionParams.expectedFeeAmount, user1);

        uint256 wethSupplied = IERC20(aWeth).balanceOf(user1);
        uint256 usdcBorrowed = IERC20(variableDebtUsdcToken).balanceOf(user1);
        uint256 wethFeeCollected = IERC20(WETH).balanceOf(leveragedPositionManager.getFeeCollector());
        uint256 user1WethBalance = IERC20(WETH).balanceOf(user1);

        assertApproxEqAbs(
            wethSupplied,
            (
                (sampleIncreaseLeveragedPositionParams.wethAmount + sampleIncreaseLeveragedPositionParams.bufferAmount)
                    * 2
            ),
            100
        );
        assertApproxEqAbs(usdcBorrowed, sampleIncreaseLeveragedPositionParams.usdcAmount * 2, 100);
        assertEq(wethFeeCollected, sampleIncreaseLeveragedPositionParams.expectedFeeAmount * 2);
        assertEq(user1WethBalance, 0);
    }

    function test_cannotGoOverMaxLeverage() external {
        ILeveragedPositionManager.TakeLeveragedPosition memory params = ILeveragedPositionManager.TakeLeveragedPosition({
            user: user1,
            supplyToken: WETH,
            borrowToken: USDC,
            amountSupplyToken: sampleIncreaseLeveragedPositionParams.wethAmount,
            bufferAmount: sampleIncreaseLeveragedPositionParams.bufferAmount,
            amountBorrowToken: sampleIncreaseLeveragedPositionParams.usdcAmount * 2,
            uniswapV2Pair: UNISWAP_V2_USDC_WETH_PAIR,
            aaveV3Pool: AAVE_V3_POOL,
            interestRateMode: VARIABLE_INTEREST_RATE_MODE,
            additionalData: ""
        });

        deal(params.supplyToken, user1, params.bufferAmount + sampleIncreaseLeveragedPositionParams.expectedFeeAmount);

        vm.startPrank(user1);
        IERC20(params.supplyToken).approve(
            address(leveragedPositionManager),
            params.bufferAmount + sampleIncreaseLeveragedPositionParams.expectedFeeAmount
        );
        ICreditDelegationToken(variableDebtUsdcToken).approveDelegation(
            address(leveragedPositionManager), params.amountBorrowToken
        );

        vm.expectRevert();
        leveragedPositionManager.increaseLeveragedPosition(params);
        vm.stopPrank();
    }

    function test_openLeveragedPositionWithoutFees() external {
        _setFees(0);

        ILeveragedPositionManager.TakeLeveragedPosition memory params = ILeveragedPositionManager.TakeLeveragedPosition({
            user: user1,
            supplyToken: WETH,
            borrowToken: USDC,
            amountSupplyToken: sampleIncreaseLeveragedPositionParams.wethAmount,
            bufferAmount: sampleIncreaseLeveragedPositionParams.bufferAmount,
            amountBorrowToken: sampleIncreaseLeveragedPositionParams.usdcAmount,
            uniswapV2Pair: UNISWAP_V2_USDC_WETH_PAIR,
            aaveV3Pool: AAVE_V3_POOL,
            interestRateMode: VARIABLE_INTEREST_RATE_MODE,
            additionalData: ""
        });

        _increaseLeveragedPosition(params, sampleIncreaseLeveragedPositionParams.expectedFeeAmount, user1);

        uint256 wethFeeCollected = IERC20(WETH).balanceOf(leveragedPositionManager.getFeeCollector());

        assertEq(wethFeeCollected, 0);
    }
}
