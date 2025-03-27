// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import "../dependencies/forge-std-1.9.6/src/Script.sol";
import "../dependencies/zerolend-1.0.0/contracts/mocks/tokens/MintableERC20.sol";
import "../dependencies/zerolend-1.0.0/contracts/protocol/configuration/PoolAddressesProviderRegistry.sol";
import "../dependencies/zerolend-1.0.0/contracts/protocol/configuration/PoolAddressesProvider.sol";
import "../dependencies/zerolend-1.0.0/contracts/protocol/pool/Pool.sol";
import "../dependencies/zerolend-1.0.0/contracts/protocol/pool/PoolConfigurator.sol";
import "../dependencies/zerolend-1.0.0/contracts/protocol/pool/DefaultReserveInterestRateStrategy.sol";
import "../dependencies/zerolend-1.0.0/contracts/protocol/pool/DefaultReserveInterestRateStrategy.sol";
import "../dependencies/zerolend-1.0.0/contracts/mocks/oracle/PriceOracle.sol";
import "../dependencies/zerolend-1.0.0/contracts/protocol/tokenization/AToken.sol";
import "../dependencies/zerolend-1.0.0/contracts/protocol/tokenization/StableDebtToken.sol";
import "../dependencies/zerolend-1.0.0/contracts/protocol/tokenization/VariableDebtToken.sol";
import "../dependencies/zerolend-1.0.0/contracts/interfaces/IPool.sol";
import "../dependencies/zerolend-1.0.0/contracts/interfaces/IPoolAddressesProvider.sol";
import "../dependencies/zerolend-1.0.0/contracts/interfaces/IPoolAddressesProviderRegistry.sol";
import "../dependencies/zerolend-1.0.0/contracts/interfaces/IPoolConfigurator.sol";
import "../dependencies/zerolend-1.0.0/contracts/interfaces/IPriceOracle.sol";
import "../dependencies/zerolend-1.0.0/contracts/interfaces/IAToken.sol";
import "../dependencies/zerolend-1.0.0/contracts/interfaces/IStableDebtToken.sol";
import "../dependencies/zerolend-1.0.0/contracts/interfaces/IVariableDebtToken.sol";
import "../dependencies/zerolend-1.0.0/contracts/flashloan/interfaces/IFlashLoanReceiver.sol";

contract DeployMockScript is Script {
    function setUp() public {}

    AToken public wethAToken;
    AToken public usdcAToken;
    IPoolAddressesProviderRegistry registry;

    function run() public {
        // 1. Deploy mock tokens
        MintableERC20 weth = new MintableERC20("Wrapped Ether", "WETH", 18);
        MintableERC20 usdc = new MintableERC20("USD Coin", "USDC", 6);

        // 2. Deploy registry
        registry = new PoolAddressesProviderRegistry(msg.sender);

        // 3. Deploy one unique market
        IPoolAddressesProvider market = new PoolAddressesProvider("Mocked ZeroLend Market", address(registry));

        // 4. Register market in registry
        registry.registerAddressesProvider(address(market), 1);

        // 5. Deploy and set price oracle
        PriceOracle oracle = new PriceOracle();
        oracle.setEthUsdPrice(2000e18); // 1 ETH = 2000 USDeq.
        oracle.setAssetPrice(address(weth), 2000e18); // 1 WETH = 2000 USDeq.
        oracle.setAssetPrice(address(usdc), 1e18); // 1 USDC = 1 USDeq.
        market.setPriceOracle(address(oracle));

        // 6. Deploy and set pool implementation and get pool proxy
        market.setPoolImpl(address(new Pool(market)));
        IPool pool = IPool(market.getPool());

        // 8. Deploy and set pool configurator
        IPoolConfigurator configurator = new PoolConfigurator();
        market.setPoolConfiguratorImpl(address(configurator));

        // 10. Deploy tokens for WETH & USD reserve
        wethAToken = new AToken(pool);
        usdcAToken = new AToken(pool);
        StableDebtToken wethStableDebtToken = new StableDebtToken(pool);
        VariableDebtToken wethVariableDebtToken = new VariableDebtToken(pool);
        StableDebtToken usdcStableDebtToken = new StableDebtToken(pool);
        VariableDebtToken usdcVariableDebtToken = new VariableDebtToken(pool);

        // 11. Deploy interest rate strategies
        IDefaultInterestRateStrategy wethStrategy = new DefaultReserveInterestRateStrategy(
            IPoolAddressesProvider(address(market)),
            0.8e27, // optimal utilization
            0.04e27, // base variable borrow rate
            0.08e27, // variable rate slope1
            0.75e27, // variable rate slope2
            0.03e27, // stable rate slope1
            0.60e27, // stable rate slope2
            0.02e27, // base stable rate offset
            0.01e27, // stable rate excess offset
            0.5e27   // optimal stable to total debt ratio
        );
        IDefaultInterestRateStrategy usdcStrategy = new DefaultReserveInterestRateStrategy(
            IPoolAddressesProvider(address(market)),
            0.9e27, // optimal utilization
            0.03e27, // base variable borrow rate
            0.06e27, // variable rate slope1
            0.80e27, // variable rate slope2
            0.02e27, // stable rate slope1
            0.65e27, // stable rate slope2
            0.01e27, // base stable rate offset
            0.008e27, // stable rate excess offset
            0.6e27   // optimal stable to total debt ratio
        );

        // 12. Initialize reserves
        pool.initReserve(
            address(weth),
            address(wethAToken),
            address(wethStableDebtToken),
            address(wethVariableDebtToken),
            address(wethStrategy)
        );

        pool.initReserve(
            address(usdc),
            address(usdcAToken),
            address(usdcStableDebtToken),
            address(usdcVariableDebtToken),
            address(usdcStrategy)
        );

        // 13. Configure reserves
        IPoolConfigurator configuratorProxy = IPoolConfigurator(market.getPoolConfigurator());
        configuratorProxy.configureReserveAsCollateral(
            address(weth),
            8000, // 80% LTV
            8250, // 82.5% liquidation threshold
            10500  // 105% liquidation bonus
        );
        configuratorProxy.configureReserveAsCollateral(
            address(usdc),
            8500, // 85% LTV
            8750, // 87.5% liquidation threshold
            10500  // 105% liquidation bonus
        );

        // 14. Enable borrowing and set reserve factor
        configuratorProxy.setReserveBorrowing(address(weth), true);
        configuratorProxy.setReserveFactor(address(weth), 1000); // 10%
        configuratorProxy.setReserveBorrowing(address(usdc), true);
        configuratorProxy.setReserveFactor(address(usdc), 1000); // 10%

        vm.stopBroadcast();
    }
}
