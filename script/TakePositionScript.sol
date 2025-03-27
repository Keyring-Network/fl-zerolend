// SPDX-License-Identifier: MIT
pragma solidity 0.8.12;

import "../dependencies/forge-std/src/Script.sol";
import "../dependencies/zerolend-1.0.0/contracts/interfaces/IPoolAddressesProviderRegistry.sol";
import "../dependencies/zerolend-1.0.0/contracts/interfaces/IPoolAddressesProvider.sol";
import "../dependencies/zerolend-1.0.0/contracts/interfaces/IPool.sol";
import "../dependencies/zerolend-1.0.0/contracts/protocol/tokenization/AToken.sol";
import "../dependencies/zerolend-1.0.0/contracts/protocol/libraries/configuration/ReserveConfiguration.sol";
import "../dependencies/zerolend-1.0.0/contracts/protocol/libraries/types/DataTypes.sol";
import "../src/LeveragePositionManager.sol";

contract TakePositionScript is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Get addresses from environment variables
        address poolAddressesProviderRegistryAddress = vm.envAddress("POOL_ADDRESSES_PROVIDER_REGISTRY");
        address poolAddressesProviderAddress = vm.envAddress("POOL_ADDRESSES_PROVIDER");
        address poolAddress = vm.envAddress("POOL");
        address aTokenAddress = vm.envAddress("ATOKEN");
        address userAddress = vm.envAddress("USER");

        // Get the pool and addresses provider instances
        IPoolAddressesProviderRegistry poolAddressesProviderRegistry = IPoolAddressesProviderRegistry(poolAddressesProviderRegistryAddress);
        IPoolAddressesProvider poolAddressesProvider = IPoolAddressesProvider(poolAddressesProviderAddress);
        IPool pool = IPool(poolAddress);
        AToken aToken = AToken(aTokenAddress);

        // Deploy the LeveragePositionManager
        LeveragePositionManager leverageManager = new LeveragePositionManager(
            poolAddressesProviderRegistryAddress,
            poolAddressesProviderAddress,
            poolAddress
        );

        // Get reserve data
        address underlyingAsset = aToken.UNDERLYING_ASSET_ADDRESS();
        DataTypes.ReserveData memory reserveData = pool.getReserveData(underlyingAsset);
        DataTypes.ReserveConfigurationMap memory reserveConfig = reserveData.configuration;

        // Log reserve information
        console.log("Reserve Information:");
        console.log("    Underlying Asset:", underlyingAsset);
        console.log("    Reserve LTV:", (reserveConfig.data & 0xFFFF));
        console.log("    Liquidation Threshold:", ((reserveConfig.data >> 16) & 0xFFFF));
        console.log("    Liquidation Bonus:", ((reserveConfig.data >> 32) & 0xFFFF));
        console.log("    Reserve Factor:", ((reserveConfig.data >> 48) & 0xFFFF));
        console.log("    Usage As Collateral Enabled:", ((reserveConfig.data >> 64) & 0x01) == 1);
        console.log("    Borrowing Enabled:", ((reserveConfig.data >> 65) & 0x01) == 1);
        console.log("    Stable Borrowing Enabled:", ((reserveConfig.data >> 66) & 0x01) == 1);
        console.log("    Active:", ((reserveConfig.data >> 67) & 0x01) == 1);

        // Get user account data
        (uint256 totalCollateralBase, uint256 totalDebtBase, uint256 availableBorrowsBase, uint256 currentLiquidationThreshold, uint256 ltv, uint256 healthFactor) = pool.getUserAccountData(userAddress);

        // Log user information
        console.log("\nUser Information:");
        console.log("    Total Collateral (Base):", totalCollateralBase);
        console.log("    Total Debt (Base):", totalDebtBase);
        console.log("    Available Borrows (Base):", availableBorrowsBase);
        console.log("    Current Liquidation Threshold:", currentLiquidationThreshold);
        console.log("    LTV:", ltv);
        console.log("    Health Factor:", healthFactor);

        // Take a leveraged position
        // Parameters:
        // - aToken: The aToken to use for the position
        // - lentTokenAmount: Amount of tokens to lend (in wei)
        // - targetLtv: Target LTV (in basis points, e.g., 8000 for 80%)
        // - interestRateMode: true for stable rate, false for variable rate
        uint256 lentTokenAmount = 1000 * 10**18; // 1000 tokens (assuming 18 decimals)
        uint256 targetLtv = 8000; // 80%
        bool interestRateMode = false; // Variable rate

        console.log("\nTaking leveraged position:");
        console.log("    Lent Token Amount:", lentTokenAmount);
        console.log("    Target LTV:", targetLtv);
        console.log("    Interest Rate Mode:", interestRateMode ? "Stable" : "Variable");

        leverageManager.takePosition(aToken, lentTokenAmount, targetLtv, interestRateMode);

        vm.stopBroadcast();
    }
}
