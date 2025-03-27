// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script, console} from "forge-std/Script.sol";
import {ERC20} from "@zerolend/dependencies/openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IPoolAddressesProviderRegistry} from "@zerolend/interfaces/IPoolAddressesProviderRegistry.sol";
import {IPoolAddressesProvider} from "@zerolend/interfaces/IPoolAddressesProvider.sol";
import {IPool} from "@zerolend/interfaces/IPool.sol";
import {IPoolConfigurator} from "@zerolend/interfaces/IPoolConfigurator.sol";
import {IPriceOracle} from "@zerolend/interfaces/IPriceOracle.sol";
import {IAToken} from "@zerolend/interfaces/IAToken.sol";
import {IStableDebtToken} from "@zerolend/interfaces/IStableDebtToken.sol";
import {IVariableDebtToken} from "@zerolend/interfaces/IVariableDebtToken.sol";
import {ReservesSetupHelper} from "@zerolend/deployments/ReservesSetupHelper.sol";
import {Pool} from "@zerolend/protocol/pool/Pool.sol";
import {PoolConfigurator} from "@zerolend/protocol/pool/PoolConfigurator.sol";
import {PoolAddressesProvider} from "@zerolend/protocol/configuration/PoolAddressesProvider.sol";
import {PoolAddressesProviderRegistry} from "@zerolend/protocol/configuration/PoolAddressesProviderRegistry.sol";
import {AaveOracle} from "@zerolend/protocol/oracle/AaveOracle.sol";

contract DeployMockScript is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Deploy WETH and USDC
        ERC20 weth = new ERC20("Wrapped Ether", "WETH");
        console.log("WETH deployed at:", address(weth));

        ERC20 usdc = new ERC20("USD Coin", "USDC");
        console.log("USDC deployed at:", address(usdc));

        // Deploy core protocol contracts
        PoolAddressesProviderRegistry registry = new PoolAddressesProviderRegistry();
        console.log("PoolAddressesProviderRegistry deployed at:", address(registry));

        PoolAddressesProvider provider = new PoolAddressesProvider("ZeroLend Market", address(registry));
        console.log("PoolAddressesProvider deployed at:", address(provider));

        AaveOracle oracle = new AaveOracle(address(provider), new address[](0), new address[](0));
        console.log("Oracle deployed at:", address(oracle));

        Pool pool = new Pool(provider);
        console.log("Pool deployed at:", address(pool));

        PoolConfigurator configurator = new PoolConfigurator();
        console.log("PoolConfigurator deployed at:", address(configurator));

        // Configure the protocol
        provider.setPoolImpl(address(pool));
        provider.setPoolConfiguratorImpl(address(configurator));
        provider.setPriceOracle(address(oracle));

        // Register the provider
        registry.registerAddressesProvider(address(provider), 1);

        // Set up reserves
        ReservesSetupHelper setupHelper = new ReservesSetupHelper();
        console.log("ReservesSetupHelper deployed at:", address(setupHelper));

        ReservesSetupHelper.ConfigureReserveInput[] memory configs = new ReservesSetupHelper.ConfigureReserveInput[](2);
        
        // Configure WETH
        configs[0] = ReservesSetupHelper.ConfigureReserveInput({
            asset: address(weth),
            baseLTV: 8000, // 80%
            liquidationThreshold: 8250, // 82.5%
            liquidationBonus: 10500, // 5%
            reserveFactor: 1000, // 1%
            borrowCap: 1000 ether,
            supplyCap: 10000 ether,
            stableBorrowingEnabled: true,
            borrowingEnabled: true,
            flashLoanEnabled: true
        });

        // Configure USDC
        configs[1] = ReservesSetupHelper.ConfigureReserveInput({
            asset: address(usdc),
            baseLTV: 8500, // 85%
            liquidationThreshold: 8750, // 87.5%
            liquidationBonus: 10500, // 5%
            reserveFactor: 1000, // 1%
            borrowCap: 1000000 * 1e6, // 1M USDC
            supplyCap: 10000000 * 1e6, // 10M USDC
            stableBorrowingEnabled: true,
            borrowingEnabled: true,
            flashLoanEnabled: true
        });

        setupHelper.configureReserves(IPoolConfigurator(address(configurator)), configs);

        vm.stopBroadcast();
    }
}
