// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";

import {console} from "forge-std/console.sol";

import {ILeveragedPositionManager} from "@src/interfaces/ILeveragedPositionManager.sol";
import {IPool} from "@src/vendors/aaveV3/interfaces/IPool.sol";

import {TestBase} from "@test/utils/TestBase.sol";

contract MoveLeveragedPositionTests is TestBase {
    address internal constant SPARKLEND_POOL = 0xC13e21B648A5Ee794902342038FF3aDAB66BE987;
    address internal aWethSparkToken;
    address internal variableDebtUsdcSparkToken;

    function setUp() public override {
        super.setUp();

        aWethSparkToken = IPool(SPARKLEND_POOL).getReserveData(WETH).aTokenAddress;
        variableDebtUsdcSparkToken = IPool(SPARKLEND_POOL).getReserveData(USDC).variableDebtTokenAddress;

        vm.label(aWethSparkToken, "aWeth Spark Token");
        vm.label(variableDebtUsdcSparkToken, "Variable Debt Usdc Spark Token");
    }

    function test_moveLeveragedPositionFromAavev3ToZerolend() external {
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
        openParams.aaveV3Pool = SPARKLEND_POOL;

        _move(
            closeParams,
            sampleDecreaseLeveragedPositionParams.expectedFeeAmount,
            sampleIncreaseLeveragedPositionParams.bufferAmount,
            openParams,
            sampleIncreaseLeveragedPositionParams.expectedFeeAmount,
            user1
        );

        uint256 wethSuppliedOnAaveV3 = IERC20(aWeth).balanceOf(user1);
        uint256 usdcBorrowedOnAaveV3 = IERC20(variableDebtUsdcToken).balanceOf(user1);
        uint256 wethSuppliedOnSparkLend = IERC20(aWethSparkToken).balanceOf(user1);
        uint256 usdcBorrowedOnSparkLend = IERC20(variableDebtUsdcSparkToken).balanceOf(user1);

        assertEq(wethSuppliedOnAaveV3, 0);
        assertEq(usdcBorrowedOnAaveV3, 0);
        assertEq(
            wethSuppliedOnSparkLend,
            (sampleIncreaseLeveragedPositionParams.wethAmount + sampleIncreaseLeveragedPositionParams.bufferAmount)
        );
        assertEq(usdcBorrowedOnSparkLend, sampleIncreaseLeveragedPositionParams.usdcAmount);
    }
}
