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
import "../dependencies/zerolend-1.0.0/contracts/protocol/libraries/types/ConfiguratorInputTypes.sol";
import "../dependencies/zerolend-1.0.0/contracts/protocol/configuration/ACLManager.sol";
import "../dependencies/zerolend-1.0.0/contracts/interfaces/IAaveIncentivesController.sol";

contract DeployMockScript is Script {
    function setUp() public {}

    AToken public aWeth;
    AToken public aUsdc;
    MintableERC20 public weth;
    MintableERC20 public usdc;
    IPoolAddressesProviderRegistry public registry;
    IPoolAddressesProvider public market;

    function run() public {
        // 1. Deploy mock tokens
        weth = new MintableERC20("Wrapped Ether", "WETH", 18);
        usdc = new MintableERC20("USD Coin", "USDC", 6);

        // 2. Deploy registry
        registry = new PoolAddressesProviderRegistry(address(this));

        // 3. Deploy one unique market
        market = new PoolAddressesProvider("Mocked ZeroLend Market", address(this));

        // 4. Set the ACLAdmin on the market
        market.setACLAdmin(address(this));

        // 5. Deploy ACL Manager and set roles
        ACLManager aclManager = new ACLManager(market);
        market.setACLManager(address(aclManager));
        aclManager.addPoolAdmin(address(this));
        aclManager.addAssetListingAdmin(address(this));
        aclManager.addRiskAdmin(address(this));
        aclManager.addEmergencyAdmin(address(this));

        // 6. Register market in registry
        registry.registerAddressesProvider(address(market), 1);

        // 7. Deploy and set price oracle
        PriceOracle oracle = new PriceOracle();
        oracle.setEthUsdPrice(2000e18); // 1 ETH = 2000 USDeq.
        oracle.setAssetPrice(address(weth), 2000e18); // 1 WETH = 2000 USDeq.
        oracle.setAssetPrice(address(usdc), 1e18); // 1 USDC = 1 USDeq.
        market.setPriceOracle(address(oracle));

        // 8. Deploy and set pool implementation and get pool proxy
        market.setPoolImpl(address(new Pool(market)));
        IPool pool = IPool(market.getPool());

        // 9. Deploy tokens for WETH & USD reserve
        aWeth = new AToken(pool);
        aUsdc = new AToken(pool);
        StableDebtToken wethStableDebtToken = new StableDebtToken(pool);
        VariableDebtToken wethVariableDebtToken = new VariableDebtToken(pool);
        StableDebtToken usdcStableDebtToken = new StableDebtToken(pool);
        VariableDebtToken usdcVariableDebtToken = new VariableDebtToken(pool);

        // Initialize aTokens
        aWeth.initialize(
            pool,
            address(this), // treasury
            address(weth), // underlying asset
            IAaveIncentivesController(address(0)), // incentives controller
            18, // decimals
            "ZeroLend WETH",
            "zWETH",
            bytes("")
        );

        aUsdc.initialize(
            pool,
            address(this), // treasury
            address(usdc), // underlying asset
            IAaveIncentivesController(address(0)), // incentives controller
            6, // decimals
            "ZeroLend USDC",
            "zUSDC",
            bytes("")
        );

        // 10. Deploy interest rate strategies
        IDefaultInterestRateStrategy wethStrategy = new DefaultReserveInterestRateStrategy(
            IPoolAddressesProvider(address(market)),
            0.8e27, // optimal utilization
            0.04e27, // base variable borrow rate
            0.08e27, // variable rate slope1
            0.75e27, // variable rate slope2
            0.03e27, // stable rate slope1
            0.6e27, // stable rate slope2
            0.02e27, // base stable rate offset
            0.01e27, // stable rate excess offset
            0.5e27 // optimal stable to total debt ratio
        );
        IDefaultInterestRateStrategy usdcStrategy = new DefaultReserveInterestRateStrategy(
            IPoolAddressesProvider(address(market)),
            0.9e27, // optimal utilization
            0.03e27, // base variable borrow rate
            0.06e27, // variable rate slope1
            0.8e27, // variable rate slope2
            0.02e27, // stable rate slope1
            0.65e27, // stable rate slope2
            0.01e27, // base stable rate offset
            0.008e27, // stable rate excess offset
            0.6e27 // optimal stable to total debt ratio
        );

        // 11. Initialize reserves
        ConfiguratorInputTypes.InitReserveInput[] memory initInputs = new ConfiguratorInputTypes.InitReserveInput[](2);

        initInputs[0] = ConfiguratorInputTypes.InitReserveInput({
            aTokenImpl: address(aWeth),
            stableDebtTokenImpl: address(wethStableDebtToken),
            variableDebtTokenImpl: address(wethVariableDebtToken),
            underlyingAssetDecimals: 18,
            interestRateStrategyAddress: address(wethStrategy),
            underlyingAsset: address(weth),
            treasury: address(this),
            incentivesController: address(0),
            aTokenName: "ZeroLend WETH",
            aTokenSymbol: "zWETH",
            variableDebtTokenName: "ZeroLend Variable Debt WETH",
            variableDebtTokenSymbol: "variableDebtWETH",
            stableDebtTokenName: "ZeroLend Stable Debt WETH",
            stableDebtTokenSymbol: "stableDebtWETH",
            params: bytes("")
        });

        initInputs[1] = ConfiguratorInputTypes.InitReserveInput({
            aTokenImpl: address(aUsdc),
            stableDebtTokenImpl: address(usdcStableDebtToken),
            variableDebtTokenImpl: address(usdcVariableDebtToken),
            underlyingAssetDecimals: 6,
            interestRateStrategyAddress: address(usdcStrategy),
            underlyingAsset: address(usdc),
            treasury: address(this),
            incentivesController: address(0),
            aTokenName: "ZeroLend USDC",
            aTokenSymbol: "zUSDC",
            variableDebtTokenName: "ZeroLend Variable Debt USDC",
            variableDebtTokenSymbol: "variableDebtUSDC",
            stableDebtTokenName: "ZeroLend Stable Debt USDC",
            stableDebtTokenSymbol: "stableDebtUSDC",
            params: bytes("")
        });

        IPoolConfigurator configurator = new PoolConfigurator();
        market.setPoolConfiguratorImpl(address(configurator));
        IPoolConfigurator configuratorProxy = IPoolConfigurator(market.getPoolConfigurator());

        configuratorProxy.initReserves(initInputs);

        // 12. Configure reserves
        configuratorProxy.configureReserveAsCollateral(
            address(weth),
            8000, // 80% LTV
            8250, // 82.5% liquidation threshold
            10500 // 105% liquidation bonus
        );
        configuratorProxy.configureReserveAsCollateral(
            address(usdc),
            8500, // 85% LTV
            8750, // 87.5% liquidation threshold
            10500 // 105% liquidation bonus
        );

        // 13. Enable borrowing and set reserve factor
        configuratorProxy.setReserveBorrowing(address(weth), true);
        configuratorProxy.setReserveFactor(address(weth), 1000); // 10%
        configuratorProxy.setReserveBorrowing(address(usdc), true);
        configuratorProxy.setReserveFactor(address(usdc), 1000); // 10%
    }
}
