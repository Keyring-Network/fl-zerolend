// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import {Script} from "forge-std/Script.sol";

import {LeveragedPositionManager} from "@src/LeveragedPositionManager.sol";

contract DeployLeveragedPositionManager is Script {
    address private uniswapV2Factory;
    address private owner;
    uint16 private feeInBps;

    function setUp() public {
        uniswapV2Factory = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
        owner = msg.sender;
        feeInBps = 50;
    }

    function run() public returns (LeveragedPositionManager) {
        vm.startBroadcast();

        LeveragedPositionManager leveragedPositionManager =
            new LeveragedPositionManager(uniswapV2Factory, owner, feeInBps);

        vm.stopBroadcast();

        return leveragedPositionManager;
    }
}
