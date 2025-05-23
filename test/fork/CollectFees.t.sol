// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";

import {console} from "forge-std/console.sol";

import {ILeveragedPositionManager} from "@src/interfaces/ILeveragedPositionManager.sol";
import {ICreditDelegationToken} from "@src/vendors/aaveV3/interfaces/ICreditDelegationToken.sol";
import {IFeeCollector} from "@src/interfaces/IFeeCollector.sol";

import {TestBase} from "@test/utils/TestBase.sol";

contract CollectFeesTests is TestBase {
    function test_collectFeesFromIncreasingLeveragedPosition() external {
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

        vm.startPrank(owner);
        leveragedPositionManager.collectFees(WETH, wethFeeCollected, owner);
        vm.stopPrank();

        uint256 ownerWethBalance = IERC20(WETH).balanceOf(owner);

        assertEq(ownerWethBalance, wethFeeCollected);
    }

    function test_collectFeesFromDecreasingLeveragedPosition() external {
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

        vm.startPrank(owner);
        leveragedPositionManager.collectFees(USDC, usdcFeeCollected, owner);
        vm.stopPrank();

        uint256 ownerUsdcBalance = IERC20(USDC).balanceOf(owner);

        assertEq(ownerUsdcBalance, usdcFeeCollected);
    }

    function test_collectingMoreFeesThanWhatHasAccruedFails() external {
        uint256 amountToCollect = 1 * 10 ** IERC20Metadata(WETH).decimals();

        vm.startPrank(owner);
        vm.expectRevert();
        leveragedPositionManager.collectFees(WETH, amountToCollect, user1);
        vm.stopPrank();
    }

    function test_onlyLeveragedPositionManagerCanWithdrawFees() external {
        uint256 amountToCollect = 1 * IERC20Metadata(WETH).decimals();
        address feeCollector = leveragedPositionManager.getFeeCollector();

        vm.startPrank(owner);
        vm.expectRevert(IFeeCollector.FeeCollector__NotLeveragedPositionManager.selector);
        IFeeCollector(feeCollector).withdrawFees(WETH, amountToCollect, user1);
        vm.stopPrank();
    }
}
