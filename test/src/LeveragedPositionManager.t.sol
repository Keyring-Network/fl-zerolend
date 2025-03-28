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
        vm.assertEq(amountInTokenToBorrow, 4 * 12 * 10 ** weth.decimals());

        amountInTokenToBorrow = leveragedPositionManager.getCollateralToGetFromFlashloanInToken(
            aUsdc, 34 * 10 ** usdc.decimals(), 8000, address(0)
        );
        vm.assertEq(amountInTokenToBorrow, 4 * 34 * 10 ** usdc.decimals());

        amountInTokenToBorrow = leveragedPositionManager.getCollateralToGetFromFlashloanInToken(
            aWeth, 12 * 10 ** weth.decimals(), 8000, bob
        );
        vm.assertEq(amountInTokenToBorrow, 4 * 12 * 10 ** weth.decimals());

        amountInTokenToBorrow = leveragedPositionManager.getCollateralToGetFromFlashloanInToken(
            aUsdc, 34 * 10 ** usdc.decimals(), 8000, bob
        );
        vm.assertEq(amountInTokenToBorrow, 4 * 34 * 10 ** usdc.decimals());

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
        uint256 amountInTokenToBorrow;

        amountInTokenToBorrow = leveragedPositionManager.getCollateralToGetFromFlashloanInToken(
            aWeth, 12 * 10 ** weth.decimals(), 8000, alice
        );
        vm.assertEq(amountInTokenToBorrow, 0);
    }
}
