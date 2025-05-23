// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {console} from "forge-std/console.sol";

import {IFeeCollector} from "@src/interfaces/IFeeCollector.sol";

import {TestBase} from "@test/utils/TestBase.sol";

contract InitializationTests is TestBase {
    address internal constant ZERO_ADDRESS = address(0);

    function test_checkLeveragedPositionManagerInitialization() external view {
        assertEq(leveragedPositionManager.getUniswapV2Factory(), UNISWAP_V2_FACTORY);
        assertNotEq(leveragedPositionManager.getFeeCollector(), ZERO_ADDRESS);
        assertEq(leveragedPositionManager.getFeeInBps(), feeInBps);
        assertEq(leveragedPositionManager.checkAccumulatedFees(WETH), 0);
        assertEq(leveragedPositionManager.checkAccumulatedFees(USDC), 0);
    }

    function test_checkFeeCollectorInitialization() external view {
        address feeCollector = leveragedPositionManager.getFeeCollector();

        assertEq(IFeeCollector(feeCollector).getLeveragedPositionManager(), address(leveragedPositionManager));
    }
}
