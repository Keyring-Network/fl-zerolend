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

contract GetAmountToBorrowTest is Test {
    DeployMockProtocolScript public script;
    MintableERC20 public weth;
    MintableERC20 public usdc;
    IPool public pool;
    AToken public aWeth;
    AToken public aUsdc;
    LeveragedPositionManager public leveragedPositionManager;

    address public alice = makeAddr("Alice");
    address public bob = makeAddr("Bob");

    struct TestCase {
        string name;
        AToken aToken;
        int256 initialAmount;
        uint256 initialLtv;
        int256 tokenAmount;
        uint256 targetLtv;
        int256 expectedAmount;
        bool shouldRevert;
        bytes4 revertSelector;
    }

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
        weth.mint(bob, 1000 * 10 ** weth.decimals());
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

    function test_NewPositionWith80Ltv() public {
        TestCase memory testCase = TestCase({
            name: "New position with 80% LTV",
            aToken: aWeth,
            initialAmount: 0,
            initialLtv: 0,
            tokenAmount: 100e18,
            targetLtv: 8000,
            expectedAmount: 400e18,
            shouldRevert: false,
            revertSelector: bytes4(0)
        });
        runTestCase(testCase);
    }

    function test_IncreaseLeverageFrom50To80Ltv() public {
        TestCase memory testCase = TestCase({
            name: "Increase leverage from 50% to 80% LTV",
            aToken: aWeth,
            initialAmount: 300e18,
            initialLtv: 5000,
            tokenAmount: 100e18,
            targetLtv: 8000,
            expectedAmount: 850e18,
            shouldRevert: false,
            revertSelector: bytes4(0)
        });
        runTestCase(testCase);
    }

    function test_DecreaseLeverageFrom6666To50LtvWithWithdrawal() public {
        TestCase memory testCase = TestCase({
            name: "Decrease leverage from 66.66% to 50% LTV with withdrawal",
            aToken: aWeth,
            initialAmount: 300e18,
            initialLtv: 6666,
            tokenAmount: -50e18,
            targetLtv: 5000,
            expectedAmount: -150e18,
            shouldRevert: false,
            revertSelector: bytes4(0)
        });
        runTestCase(testCase);
    }

    function test_NoFlashLoanNeededWithdrawal() public {
        TestCase memory testCase = TestCase({
            name: "No flash loan needed (withdrawal)",
            aToken: aWeth,
            initialAmount: 200e18,
            initialLtv: 5000,
            tokenAmount: 0,
            targetLtv: 5000,
            expectedAmount: 0,
            shouldRevert: false,
            revertSelector: bytes4(0)
        });
        runTestCase(testCase);
    }

    function test_NoFlashLoanNeededDeposit() public {
        TestCase memory testCase = TestCase({
            name: "No flash loan needed (deposit)",
            aToken: aWeth,
            initialAmount: 200e18,
            initialLtv: 5000,
            tokenAmount: 0,
            targetLtv: 5000,
            expectedAmount: 0,
            shouldRevert: false,
            revertSelector: bytes4(0)
        });
        runTestCase(testCase);
    }

    function test_UnwindPositionFrom80To0Ltv() public {
        TestCase memory testCase = TestCase({
            name: "Unwind position from 80% to 0% LTV",
            aToken: aWeth,
            initialAmount: 100e18,
            initialLtv: 8000,
            tokenAmount: 0,
            targetLtv: 0,
            expectedAmount: -80e18,
            shouldRevert: false,
            revertSelector: bytes4(0)
        });
        runTestCase(testCase);
    }

    function test_IncreaseLtvWhileWithdrawing() public {
        TestCase memory testCase = TestCase({
            name: "Increase LTV while withdrawing",
            aToken: aWeth,
            initialAmount: 300e18,
            initialLtv: 5000,
            tokenAmount: -50e18,
            targetLtv: 8000,
            expectedAmount: 250e18,
            shouldRevert: false,
            revertSelector: bytes4(0)
        });
        runTestCase(testCase);
    }

    function test_InsufficientCollateral() public {
        TestCase memory testCase = TestCase({
            name: "Insufficient collateral",
            aToken: aWeth,
            initialAmount: 100e18,
            initialLtv: 5000,
            tokenAmount: -150e18,
            targetLtv: 5000,
            expectedAmount: 0,
            shouldRevert: true,
            revertSelector: LeveragedPositionManager.InvalidResultingCollateral.selector
        });
        runTestCase(testCase);
    }

    function test_InvalidTargetLtv() public {
        TestCase memory testCase = TestCase({
            name: "Invalid target LTV",
            aToken: aWeth,
            initialAmount: 100e18,
            initialLtv: 5000,
            tokenAmount: 100e18,
            targetLtv: 10000,
            expectedAmount: 0,
            shouldRevert: true,
            revertSelector: LeveragedPositionManager.LtvTooHigh.selector
        });
        runTestCase(testCase);
    }

    function test_MultipleDepositsWithExistingCollateral() public {
        TestCase memory testCase = TestCase({
            name: "Multiple deposits with existing collateral",
            aToken: aWeth,
            initialAmount: 10e18,
            initialLtv: 0,
            tokenAmount: 8e18,
            targetLtv: 8000,
            expectedAmount: 4 * 28e18,
            shouldRevert: false,
            revertSelector: bytes4(0)
        });
        runTestCase(testCase);
    }

    function runTestCase(TestCase memory testCase) internal {
        // Set up initial position if needed
        if (testCase.initialAmount != 0) {
            vm.startPrank(bob);
            leveragedPositionManager.takePosition(
                testCase.aToken,
                testCase.initialAmount,
                testCase.initialLtv,
                2
            );
            vm.stopPrank();
        }

        // Run the test
        if (testCase.shouldRevert) {
            vm.expectRevert(testCase.revertSelector);
        }
        
        int256 result = leveragedPositionManager.getAmountToBorrowInFlashLoan(
            testCase.aToken,
            testCase.tokenAmount,
            testCase.targetLtv,
            bob
        );

        if (!testCase.shouldRevert) {
            assertEq(
                result,
                testCase.expectedAmount,
                string.concat("Test case failed : ", testCase.name)
            );
        }
    }
}
