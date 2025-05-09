// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import {Script} from "forge-std/Script.sol";

import {LeveragedPositionManager} from "@src/LeveragedPositionManager.sol";

contract DeployLeveragedPositionManager is Script {
    function run() public returns (LeveragedPositionManager) {
        vm.startBroadcast();

        LeveragedPositionManager leveragedPositionManager = new LeveragedPositionManager();

        vm.stopBroadcast();

        return leveragedPositionManager;
    }
}
