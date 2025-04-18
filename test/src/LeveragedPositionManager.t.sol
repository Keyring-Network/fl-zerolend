// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {DeployMockProtocolScript} from "../../script/DeployMockProtocolScript.sol";
import {MintableERC20} from "../../dependencies/zerolend-1.0.0/contracts/mocks/tokens/MintableERC20.sol";
import {IPool} from "../../dependencies/zerolend-1.0.0/contracts/interfaces/IPool.sol";
import {AToken} from "../../dependencies/zerolend-1.0.0/contracts/protocol/tokenization/AToken.sol";
import {LeveragedPositionManager} from "../../src/LeveragedPositionManager.sol";
import {DebtTokenBase} from "../../dependencies/zerolend-1.0.0/contracts/protocol/tokenization/base/DebtTokenBase.sol";

contract LeveragedPositionManagerTest is Test {
    DeployMockProtocolScript public script;
    MintableERC20 public weth;
    MintableERC20 public usdc;
    IPool public pool;
    AToken public aWeth;
    AToken public aUsdc;
    LeveragedPositionManager public leveragedPositionManager;

    address public alice = makeAddr("Alice");
    address public bob = makeAddr("Bob");

    function setUp() public {
        script = new DeployMockProtocolScript();
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
        weth.approve(address(leveragedPositionManager), type(uint256).max);
        usdc.approve(address(leveragedPositionManager), type(uint256).max);
        address wethStableDebtTokenAddress = pool.getReserveData(address(weth)).stableDebtTokenAddress;
        address wethVariableDebtTokenAddress = pool.getReserveData(address(weth)).variableDebtTokenAddress;
        DebtTokenBase(wethStableDebtTokenAddress).approveDelegation(
            address(leveragedPositionManager), type(uint256).max
        );
        DebtTokenBase(wethVariableDebtTokenAddress).approveDelegation(
            address(leveragedPositionManager), type(uint256).max
        );
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

    function test_AmountInTokenToBorrowWithExceedingCollateralAlreadyExisting() public {
        vm.skip(true, "TODO");
    }

    function test_SendTokensToContractShouldNotFreezeContract() public {
        vm.skip(true, "TODO");
    }


    function test_ValidateLtv_ValidTargetLtv() public {
        uint256 targetLtv = 8000;
        uint256 validatedLtv = leveragedPositionManager.validateLtv(aWeth, targetLtv, bob);
        assertEq(validatedLtv, targetLtv);
    }

    function test_ValidateLtv_ZeroTargetLtv() public {
        uint256 targetLtv = 0;
        uint256 validatedLtv = leveragedPositionManager.validateLtv(aWeth, targetLtv, bob);
        assertEq(validatedLtv, 8000);
    }

    function test_ValidateLtv_ExceedsMaxLtv() public {
        uint256 targetLtv = 8500;
        vm.expectRevert(abi.encodeWithSelector(LeveragedPositionManager.LtvTooHigh.selector, targetLtv, 8000));
        leveragedPositionManager.validateLtv(aWeth, targetLtv, bob);
    }

    function test_ValidateLtv_CurrentLtvTooHigh() public {
        vm.startPrank(bob);
        uint256 depositAmount = 10 * 10 ** weth.decimals();
        pool.supply(address(weth), depositAmount, bob, 0);
        pool.setUserUseReserveAsCollateral(address(weth), true);
        pool.borrow(address(usdc), 15000 * 10 ** usdc.decimals(), 2, 0, bob);
        vm.stopPrank();

        uint256 targetLtv = 7000;
        vm.expectRevert(abi.encodeWithSelector(LeveragedPositionManager.LtvTooLow.selector, targetLtv, 7500));
        leveragedPositionManager.validateLtv(aWeth, targetLtv, bob);
    }

    function test_ValidateLtv_DifferentTokens() public {
        uint256 targetLtv = 7500;
        uint256 validatedLtv = leveragedPositionManager.validateLtv(aUsdc, targetLtv, bob);
        assertEq(validatedLtv, targetLtv);
    }

    function test_resetTransientState() public {
        vm.startPrank(bob);
        leveragedPositionManager.takePosition(aWeth, int256(1 * 10 ** weth.decimals()), 1000, 2);
        leveragedPositionManager.takePosition(aWeth, int256(1 * 10 ** weth.decimals()), 2000, 2);
        vm.stopPrank();
    }

    function test_takePositionFromZeroCollateralWithPoolsWithNoPremium() public {
        uint256 targetLtv = 8000;

        vm.startPrank(bob);
        leveragedPositionManager.takePosition(aWeth, int256(1 * 10 ** weth.decimals()), targetLtv, 2);
        vm.stopPrank();

        (uint256 totalCollateralBase, uint256 totalDebtBase,,,,) = pool.getUserAccountData(bob);
        vm.assertEq(
            leveragedPositionManager.convertBaseToToken(aWeth, totalCollateralBase), 5 * 10 ** weth.decimals(), "A1"
        );
        vm.assertEq(leveragedPositionManager.convertBaseToToken(aWeth, totalDebtBase), 4 * 10 ** weth.decimals(), "A2");
        vm.assertEq(totalDebtBase * 10000 / totalCollateralBase, targetLtv, "A3");
    }

    function test_noNeedToGetCollateralFromFlashloan() public {
        vm.skip(true, "TODO");
    }

    function test_takePositionFromZeroCollateralWithPoolsWithPremium() public {
        vm.skip(true, "TODO");
    }

    function test_takePositionWithExistingMonoCollateral() public {
        vm.skip(true, "TODO");
    }

    function test_takePositionWithExistingMultiCollateral() public {
        vm.skip(true, "TODO");
    }

    function test_reentrancy() public {
        vm.skip(true, "TODO");
    }

    function test_dustManagement() public {
        vm.skip(true, "TODO");
    }

    function test_digitsPrecision() public {
        vm.skip(true, "TODO");
    }

    function test_oracleStaleness() public {
        vm.skip(true, "TODO");
    }

    function test_executeOperationValidations() public {
        vm.skip(true, "TODO");
    }

    function test_convertBaseToToken() public {
        uint256 wethBaseAmount = 1000e18; // 1000 base units of weth
        uint256 usdcBaseAmount = 1000e18; // 1000 base units of usdc
        uint256 wethTokenAmount = leveragedPositionManager.convertBaseToToken(aWeth, wethBaseAmount);
        assertEq(wethTokenAmount, 1 * 10 ** weth.decimals() / 2);
        uint256 usdcTokenAmount = leveragedPositionManager.convertBaseToToken(aUsdc, usdcBaseAmount);
        assertEq(usdcTokenAmount, 1000 * 10 ** usdc.decimals());
        uint256 wethTokenAmountNormalized = wethTokenAmount * 10 ** (36 - weth.decimals());
        uint256 usdcTokenAmountNormalized = usdcTokenAmount * 10 ** (36 - usdc.decimals());
        assertEq(usdcTokenAmountNormalized / wethTokenAmountNormalized, 2000);
    }

    function test_transientStorageRemainsUnset(uint256 amount, uint256 targetLtv) public {
        // Bound the amount to reasonable values to avoid overflow
        amount = bound(amount, 0.1 ether, 100 ether);
        // Bound the targetLtv to valid range (0-8000)
        targetLtv = bound(targetLtv, 0, 8000);

        // Ensure Bob has enough WETH balance
        uint256 bobWethBalance = weth.balanceOf(bob);
        if (bobWethBalance < amount) {
            weth.mint(bob, amount - bobWethBalance);
        }

        // Verify transient storage is unset before transaction
        assertEq(address(leveragedPositionManager.transientPool()), address(0), "Transient pool should be unset before");
        assertEq(
            address(leveragedPositionManager.transientAddressesProvider()),
            address(0),
            "Transient addresses provider should be unset before"
        );
        assertEq(leveragedPositionManager.transientUser(), address(0), "Transient user should be unset before");

        // Execute a transaction
        vm.startPrank(bob);
        leveragedPositionManager.takePosition(aWeth, int256(amount), targetLtv, 2);
        vm.stopPrank();

        // Verify transient storage is unset after transaction
        assertEq(address(leveragedPositionManager.transientPool()), address(0), "Transient pool should be unset after");
        assertEq(
            address(leveragedPositionManager.transientAddressesProvider()),
            address(0),
            "Transient addresses provider should be unset after"
        );
        assertEq(leveragedPositionManager.transientUser(), address(0), "Transient user should be unset after");
    }

    // create a test to test the function getAmountToBorrowInFlashLoan when a user already a position and wants to deleverage it
    function test_getAmountToBorrowInFlashLoan_WithExistingPosition() public {
        // Setup initial leveraged position
        uint256 initialAmount = 10 * 10 ** weth.decimals();
        uint256 initialTargetLtv = 8000;
        
        vm.startPrank(bob);
        leveragedPositionManager.takePosition(aWeth, int256(initialAmount), initialTargetLtv, 2);
        vm.stopPrank();
        
        uint256 newTargetLtv = 8000;
        
        int256 amountToBorrow = leveragedPositionManager.getAmountToBorrowInFlashLoan(
            aWeth,
            0, 
            newTargetLtv,
            bob
        );

        console.log("amountToBorrow", amountToBorrow);
    }
    
}
