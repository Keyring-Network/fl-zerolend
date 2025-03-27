// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import {Script, console} from "forge-std/Script.sol";
import {LeveragePositionManager} from "../src/LeveragePositionManager.sol";
import {IPoolAddressesProviderRegistry} from "@aave/core-v3/contracts/interfaces/IPoolAddressesProviderRegistry.sol";
import {IPoolAddressesProvider} from "@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol";
import {IPool} from "@aave/core-v3/contracts/interfaces/IPool.sol";
import {IERC20Detailed as IERC20} from "@aave/core-v3/contracts/dependencies/openzeppelin/contracts/IERC20Detailed.sol";
import {IAToken} from "@aave/core-v3/contracts/interfaces/IAToken.sol";
import {DataTypes} from "@aave/core-v3/contracts/protocol/libraries/types/DataTypes.sol";
import {IFlashLoanSimpleReceiver} from "@aave/core-v3/contracts/flashloan/interfaces/IFlashLoanSimpleReceiver.sol";
import {IPriceOracleGetter} from "@aave/core-v3/contracts/interfaces/IPriceOracleGetter.sol";

contract TakeLeveragedPositionScript is Script, IFlashLoanSimpleReceiver {
    LeveragePositionManager public leveragePositionManager;
    IPoolAddressesProviderRegistry public poolAddressesProviderRegistry;
    IPoolAddressesProvider public poolAddressesProvider;
    IPool public pool;
    IPriceOracleGetter public priceOracle;
    
    address public collateralToken;
    address public borrowToken;
    uint256 public initialCollateralAmount;
    uint256 public borrowAmount;
    uint256 public numberOfLoops;

    function setUp() public {
        // Load environment variables
        address poolAddressesProviderRegistryAddress = vm.envAddress("POOL_ADDRESSES_PROVIDER_REGISTRY");
        address poolAddressesProviderAddress = vm.envAddress("POOL_ADDRESSES_PROVIDER");
        
        // Initialize contracts
        poolAddressesProviderRegistry = IPoolAddressesProviderRegistry(poolAddressesProviderRegistryAddress);
        poolAddressesProvider = IPoolAddressesProvider(poolAddressesProviderAddress);
        pool = IPool(poolAddressesProvider.getPool());
        priceOracle = IPriceOracleGetter(poolAddressesProvider.getPriceOracle());
        leveragePositionManager = new LeveragePositionManager(poolAddressesProviderRegistryAddress);
    }

    function getTokenPrice(address token) public view returns (uint256) {
        return priceOracle.getAssetPrice(token);
    }

    function executeOperation(
        address asset,
        uint256 amount,
        uint256 premium,
        address initiator,
        bytes calldata params
    ) external override returns (bool) {
        // Decode parameters
        (address collateralToken, address borrowToken, uint256 initialCollateralAmount, uint256 numberOfLoops) = 
            abi.decode(params, (address, address, uint256, uint256));
        
        IERC20 assetToken = IERC20(asset);
        
        // Get token prices
        uint256 collateralPrice = getTokenPrice(collateralToken);
        uint256 borrowPrice = getTokenPrice(borrowToken);
        
        console.log("Collateral token price:", collateralPrice);
        console.log("Borrow token price:", borrowPrice);
        
        // Approve repayment
        uint256 amountToRepay = amount + premium;
        assetToken.approve(address(pool), amountToRepay);
        
        // Supply initial collateral
        IERC20(collateralToken).approve(address(pool), initialCollateralAmount);
        pool.supply(collateralToken, initialCollateralAmount, address(this), 0);
        pool.setUserUseReserveAsCollateral(collateralToken, true);
        
        // Leverage loop
        for (uint256 i = 0; i < numberOfLoops; i++) {
            // Borrow
            pool.borrow(borrowToken, amount, 2, 0, address(this));
            
            // Use borrowed amount as collateral
            IERC20(borrowToken).approve(address(pool), amount);
            pool.supply(borrowToken, amount, address(this), 0);
            pool.setUserUseReserveAsCollateral(borrowToken, true);
            
            console.log("Loop", i + 1, "completed");
        }
        
        return true;
    }

    function run() public {
        // Load environment variables
        collateralToken = vm.envAddress("COLLATERAL_TOKEN");
        borrowToken = vm.envAddress("BORROW_TOKEN");
        initialCollateralAmount = vm.envUint("INITIAL_COLLATERAL_AMOUNT");
        borrowAmount = vm.envUint("BORROW_AMOUNT");
        numberOfLoops = vm.envUint("NUMBER_OF_LOOPS");
        
        // Get initial prices
        uint256 collateralPrice = getTokenPrice(collateralToken);
        uint256 borrowPrice = getTokenPrice(borrowToken);
        
        console.log("Initial collateral token price:", collateralPrice);
        console.log("Initial borrow token price:", borrowPrice);
        
        // Start broadcasting transactions
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        
        // Prepare flash loan parameters
        bytes memory params = abi.encode(collateralToken, borrowToken, initialCollateralAmount, numberOfLoops);
        
        // Execute flash loan
        pool.flashLoanSimple(
            address(this),
            borrowToken,
            borrowAmount,
            params,
            0
        );
        
        // Log final position
        (
            uint256 totalCollateralBase,
            uint256 totalDebtBase,
            uint256 availableBorrowsBase,
            uint256 currentLiquidationThreshold,
            uint256 ltv,
            uint256 healthFactor
        ) = pool.getUserAccountData(address(this));
        
        console.log("Position taken successfully!");
        console.log("Initial collateral:", initialCollateralAmount);
        console.log("Number of loops:", numberOfLoops);
        console.log("Total collateral (in base units):", totalCollateralBase);
        console.log("Total debt (in base units):", totalDebtBase);
        console.log("Health factor:", healthFactor);
        
        vm.stopBroadcast();
    }
} 