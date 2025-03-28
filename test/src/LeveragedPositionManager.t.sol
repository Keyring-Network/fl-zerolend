// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {DeployMockScript} from "../../script/DeployMockScript.sol";
import {MintableERC20} from "../../dependencies/zerolend-1.0.0/contracts/mocks/tokens/MintableERC20.sol";
import {IPool} from "../../dependencies/zerolend-1.0.0/contracts/interfaces/IPool.sol";
import {AToken} from "../../dependencies/zerolend-1.0.0/contracts/protocol/tokenization/AToken.sol";
import {LeveragedPositionManager} from "../../src/LeveragedPositionManager.sol";

contract LeveragedPositionManagerTest is Test {
    DeployMockScript public script;
    MintableERC20 public weth;
    MintableERC20 public usdc;
    IPool public pool;
    AToken public aWeth;
    AToken public aUsdc;
    LeveragedPositionManager public leveragedPositionManager;

    address public alice = makeAddr("Alice");
    address public bob = makeAddr("Bob");

    function setUp() public {
        script = new DeployMockScript();
        script.run();

        // Get the deployed contracts
        weth = script.weth();
        usdc = script.usdc();
        pool = IPool(script.market().getPool());
        aWeth = script.aWeth();
        aUsdc = script.aUsdc();

        // Deploy the leveraged position manager
        leveragedPositionManager = new LeveragedPositionManager(address(script.registry()));

        // Make them rich
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        weth.mint(alice, 3000 * 10 ** weth.decimals());
        weth.mint(bob, 10 * 10 ** weth.decimals());
        usdc.mint(alice, 5600000000 * 10 ** usdc.decimals());
        usdc.mint(bob, 1000000 * 10 ** usdc.decimals());
        // Alice fills in the pool
        vm.startPrank(alice);
        weth.approve(address(pool), type(uint256).max);
        usdc.approve(address(pool), type(uint256).max);
        pool.supply(address(usdc), usdc.balanceOf(alice), alice, 0);
        pool.supply(address(weth), weth.balanceOf(alice), alice, 0);
        vm.stopPrank();

        // Bob gets ready to lend weth and borrow usdc
        vm.startPrank(bob);
        weth.approve(address(pool), type(uint256).max);
        usdc.approve(address(pool), type(uint256).max);
        //pool.setUserUseReserveAsCollateral(address(weth), true);
        vm.stopPrank();
    }

    function test_ATokensAreSupported() public {
        leveragedPositionManager.revertIfATokenNotSupported(aWeth);
        leveragedPositionManager.revertIfATokenNotSupported(aUsdc);
        vm.assertTrue(true);
    }

    function test_NotATokenIsNotSupported() public {
        vm.expectRevert();
        leveragedPositionManager.revertIfATokenNotSupported(AToken(address(0)));
    }

    function test_AmountInTokenToBorrowWithNoCollateralAlreadyExisting() public {
        uint256 amountInTokenToBorrow;

        amountInTokenToBorrow = leveragedPositionManager.getCollateralToGetFromFlashloanInToken(
            aWeth, 12 * 10 ** weth.decimals(), 8000, address(0)
        );
        vm.assertEq(amountInTokenToBorrow, 5 * 12 * 10 ** weth.decimals());

        amountInTokenToBorrow = leveragedPositionManager.getCollateralToGetFromFlashloanInToken(
            aUsdc, 34 * 10 ** usdc.decimals(), 8000, address(0)
        );
        vm.assertEq(amountInTokenToBorrow, 5 * 34 * 10 ** usdc.decimals());

        amountInTokenToBorrow = leveragedPositionManager.getCollateralToGetFromFlashloanInToken(
            aWeth, 12 * 10 ** weth.decimals(), 8000, bob
        );
        vm.assertEq(amountInTokenToBorrow, 5 * 12 * 10 ** weth.decimals());

        amountInTokenToBorrow = leveragedPositionManager.getCollateralToGetFromFlashloanInToken(
            aUsdc, 34 * 10 ** usdc.decimals(), 8000, bob
        );
        vm.assertEq(amountInTokenToBorrow, 5 * 34 * 10 ** usdc.decimals());

        amountInTokenToBorrow = leveragedPositionManager.getCollateralToGetFromFlashloanInToken(
            aWeth, 56 * 10 ** weth.decimals(), 0, address(0)
        );
        vm.assertEq(amountInTokenToBorrow, 0);

        amountInTokenToBorrow = leveragedPositionManager.getCollateralToGetFromFlashloanInToken(
            aUsdc, 78 * 10 ** usdc.decimals(), 0, address(0)
        );
        vm.assertEq(amountInTokenToBorrow, 0);

        // TODO: fix this test with the decorator `forge-config: default.allow_internal_expect_revert = true`; Probably related to https://github.com/foundry-rs/foundry/issues/3437 ?
        // vm.expectRevert(abi.encodeWithSelector(LeveragedPositionManager.TokenPriceZeroOrUnknown.selector, address(0)));
        // leveragedPositionManager.getCollateralToGetFromFlashloanInToken(AToken(address(0)), 91 * 10 ** usdc.decimals(), 0, address(0));
    }

    function test_AmountInTokenToBorrowWithExceedingCollateralAlreadyExisting() public {
        
        uint256 amountInTokenToBorrow = leveragedPositionManager.getCollateralToGetFromFlashloanInToken(
            aWeth, 12 * 10 ** weth.decimals(), 8000, alice
        );
        vm.assertEq(amountInTokenToBorrow, 0);
    }

    function test_AmountInTokenToBorrowWithCollateralAlreadyExisting() public {
        uint256 collateralInWethProvided = 10 * 10 ** weth.decimals();
        vm.startPrank(bob);
        pool.supply(address(weth), collateralInWethProvided, bob, 0);
        vm.stopPrank();

        uint256 amountInTokenToBorrow = leveragedPositionManager.getCollateralToGetFromFlashloanInToken(
            aWeth, 12 * 10 ** weth.decimals(), 8000, bob
        );
        vm.assertEq(amountInTokenToBorrow, 5 * 12 * 10 ** weth.decimals() - collateralInWethProvided);

        vm.startPrank(bob);
        uint256 collateralInUsdcProvided = collateralInWethProvided * 2000 / 10 ** (18 - usdc.decimals());
        pool.supply(address(usdc), collateralInUsdcProvided, bob, 0);
        vm.assertEq(usdc.balanceOf(bob), 980000 * 10 ** usdc.decimals());
        vm.stopPrank();

        amountInTokenToBorrow = leveragedPositionManager.getCollateralToGetFromFlashloanInToken(
            aWeth, 12 * 10 ** weth.decimals(), 8000, bob
        );
        vm.assertEq(amountInTokenToBorrow, 5 * 12 * 10 ** weth.decimals() - 2 * collateralInWethProvided);
    }

    function test_ValidateLtv_ValidTargetLtv() public {
        // Test with a valid target LTV (8000 = 80%)
        uint256 targetLtv = 8000;
        uint256 validatedLtv = leveragedPositionManager.validateLtv(aWeth, targetLtv, bob);
        assertEq(validatedLtv, targetLtv);
    }

    function test_ValidateLtv_ZeroTargetLtv() public {
        // Test with zero target LTV (should use max LTV)
        uint256 targetLtv = 0;
        uint256 validatedLtv = leveragedPositionManager.validateLtv(aWeth, targetLtv, bob);
        assertEq(validatedLtv, 8000); // Max LTV is 80% in the mock setup
    }

    function test_ValidateLtv_ExceedsMaxLtv() public {
        // Test with LTV exceeding max (8000 = 80%)
        uint256 targetLtv = 8500; // 85%
        vm.expectRevert(abi.encodeWithSelector(LeveragedPositionManager.LTVTooHigh.selector, targetLtv, 8000));
        leveragedPositionManager.validateLtv(aWeth, targetLtv, bob);
    }

    function test_ValidateLtv_CurrentLtvTooHigh() public {
        // Setup: Bob deposits WETH and borrows USDC to create a position with ~75% LTV
        vm.startPrank(bob);
        uint256 depositAmount = 10 * 10 ** weth.decimals(); // 10 WETH = 20,000 USDC
        pool.supply(address(weth), depositAmount, bob, 0);
        pool.setUserUseReserveAsCollateral(address(weth), true);
        // Borrow 15,000 USDC to create a 75% LTV position (15000/20000)
        pool.borrow(address(usdc), 15000 * 10 ** usdc.decimals(), 2, 0, bob);
        vm.stopPrank();

        // Try to validate LTV that's lower than current position
        uint256 targetLtv = 7000; // 70%
        vm.expectRevert(abi.encodeWithSelector(LeveragedPositionManager.LTVTooLow.selector, targetLtv, 7500));
        leveragedPositionManager.validateLtv(aWeth, targetLtv, bob);
    }

    function test_ValidateLtv_DifferentTokens() public {
        // Test with USDC token
        uint256 targetLtv = 7500; // 75%
        uint256 validatedLtv = leveragedPositionManager.validateLtv(aUsdc, targetLtv, bob);
        assertEq(validatedLtv, targetLtv);
    }

    function test_takePositionFromZeroCollateral() public {
        
        // Get account data before taking position
        (uint256 totalCollateralBaseBefore, uint256 totalDebtBaseBefore,,,,) = pool.getUserAccountData(bob);
        
        // Take the position with 80% LTV and variable rate, using 10 WETH
        vm.startPrank(bob);
        leveragedPositionManager.takePosition(aWeth, 1 * 10 ** weth.decimals(), 8000, 2);
        vm.stopPrank();
        
        // Get account data after taking position
        (uint256 totalCollateralBaseAfter, uint256 totalDebtBaseAfter,,,,) = pool.getUserAccountData(bob);
        
        // Assert that collateral and debt increased
        assertGt(totalCollateralBaseAfter, totalCollateralBaseBefore, "Collateral should increase");
        assertGt(totalDebtBaseAfter, totalDebtBaseBefore, "Debt should increase");
        
        vm.stopPrank();
    }
}
