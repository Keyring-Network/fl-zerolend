// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import "forge-std/Test.sol";
import "../script/DeployMockScript.sol";
import "../dependencies/zerolend-1.0.0/contracts/mocks/tokens/MintableERC20.sol";
import "../dependencies/zerolend-1.0.0/contracts/interfaces/IPool.sol";
import "../dependencies/zerolend-1.0.0/contracts/interfaces/IAToken.sol";
import "../dependencies/zerolend-1.0.0/contracts/interfaces/IPoolAddressesProvider.sol";

contract DeployMockTest is Test {
    DeployMockScript public script;
    MintableERC20 public weth;
    MintableERC20 public usdc;
    IPool public pool;
    IAToken public aWeth;
    IAToken public aUsdc;
    IPoolAddressesProvider public market;

    address public alice = address(0x1);
    address public bob = address(0x2);

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

        // Log initial setup
        console.log("WETH address:", address(weth));
        console.log("USDC address:", address(usdc));
        console.log("Pool address:", address(pool));
        console.log("aWETH address:", address(aWeth));
        console.log("aUSDC address:", address(aUsdc));
    }

    function testDepositsAndBorrows() public {
        // Mint tokens to users
        weth.mint(alice, 12 ether);
        weth.mint(bob, 34 ether);
        usdc.mint(alice, 560000 * 10 ** 6); // 6 decimals for USDC

        // Log initial balances
        console.log("Initial balances:");
        console.log("Alice WETH:", weth.balanceOf(alice));
        console.log("Bob WETH:", weth.balanceOf(bob));
        console.log("Alice USDC:", usdc.balanceOf(alice));

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

        // Log intermediate balances
        console.log("After deposits:");
        console.log("Alice aWETH:", aWeth.balanceOf(alice));
        console.log("Bob aWETH:", aWeth.balanceOf(bob));
        console.log("Alice aUSDC:", aUsdc.balanceOf(alice));

        // Get Bob's account data before borrowing
        (
            uint256 totalCollateralBase,
            uint256 totalDebtBase,
            uint256 availableBorrowsBase,
            uint256 currentLiquidationThreshold,
            uint256 ltv,
            uint256 healthFactor
        ) = pool.getUserAccountData(bob);

        console.log("Bob's account data before borrowing:");
        console.log("Total collateral (base units):", totalCollateralBase);
        console.log("Total debt (base units):", totalDebtBase);
        console.log("Available borrows (base units):", availableBorrowsBase);
        console.log("Current liquidation threshold:", currentLiquidationThreshold);
        console.log("LTV:", ltv);
        console.log("Health factor:", healthFactor);

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

        // Log final balances
        console.log("Final balances:");
        console.log("Alice aWETH:", aWeth.balanceOf(alice));
        console.log("Bob aWETH:", aWeth.balanceOf(bob));
        console.log("Alice aUSDC:", aUsdc.balanceOf(alice));
        console.log("Bob USDC borrowed:", usdc.balanceOf(bob));

        // Log Bob's final account data
        (totalCollateralBase, totalDebtBase, availableBorrowsBase, currentLiquidationThreshold, ltv, healthFactor) =
            pool.getUserAccountData(bob);

        console.log("Bob's final account data:");
        console.log("Total collateral (base units):", totalCollateralBase);
        console.log("Total debt (base units):", totalDebtBase);
        console.log("Available borrows (base units):", availableBorrowsBase);
        console.log("Current liquidation threshold:", currentLiquidationThreshold);
        console.log("LTV:", ltv);
        console.log("Health factor:", healthFactor);
    }
}
