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
// struct Addresses {
//     address poolAddressesProviderRegistry;
//     address poolAddressesProvider;
//     address pool;
//     address aToken;
//     address user;
// }

// struct ReserveInfo {
//     address underlyingAsset;
//     uint256 ltv;
//     uint256 liquidationThreshold;
//     uint256 liquidationBonus;
//     uint256 reserveFactor;
//     bool usageAsCollateralEnabled;
//     bool borrowingEnabled;
//     bool stableBorrowingEnabled;
//     bool active;
// }

// struct UserInfo {
//     uint256 totalCollateralBase;
//     uint256 totalDebtBase;
//     uint256 availableBorrowsBase;
//     uint256 currentLiquidationThreshold;
//     uint256 ltv;
//     uint256 healthFactor;
// }

// function getAddresses() internal returns (Addresses memory) {
//     return Addresses({
//         poolAddressesProviderRegistry: vm.envAddress("POOL_ADDRESSES_PROVIDER_REGISTRY"),
//         poolAddressesProvider: vm.envAddress("POOL_ADDRESSES_PROVIDER"),
//         pool: vm.envAddress("POOL"),
//         aToken: vm.envAddress("ATOKEN"),
//         user: vm.envAddress("USER")
//     });
// }

// function getReserveInfo(IPool pool, AToken aToken) internal view returns (ReserveInfo memory) {
//     address underlyingAsset = aToken.UNDERLYING_ASSET_ADDRESS();
//     DataTypes.ReserveData memory reserveData = pool.getReserveData(underlyingAsset);
//     DataTypes.ReserveConfigurationMap memory reserveConfig = reserveData.configuration;

//     return ReserveInfo({
//         underlyingAsset: underlyingAsset,
//         ltv: (reserveConfig.data & 0xFFFF),
//         liquidationThreshold: ((reserveConfig.data >> 16) & 0xFFFF),
//         liquidationBonus: ((reserveConfig.data >> 32) & 0xFFFF),
//         reserveFactor: ((reserveConfig.data >> 48) & 0xFFFF),
//         usageAsCollateralEnabled: ((reserveConfig.data >> 64) & 0x01) == 1,
//         borrowingEnabled: ((reserveConfig.data >> 65) & 0x01) == 1,
//         stableBorrowingEnabled: ((reserveConfig.data >> 66) & 0x01) == 1,
//         active: ((reserveConfig.data >> 67) & 0x01) == 1
//     });
// }

// function getUserInfo(IPool pool, address user) internal view returns (UserInfo memory) {
//     (uint256 totalCollateralBase, uint256 totalDebtBase, uint256 availableBorrowsBase,
//      uint256 currentLiquidationThreshold, uint256 ltv, uint256 healthFactor) =
//      pool.getUserAccountData(user);

//     return UserInfo({
//         totalCollateralBase: totalCollateralBase,
//         totalDebtBase: totalDebtBase,
//         availableBorrowsBase: availableBorrowsBase,
//         currentLiquidationThreshold: currentLiquidationThreshold,
//         ltv: ltv,
//         healthFactor: healthFactor
//     });
// }

// function logReserveInfo(ReserveInfo memory info) internal {
//     console.log("Reserve Information:");
//     console.log("    Underlying Asset:", info.underlyingAsset);
//     console.log("    Reserve LTV:", info.ltv);
//     console.log("    Liquidation Threshold:", info.liquidationThreshold);
//     console.log("    Liquidation Bonus:", info.liquidationBonus);
//     console.log("    Reserve Factor:", info.reserveFactor);
//     console.log("    Usage As Collateral Enabled:", info.usageAsCollateralEnabled);
//     console.log("    Borrowing Enabled:", info.borrowingEnabled);
//     console.log("    Stable Borrowing Enabled:", info.stableBorrowingEnabled);
//     console.log("    Active:", info.active);
// }

// function logUserInfo(UserInfo memory info) internal {
//     console.log("\nUser Information:");
//     console.log("    Total Collateral (Base):", info.totalCollateralBase);
//     console.log("    Total Debt (Base):", info.totalDebtBase);
//     console.log("    Available Borrows (Base):", info.availableBorrowsBase);
//     console.log("    Current Liquidation Threshold:", info.currentLiquidationThreshold);
//     console.log("    LTV:", info.ltv);
//     console.log("    Health Factor:", info.healthFactor);
// }

// function run() public {
//     uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
//     vm.startBroadcast(deployerPrivateKey);

//     // Get addresses
//     Addresses memory addresses = getAddresses();

//     // Get contract instances
//     IPoolAddressesProviderRegistry poolAddressesProviderRegistry = IPoolAddressesProviderRegistry(addresses.poolAddressesProviderRegistry);
//     IPoolAddressesProvider poolAddressesProvider = IPoolAddressesProvider(addresses.poolAddressesProvider);
//     IPool pool = IPool(addresses.pool);
//     AToken aToken = AToken(addresses.aToken);

//     // Deploy the LeveragePositionManager
//     LeveragePositionManager leverageManager = new LeveragePositionManager(
//         addresses.poolAddressesProviderRegistry,
//         addresses.poolAddressesProvider,
//         addresses.pool
//     );

//     // Get and log reserve information
//     ReserveInfo memory reserveInfo = getReserveInfo(pool, aToken);
//     logReserveInfo(reserveInfo);

//     // Get and log user information
//     UserInfo memory userInfo = getUserInfo(pool, addresses.user);
//     logUserInfo(userInfo);

//     // Take a leveraged position
//     uint256 lentTokenAmount = 1000 * 10**18; // 1000 tokens (assuming 18 decimals)
//     uint256 targetLtv = 8000; // 80%
//     bool interestRateMode = false; // Variable rate

//     console.log("\nTaking leveraged position:");
//     console.log("    Lent Token Amount:", lentTokenAmount);
//     console.log("    Target LTV:", targetLtv);
//     console.log("    Interest Rate Mode:", interestRateMode ? "Stable" : "Variable");

//     leverageManager.takePosition(aToken, lentTokenAmount, targetLtv, interestRateMode);

//     vm.stopBroadcast();
// }
}
