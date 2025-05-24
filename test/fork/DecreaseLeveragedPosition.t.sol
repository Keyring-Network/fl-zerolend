// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";

import {console} from "forge-std/console.sol";

import {ILeveragedPositionManager} from "@src/interfaces/ILeveragedPositionManager.sol";
import {ICreditDelegationToken} from "@src/vendors/aaveV3/interfaces/ICreditDelegationToken.sol";

import {TestBase} from "@test/utils/TestBase.sol";

contract DecreaseLeveragedPositionTests is TestBase {
    function test_closeLeveragedPosition() external {
        ILeveragedPositionManager.TakeLeveragedPosition memory openParams = ILeveragedPositionManager
            .TakeLeveragedPosition({
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

        _increaseLeveragedPosition(openParams, sampleIncreaseLeveragedPositionParams.expectedFeeAmount, user1);

        uint256 wethBufferAmount = 1 * 10 ** (IERC20Metadata(WETH).decimals() - 2);
        ILeveragedPositionManager.TakeLeveragedPosition memory closeParams = ILeveragedPositionManager
            .TakeLeveragedPosition({
            user: user1,
            supplyToken: WETH,
            borrowToken: USDC,
            amountSupplyToken: sampleDecreaseLeveragedPositionParams.wethAmount,
            bufferAmount: sampleDecreaseLeveragedPositionParams.bufferAmount,
            amountBorrowToken: sampleDecreaseLeveragedPositionParams.usdcAmount,
            uniswapV2Pair: UNISWAP_V2_USDC_WETH_PAIR,
            aaveV3Pool: AAVE_V3_POOL,
            interestRateMode: VARIABLE_INTEREST_RATE_MODE,
            additionalData: abi.encode(sampleIncreaseLeveragedPositionParams.wethAmount, wethBufferAmount)
        });

        _decreaseLeveragedPosition(closeParams, sampleDecreaseLeveragedPositionParams.expectedFeeAmount, user1);

        uint256 wethSupplied = IERC20(aWeth).balanceOf(user1);
        uint256 usdcBorrowed = IERC20(variableDebtUsdcToken).balanceOf(user1);
        uint256 usdcFeeCollected = IERC20(USDC).balanceOf(leveragedPositionManager.getFeeCollector());
        uint256 tolerablePrecisionLoss = 100;

        assertApproxEqAbs(wethSupplied, sampleIncreaseLeveragedPositionParams.bufferAmount, tolerablePrecisionLoss);
        assertApproxEqAbs(usdcBorrowed, 0, tolerablePrecisionLoss);
        assertEq(usdcFeeCollected, sampleDecreaseLeveragedPositionParams.expectedFeeAmount);
    }

    function test_decreaseLeveragedPosition() external {
        ILeveragedPositionManager.TakeLeveragedPosition memory openParams = ILeveragedPositionManager
            .TakeLeveragedPosition({
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

        _increaseLeveragedPosition(openParams, sampleIncreaseLeveragedPositionParams.expectedFeeAmount, user1);

        uint256 wethBufferAmount = 1 * 10 ** (IERC20Metadata(WETH).decimals() - 2);
        ILeveragedPositionManager.TakeLeveragedPosition memory closeParams = ILeveragedPositionManager
            .TakeLeveragedPosition({
            user: user1,
            supplyToken: WETH,
            borrowToken: USDC,
            amountSupplyToken: sampleDecreaseLeveragedPositionParams.wethAmount / 2,
            bufferAmount: sampleDecreaseLeveragedPositionParams.bufferAmount / 2,
            amountBorrowToken: sampleDecreaseLeveragedPositionParams.usdcAmount / 2,
            uniswapV2Pair: UNISWAP_V2_USDC_WETH_PAIR,
            aaveV3Pool: AAVE_V3_POOL,
            interestRateMode: VARIABLE_INTEREST_RATE_MODE,
            additionalData: abi.encode(sampleIncreaseLeveragedPositionParams.wethAmount, wethBufferAmount)
        });

        _decreaseLeveragedPosition(closeParams, sampleDecreaseLeveragedPositionParams.expectedFeeAmount / 2, user1);

        uint256 wethSupplied = IERC20(aWeth).balanceOf(user1);
        uint256 usdcBorrowed = IERC20(variableDebtUsdcToken).balanceOf(user1);
        uint256 usdcFeeCollected = IERC20(USDC).balanceOf(leveragedPositionManager.getFeeCollector());
        uint256 tolerablePrecisionLoss = 100;

        assertApproxEqAbs(
            wethSupplied, (sampleIncreaseLeveragedPositionParams.bufferAmount * 3) / 2, tolerablePrecisionLoss
        );
        assertApproxEqAbs(usdcBorrowed, sampleDecreaseLeveragedPositionParams.usdcAmount / 2, tolerablePrecisionLoss);
        assertEq(usdcFeeCollected, sampleDecreaseLeveragedPositionParams.expectedFeeAmount / 2);
    }

    function test_decreaseLeveragedPositionByWithdrawingMoreThanAllowedFails() external {
        ILeveragedPositionManager.TakeLeveragedPosition memory openParams = ILeveragedPositionManager
            .TakeLeveragedPosition({
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

        _increaseLeveragedPosition(openParams, sampleIncreaseLeveragedPositionParams.expectedFeeAmount, user1);

        uint256 wethBufferAmount = 1 * 10 ** (IERC20Metadata(WETH).decimals() - 2);
        ILeveragedPositionManager.TakeLeveragedPosition memory closeParams = ILeveragedPositionManager
            .TakeLeveragedPosition({
            user: user1,
            supplyToken: WETH,
            borrowToken: USDC,
            amountSupplyToken: sampleDecreaseLeveragedPositionParams.wethAmount * 2,
            bufferAmount: sampleDecreaseLeveragedPositionParams.bufferAmount / 2,
            amountBorrowToken: sampleDecreaseLeveragedPositionParams.usdcAmount / 2,
            uniswapV2Pair: UNISWAP_V2_USDC_WETH_PAIR,
            aaveV3Pool: AAVE_V3_POOL,
            interestRateMode: VARIABLE_INTEREST_RATE_MODE,
            additionalData: abi.encode(sampleIncreaseLeveragedPositionParams.wethAmount, wethBufferAmount)
        });

        vm.startPrank(user1);
        deal(
            closeParams.borrowToken,
            user1,
            closeParams.bufferAmount + sampleDecreaseLeveragedPositionParams.expectedFeeAmount / 2
        );
        IERC20(closeParams.borrowToken).approve(
            address(leveragedPositionManager),
            closeParams.bufferAmount + sampleDecreaseLeveragedPositionParams.expectedFeeAmount / 2
        );

        (uint256 approvedATokenAmount, uint256 supplyTokenBufferAmount) =
            abi.decode(closeParams.additionalData, (uint256, uint256));
        IERC20(aUsdc).approve(address(leveragedPositionManager), approvedATokenAmount);

        deal(closeParams.supplyToken, user1, supplyTokenBufferAmount);
        IERC20(closeParams.supplyToken).approve(address(leveragedPositionManager), supplyTokenBufferAmount);

        vm.expectRevert();
        leveragedPositionManager.decreaseLeveragedPosition(closeParams);
        vm.stopPrank();
    }

    function test_closeLeveragedPositionWithoutFees() external {
        _setFees(0);

        ILeveragedPositionManager.TakeLeveragedPosition memory openParams = ILeveragedPositionManager
            .TakeLeveragedPosition({
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

        _increaseLeveragedPosition(openParams, sampleIncreaseLeveragedPositionParams.expectedFeeAmount, user1);

        uint256 wethBufferAmount = 1 * 10 ** (IERC20Metadata(WETH).decimals() - 2);
        ILeveragedPositionManager.TakeLeveragedPosition memory closeParams = ILeveragedPositionManager
            .TakeLeveragedPosition({
            user: user1,
            supplyToken: WETH,
            borrowToken: USDC,
            amountSupplyToken: sampleDecreaseLeveragedPositionParams.wethAmount,
            bufferAmount: sampleDecreaseLeveragedPositionParams.bufferAmount,
            amountBorrowToken: sampleDecreaseLeveragedPositionParams.usdcAmount,
            uniswapV2Pair: UNISWAP_V2_USDC_WETH_PAIR,
            aaveV3Pool: AAVE_V3_POOL,
            interestRateMode: VARIABLE_INTEREST_RATE_MODE,
            additionalData: abi.encode(sampleIncreaseLeveragedPositionParams.wethAmount, wethBufferAmount)
        });

        _decreaseLeveragedPosition(closeParams, sampleDecreaseLeveragedPositionParams.expectedFeeAmount, user1);

        uint256 usdcFeeCollected = IERC20(USDC).balanceOf(leveragedPositionManager.getFeeCollector());

        assertEq(usdcFeeCollected, 0);
    }
}
