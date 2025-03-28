// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import "forge-std/Test.sol";
import "../../script/DeployMockScript.sol";
import "../../dependencies/zerolend-1.0.0/contracts/mocks/tokens/MintableERC20.sol";
import "../../dependencies/zerolend-1.0.0/contracts/interfaces/IPool.sol";
import "../../dependencies/zerolend-1.0.0/contracts/interfaces/IAToken.sol";
import "../../dependencies/zerolend-1.0.0/contracts/interfaces/IPoolAddressesProvider.sol";
import "../../dependencies/zerolend-1.0.0/contracts/interfaces/IPriceOracle.sol";

contract DeployMockTest is Test {
    DeployMockScript public script;
    MintableERC20 public weth;
    MintableERC20 public usdc;
    IPool public pool;
    IAToken public aWeth;
    IAToken public aUsdc;
    IPoolAddressesProvider public market;

    address public alice = makeAddr("Alice");
    address public bob = makeAddr("Bob");

    function setUp() public {
        // Deploy the stack using the script
        script = new DeployMockScript();
        script.run();

        // Get the deployed contracts
        weth = script.weth();
        usdc = script.usdc();
        market = script.market();
        pool = IPool(market.getPool());
        aWeth = IAToken(script.aWeth());
        aUsdc = IAToken(script.aUsdc());

        // Setup users
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);

    }

    function test_DepositsAndBorrows() public {

        assertEq(aWeth.UNDERLYING_ASSET_ADDRESS(), address(weth));
        assertEq(aUsdc.UNDERLYING_ASSET_ADDRESS(), address(usdc));


        // Mint tokens to users
        weth.mint(alice, 12 ether);
        weth.mint(bob, 34 ether);
        usdc.mint(alice, 560000 * 10 ** 6); // 6 decimals for USDC

        // Alice deposits WETH
        vm.startPrank(alice);
        weth.approve(address(pool), type(uint256).max);
        pool.supply(address(weth), 12 ether, alice, 0);
        pool.setUserUseReserveAsCollateral(address(weth), true);
        vm.stopPrank();

        // Alice deposits USDC
        vm.startPrank(alice);
        usdc.approve(address(pool), type(uint256).max);
        pool.supply(address(usdc), 560000 * 10 ** 6, alice, 0);
        pool.setUserUseReserveAsCollateral(address(usdc), true);
        vm.stopPrank();

        // Bob deposits WETH
        vm.startPrank(bob);
        weth.approve(address(pool), type(uint256).max);
        pool.supply(address(weth), 34 ether, bob, 0);
        pool.setUserUseReserveAsCollateral(address(weth), true);
        vm.stopPrank();

        (
            uint256 totalCollateralBase,
            uint256 totalDebtBase,
            uint256 availableBorrowsBase,
            uint256 currentLiquidationThreshold,
            uint256 ltv,
            uint256 healthFactor
        ) = pool.getUserAccountData(bob);

        // Calculate safe borrow amount (80% of available borrows to maintain healthy position)
        uint256 borrowAmount = (availableBorrowsBase * 80) / 100 / 10 ** 12; // Convert to USDC decimals and take 80%
        console.log("Bob attempting to borrow:", borrowAmount, "USDC");

        vm.startPrank(bob);
        pool.borrow(
            address(usdc),
            borrowAmount,
            2, // Variable rate
            0, // No referral code
            bob
        );
        vm.stopPrank();


        // Log Alice's final account data
        (totalCollateralBase, totalDebtBase, availableBorrowsBase, currentLiquidationThreshold, ltv, healthFactor) =
            pool.getUserAccountData(alice);
        vm.assertEq(totalCollateralBase, 584000000000000000000000); // 12 WETH + 560,000 USDC in base units
        vm.assertEq(totalDebtBase, 0);
        vm.assertEq(availableBorrowsBase, 495173600000000000000000); // Available borrows based on collateral
        vm.assertEq(currentLiquidationThreshold, 8729); // 87.29% threshold
        vm.assertEq(ltv, 8479); // 84.79% LTV
        vm.assertEq(healthFactor, type(uint256).max); // No debt, so max health factor

        // Log Bob's final account data
        (totalCollateralBase, totalDebtBase, availableBorrowsBase, currentLiquidationThreshold, ltv, healthFactor) =
            pool.getUserAccountData(bob);

        vm.assertEq(totalCollateralBase, 68000000000000000000000); // 34 WETH in base units
        vm.assertEq(totalDebtBase, 43520000000000000000000); // Borrowed USDC amount in base units
        vm.assertEq(availableBorrowsBase, 10880000000000000000000); // Remaining available borrows
        vm.assertEq(currentLiquidationThreshold, 8250); // 82.50% threshold
        vm.assertEq(ltv, 8000); // 80% LTV
        vm.assertEq(healthFactor, 1289062500000000000); // Health factor based on collateral and debt
    }

    function test_PriceOracleSetup() public {
        // Get the price oracle from the market
        address priceOracleAddress = market.getPriceOracle();
        IPriceOracle oracle = IPriceOracle(priceOracleAddress);

        // Verify WETH price
        uint256 wethPrice = oracle.getAssetPrice(aWeth.UNDERLYING_ASSET_ADDRESS());
        console.log("wethAddress", aWeth.UNDERLYING_ASSET_ADDRESS());
        vm.assertEq(wethPrice, 2000e18, "WETH price should be 2000 USDeq");

        // Verify USDC price
        uint256 usdcPrice = oracle.getAssetPrice(aUsdc.UNDERLYING_ASSET_ADDRESS());
        console.log("usdcAddress", aUsdc.UNDERLYING_ASSET_ADDRESS());
        vm.assertEq(usdcPrice, 1e18, "USDC price should be 1 USDeq");

        // Setup Alice's collateral
        weth.mint(alice, 12 ether);
        vm.startPrank(alice);
        weth.approve(address(pool), type(uint256).max);
        pool.supply(address(weth), 12 ether, alice, 0);
        pool.setUserUseReserveAsCollateral(address(weth), true);
        vm.stopPrank();

        // Test price oracle integration with pool
        (uint256 totalCollateralBase,,,,, ) = pool.getUserAccountData(alice);
        
        // Verify that the price oracle is being used correctly in calculations
        // When Alice deposits 12 WETH, the total collateral in base currency should be:
        // 12 WETH * 2000 USDeq = 24000 USDeq
        vm.assertEq(totalCollateralBase, 24000e18, "Total collateral should be 24000 USDeq");

    }
}
