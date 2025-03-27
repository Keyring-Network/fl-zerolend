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
        aWeth = AToken(script.aWeth());
        aUsdc = AToken(script.aUsdc());
        
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

    function test_AmountInTokenToBorrow() public {
        uint256 amountInTokenToBorrow = leveragedPositionManager.getCollateralToGetFromFlashloanInToken(aWeth, 10000, 8000);
        console.log("amountInTokenToBorrow", amountInTokenToBorrow);
    }
}
