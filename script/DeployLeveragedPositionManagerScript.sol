// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import "../src/LeveragedPositionManager.sol";
import "../dependencies/forge-std-1.9.6/src/Script.sol";

contract DeployLeveragedPositionManagerScript is Script {
    function run() public {
        vm.startBroadcast();
        address poolAddressesProviderRegistry = makeAddr(vm.envString("POOL_ADDRESSES_PROVIDER_REGISTRY_ADDRESS"));

        new LeveragedPositionManager(poolAddressesProviderRegistry);
        vm.stopBroadcast();
    }
}
