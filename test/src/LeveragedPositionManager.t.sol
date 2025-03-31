// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {DeployMockProtocolScript} from "../../script/DeployMockProtocolScript.sol";
import {MintableERC20} from "../../dependencies/zerolend-1.0.0/contracts/mocks/tokens/MintableERC20.sol";
import {IPool} from "../../dependencies/zerolend-1.0.0/contracts/interfaces/IPool.sol";
import {AToken} from "../../dependencies/zerolend-1.0.0/contracts/protocol/tokenization/AToken.sol";
import {LeveragedPositionManager} from "../../src/LeveragedPositionManager.sol";

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
        vm.assertEq(amountInTokenToBorrow, 5 * 12 * 10 ** weth.decimals(), "Amount in token to borrow is not correct");

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
        vm.assertEq(amountInTokenToBorrow, 56000000000000000000);

        amountInTokenToBorrow = leveragedPositionManager.getCollateralToGetFromFlashloanInToken(
            aUsdc, 78 * 10 ** usdc.decimals(), 0, address(0)
        );
        vm.assertEq(amountInTokenToBorrow, 78000000);

        // TODO: fix this test with the decorator `forge-config: default.allow_internal_expect_revert = true`; Probably related to https://github.com/foundry-rs/foundry/issues/3437 ?
        // vm.expectRevert(abi.encodeWithSelector(LeveragedPositionManager.TokenPriceZeroOrUnknown.selector, address(0)));
        // leveragedPositionManager.getCollateralToGetFromFlashloanInToken(AToken(address(0)), 91 * 10 ** usdc.decimals(), 0, address(0));
    }

    function test_AmountInTokenToBorrowWithExceedingCollateralAlreadyExisting() public {
        vm.skip(true, "TODO");
    }

    function test_AmountInTokenToBorrowWithCollateralAlreadyInProtocol() public {
        uint256 totalCollateralBase;
        uint256 totalDebtBase;

        uint256 targetLtv = 1000;
        vm.startPrank(bob);
        leveragedPositionManager.takePosition(aWeth, 1 * 10 ** weth.decimals(), targetLtv, 2);
        vm.stopPrank();

        (totalCollateralBase, totalDebtBase,,,,) = pool.getUserAccountData(bob);
        vm.assertApproxEqRel(totalDebtBase * 10000 / totalCollateralBase, targetLtv, 1e16, "A1");

        vm.startPrank(bob);
        uint256 amountInTokenToBorrow = leveragedPositionManager.getCollateralToGetFromFlashloanInToken(
            aWeth, 1 * 10 ** weth.decimals(), targetLtv * 2, bob
        );
        vm.assertEq(amountInTokenToBorrow, 1388888888888890000, "A2");
        leveragedPositionManager.takePosition(aWeth, 1 * 10 ** weth.decimals(), targetLtv * 2, 2);

        (totalCollateralBase, totalDebtBase,,,,) = pool.getUserAccountData(bob);
        vm.assertEq(
            leveragedPositionManager.convertBaseToToken(aWeth, totalCollateralBase),
            25 * 10 ** (weth.decimals() - 1),
            "A3"
        );
        vm.assertEq(
            leveragedPositionManager.convertBaseToToken(aWeth, totalDebtBase), 5 * 10 ** (weth.decimals() - 1), "A4"
        );
        vm.assertEq(totalDebtBase * 10000 / totalCollateralBase, targetLtv * 2, "A5");

        vm.stopPrank();
    }

    function test_AmountInTokenToBorrowWithCollateralAlreadyExisting() public {
        uint256 collateralInWethProvided = 10 * 10 ** weth.decimals();
        vm.startPrank(bob);
        pool.supply(address(weth), collateralInWethProvided, bob, 0);
        vm.stopPrank();

        uint256 amountInTokenToBorrow = leveragedPositionManager.getCollateralToGetFromFlashloanInToken(
            aWeth, 10 * 10 ** weth.decimals(), 8000, bob
        );

        vm.assertEq(amountInTokenToBorrow, 5 * 20 * 10 ** weth.decimals() - collateralInWethProvided, "A1");

        uint256 collateralInUsdcProvided = collateralInWethProvided * 2000 / 10 ** (18 - usdc.decimals());
        vm.startPrank(bob);
        pool.supply(address(usdc), collateralInUsdcProvided, bob, 0);
        vm.stopPrank();
        vm.assertEq(usdc.balanceOf(bob), 980000 * 10 ** usdc.decimals(), "A2");

        amountInTokenToBorrow = leveragedPositionManager.getCollateralToGetFromFlashloanInToken(
            aWeth, 10 * 10 ** weth.decimals(), 8000, bob
        );
        vm.assertEq(amountInTokenToBorrow, 5 * 30 * 10 ** weth.decimals() - 2 * collateralInWethProvided);
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
        vm.expectRevert(abi.encodeWithSelector(LeveragedPositionManager.LTVTooHigh.selector, targetLtv, 8000));
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
        vm.expectRevert(abi.encodeWithSelector(LeveragedPositionManager.LTVTooLow.selector, targetLtv, 7500));
        leveragedPositionManager.validateLtv(aWeth, targetLtv, bob);
    }

    function test_ValidateLtv_DifferentTokens() public {
        uint256 targetLtv = 7500;
        uint256 validatedLtv = leveragedPositionManager.validateLtv(aUsdc, targetLtv, bob);
        assertEq(validatedLtv, targetLtv);
    }

    function test_resetTransientState() public {
        vm.startPrank(bob);
        leveragedPositionManager.takePosition(aWeth, 1 * 10 ** weth.decimals(), 1000, 2);
        leveragedPositionManager.takePosition(aWeth, 1 * 10 ** weth.decimals(), 2000, 2);
        vm.stopPrank();
    }

    function test_takePositionFromZeroCollateralWithPoolsWithNoPremium() public {
        uint256 targetLtv = 8000;

        vm.startPrank(bob);
        leveragedPositionManager.takePosition(aWeth, 1 * 10 ** weth.decimals(), targetLtv, 2);
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
}
