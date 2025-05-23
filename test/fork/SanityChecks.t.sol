// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";

import {console} from "forge-std/console.sol";

import {ILeveragedPositionManager} from "@src/interfaces/ILeveragedPositionManager.sol";
import {ICreditDelegationToken} from "@src/vendors/aaveV3/interfaces/ICreditDelegationToken.sol";

import {TestBase} from "@test/utils/TestBase.sol";
import {MaliciousUniswapV2Pair} from "@test/utils/MaliciousUniswapV2Pair.sol";

contract SanityChecksTests is TestBase {
    address internal constant UNISWAP_V2_WBTC_UDST_PAIR = 0x0DE0Fa91b6DbaB8c8503aAA2D1DFa91a192cB149;
    address internal constant UNISWAP_V2_PEPE_WETH_PAIR = 0xA43fe16908251ee70EF74718545e4FE6C5cCEc9f;
    address internal constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address internal constant PEPE = 0x6982508145454Ce325dDbE47a25d4ec3d2311933;

    function test_managingLeveragedPositionsWithInvalidUniswapV2PairFails() external {
        ILeveragedPositionManager.TakeLeveragedPosition memory params = ILeveragedPositionManager.TakeLeveragedPosition({
            user: user1,
            supplyToken: WETH,
            borrowToken: USDC,
            amountSupplyToken: sampleIncreaseLeveragedPositionParams.wethAmount,
            bufferAmount: sampleIncreaseLeveragedPositionParams.bufferAmount,
            amountBorrowToken: sampleIncreaseLeveragedPositionParams.usdcAmount,
            uniswapV2Pair: UNISWAP_V2_WBTC_UDST_PAIR,
            aaveV3Pool: AAVE_V3_POOL,
            interestRateMode: VARIABLE_INTEREST_RATE_MODE,
            additionalData: ""
        });

        vm.expectRevert(ILeveragedPositionManager.LeveragedPositionManager__InvalidUniswapV2Pair.selector);
        vm.startPrank(user1);
        leveragedPositionManager.increaseLeveragedPosition(params);
        vm.stopPrank();

        vm.expectRevert(ILeveragedPositionManager.LeveragedPositionManager__InvalidUniswapV2Pair.selector);
        vm.startPrank(user1);
        leveragedPositionManager.decreaseLeveragedPosition(params);
        vm.stopPrank();
    }

    function test_managingLeveragedPositionsWithInvalidAaveV3PoolFails() external {
        ILeveragedPositionManager.TakeLeveragedPosition memory params = ILeveragedPositionManager.TakeLeveragedPosition({
            user: user1,
            supplyToken: PEPE,
            borrowToken: WETH,
            amountSupplyToken: sampleIncreaseLeveragedPositionParams.wethAmount,
            bufferAmount: sampleIncreaseLeveragedPositionParams.bufferAmount,
            amountBorrowToken: sampleIncreaseLeveragedPositionParams.usdcAmount,
            uniswapV2Pair: UNISWAP_V2_PEPE_WETH_PAIR,
            aaveV3Pool: AAVE_V3_POOL,
            interestRateMode: VARIABLE_INTEREST_RATE_MODE,
            additionalData: ""
        });

        vm.expectRevert(ILeveragedPositionManager.LeveragedPositionManager__InvalidAaveV3Pool.selector);
        vm.startPrank(user1);
        leveragedPositionManager.increaseLeveragedPosition(params);
        vm.stopPrank();

        vm.expectRevert(ILeveragedPositionManager.LeveragedPositionManager__InvalidAaveV3Pool.selector);
        vm.startPrank(user1);
        leveragedPositionManager.decreaseLeveragedPosition(params);
        vm.stopPrank();
    }

    function test_invokingFlashSwapCallbackAsNonUniswapV2PairFails() external {
        MaliciousUniswapV2Pair maliciousPair = new MaliciousUniswapV2Pair(USDC, WETH);

        ILeveragedPositionManager.TakeLeveragedPosition memory params = ILeveragedPositionManager.TakeLeveragedPosition({
            user: address(maliciousPair),
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
        bytes memory encodedCall = abi.encodeWithSelector(
            leveragedPositionManager.uniswapV2Call.selector,
            address(maliciousPair),
            USDC,
            WETH,
            abi.encode(params, ILeveragedPositionManager.Direction.INCREASE)
        );

        vm.expectRevert(MaliciousUniswapV2Pair.MaliciousUniswapV2Pair__CallFailed.selector);
        maliciousPair.externalCall(address(leveragedPositionManager), encodedCall, 0);
    }

    function test_managingSomeoneElsesLeveragedPositionFails() external {
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

        deal(params.supplyToken, user1, params.bufferAmount + sampleIncreaseLeveragedPositionParams.expectedFeeAmount);

        vm.startPrank(user1);
        IERC20(params.supplyToken).approve(
            address(leveragedPositionManager),
            params.bufferAmount + sampleIncreaseLeveragedPositionParams.expectedFeeAmount
        );
        ICreditDelegationToken(variableDebtUsdcToken).approveDelegation(
            address(leveragedPositionManager), params.amountBorrowToken
        );
        vm.stopPrank();

        vm.expectRevert(ILeveragedPositionManager.LeveragedPositionManager__CallerNotPositionOwner.selector);
        leveragedPositionManager.increaseLeveragedPosition(params);
    }
}
