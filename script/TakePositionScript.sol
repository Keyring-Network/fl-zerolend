// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script, console} from "forge-std/Script.sol";
import {LeveragePositionManager} from "../src/LeveragePositionManager.sol";
import {IPoolAddressesProviderRegistry} from "@zerolend/interfaces/IPoolAddressesProviderRegistry.sol";
import {IPoolAddressesProvider} from "@zerolend/interfaces/IPoolAddressesProvider.sol";
import {IPool} from "@zerolend/interfaces/IPool.sol";
import {IERC20Detailed as IERC20} from "@zerolend/dependencies/openzeppelin/contracts/IERC20Detailed.sol";
import {DataTypes} from "@zerolend/protocol/libraries/types/DataTypes.sol";
import {AToken} from "@zerolend/protocol/tokenization/AToken.sol";

contract TakePositionScript is Script {
    function run() public {
        address poolAddressesProviderRegistryAddress =
            vm.parseAddress(vm.envString("POOL_ADDRESSES_PROVIDER_REGISTRY_ADDRESS"));
        LeveragePositionManager leveragePositionManager =
            new LeveragePositionManager(poolAddressesProviderRegistryAddress);
        address[] memory poolAdressesProviders =
            IPoolAddressesProviderRegistry(poolAddressesProviderRegistryAddress).getAddressesProvidersList();

        IPoolAddressesProvider poolAdressesProvider;
        AToken aToken;
        for (uint256 i = 0; i < poolAdressesProviders.length; i++) {
            poolAdressesProvider = IPoolAddressesProvider(poolAdressesProviders[i]);
            IPool pool = IPool(poolAdressesProvider.getPool());
            console.log("poolAdressesProvider:", address(poolAdressesProvider));
            console.log("pool:", address(pool));
            IERC20 underlyingToken;
            for (uint256 j = 0; j < pool.getReservesList().length; j++) {
                underlyingToken = IERC20(pool.getReservesList()[j]);
                console.log("Underlying token:", underlyingToken.name());
                console.log("    Symbol:", underlyingToken.symbol());
                console.log("    Decimals:", underlyingToken.decimals());
                console.log("    Address:", address(underlyingToken));

                DataTypes.ReserveData memory reserveData = pool.getReserveData(address(underlyingToken));
                console.log("    Reserve LiquidityRate:", reserveData.currentLiquidityRate);
                console.log("    Reserve VariableBorrowRate:", reserveData.currentVariableBorrowRate);
                console.log("    Reserve StableBorrowRate:", reserveData.currentStableBorrowRate);
                console.log("    Reserve LastUpdateTimestamp:", reserveData.lastUpdateTimestamp);
                console.log("    Reserve Id:", reserveData.id);
                console.log("    Reserve ATokenAddress:", reserveData.aTokenAddress);
                console.log("    Reserve StableDebtTokenAddress:", reserveData.stableDebtTokenAddress);
                console.log("    Reserve VariableDebtTokenAddress:", reserveData.variableDebtTokenAddress);
                console.log("    Reserve LiquidityIndex:", reserveData.liquidityIndex);
                AToken aToken = AToken(reserveData.aTokenAddress);
                leveragePositionManager.revertIfATokenNotSupported(aToken);
                console.log("    AToken supported:", "yes");
                DataTypes.ReserveConfigurationMap memory reserveConfig = pool.getConfiguration(address(aToken));
                console.log("    Reserve LTV:", reserveConfig.getLtv());
                console.log("    Reserve Liquidation Threshold:", reserveConfig.getLiquidationThreshold());
                console.log("    Reserve Liquidation Bonus:", reserveConfig.getLiquidationBonus());
            }
        }
    }
}
