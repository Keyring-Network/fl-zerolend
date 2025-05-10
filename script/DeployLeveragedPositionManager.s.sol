// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import {Script} from "forge-std/Script.sol";

import {LeveragedPositionManager} from "@src/LeveragedPositionManager.sol";

contract DeployLeveragedPositionManager is Script {
    address private owner;
    uint16 private feeInBps;

    function setUp() public {
        owner = msg.sender;
        feeInBps = 50;
    }

    function run() public returns (LeveragedPositionManager) {
        vm.startBroadcast();

        LeveragedPositionManager leveragedPositionManager = new LeveragedPositionManager(owner, feeInBps);

        vm.stopBroadcast();

        return leveragedPositionManager;
    }
}
