// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";

import {console} from "forge-std/console.sol";

import {ILeveragedPositionManager} from "@src/interfaces/ILeveragedPositionManager.sol";
import {ICreditDelegationToken} from "@src/vendors/aaveV3/interfaces/ICreditDelegationToken.sol";
import {IPool} from "@src/vendors/aaveV3/interfaces/IPool.sol";

import {TestBase} from "@test/utils/TestBase.sol";

contract PermitPositionManagementTests is TestBase {
    function test_settingOperators() external {
        _setOperator(user1, owner, true);

        assertTrue(leveragedPositionManager.isPermittedPositionManager(user1, owner));

        _setOperator(user1, owner, false);

        assertFalse(leveragedPositionManager.isPermittedPositionManager(user1, owner));
    }

    function test_openLeveragedPositionAsOperator() external {
        _setOperator(user1, owner, true);

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

        deal(params.supplyToken, owner, params.bufferAmount + sampleIncreaseLeveragedPositionParams.expectedFeeAmount);

        vm.startPrank(user1);
        ICreditDelegationToken(variableDebtUsdcToken).approveDelegation(
            address(leveragedPositionManager), params.amountBorrowToken
        );
        vm.stopPrank();

        vm.startPrank(owner);
        IERC20(params.supplyToken).approve(
            address(leveragedPositionManager),
            params.bufferAmount + sampleIncreaseLeveragedPositionParams.expectedFeeAmount
        );

        leveragedPositionManager.increaseLeveragedPosition(params);
        vm.stopPrank();

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

    function test_closeLeveragedPositionAsOperator() external {
        _setOperator(user1, owner, true);

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

        (uint256 approvedATokenAmount, uint256 supplyTokenBufferAmount) =
            abi.decode(closeParams.additionalData, (uint256, uint256));

        vm.startPrank(user1);
        IERC20(aWeth).approve(address(leveragedPositionManager), approvedATokenAmount);
        deal(closeParams.supplyToken, user1, supplyTokenBufferAmount);
        IERC20(closeParams.supplyToken).approve(address(leveragedPositionManager), supplyTokenBufferAmount);
        vm.stopPrank();

        vm.startPrank(owner);
        deal(
            closeParams.borrowToken,
            owner,
            closeParams.bufferAmount + sampleDecreaseLeveragedPositionParams.expectedFeeAmount
        );
        IERC20(closeParams.borrowToken).approve(
            address(leveragedPositionManager),
            closeParams.bufferAmount + sampleDecreaseLeveragedPositionParams.expectedFeeAmount
        );

        leveragedPositionManager.decreaseLeveragedPosition(closeParams);
        vm.stopPrank();

        uint256 wethSupplied = IERC20(aWeth).balanceOf(user1);
        uint256 usdcBorrowed = IERC20(variableDebtUsdcToken).balanceOf(user1);
        uint256 usdcFeeCollected = IERC20(USDC).balanceOf(leveragedPositionManager.getFeeCollector());
        uint256 tolerablePrecisionLoss = 100;

        assertApproxEqAbs(wethSupplied, sampleIncreaseLeveragedPositionParams.bufferAmount, tolerablePrecisionLoss);
        assertApproxEqAbs(usdcBorrowed, 0, tolerablePrecisionLoss);
        assertEq(usdcFeeCollected, sampleDecreaseLeveragedPositionParams.expectedFeeAmount);
    }
}
