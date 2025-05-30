// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";

import {Test} from "forge-std/Test.sol";

import {ILeveragedPositionManager} from "@src/interfaces/ILeveragedPositionManager.sol";
import {ICreditDelegationToken} from "@src/vendors/aaveV3/interfaces/ICreditDelegationToken.sol";
import {IPool} from "@src/vendors/aaveV3/interfaces/IPool.sol";
import {DataTypes} from "@src/vendors/aaveV3/DataTypes.sol";

import {LeveragedPositionManager} from "@src/LeveragedPositionManager.sol";
import {LeveragedPositionMover} from "@src/LeveragedPositionMover.sol";

contract TestBase is Test {
    struct SampleLeveragedPositionParams {
        uint256 wethAmount;
        uint256 bufferAmount;
        uint256 usdcAmount;
        uint256 expectedFeeAmount;
    }

    uint16 internal constant BPS = 1e4;
    uint256 internal constant STABLE_INTEREST_RATE_MODE = 1;
    uint256 internal constant VARIABLE_INTEREST_RATE_MODE = 2;

    uint256 internal mainnetFork;
    uint256 internal startBlockNumber;
    uint256 internal ethUsdcDipBlockNumber;

    address internal owner;
    address internal user1;
    uint256 internal userKey;
    uint16 internal feeInBps;

    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    address internal constant UNISWAP_V2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address internal constant UNISWAP_V2_USDC_WETH_PAIR = 0xB4e16d0168e52d35CaCD2c6185b44281Ec28C9Dc;
    address internal AAVE_V3_POOL = 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2;
    address internal aUsdc;
    address internal aWeth;
    address internal variableDebtUsdcToken;
    address internal variableDebtWethToken;

    SampleLeveragedPositionParams internal sampleIncreaseLeveragedPositionParams;
    SampleLeveragedPositionParams internal sampleDecreaseLeveragedPositionParams;

    LeveragedPositionManager internal leveragedPositionManager;
    LeveragedPositionMover internal leveragedPositionMover;

    error TestBase__InvalidTokensPassed();

    function setUp() public virtual {
        string memory RPC_URL = vm.envString("RPC_URL");
        if (bytes(RPC_URL).length == 0) {
            RPC_URL = "https://ethereum-rpc.publicnode.com";
        }
        mainnetFork = vm.createSelectFork(RPC_URL);

        startBlockNumber = 22451521;
        vm.rollFork(startBlockNumber);

        owner = makeAddr("owner");
        (user1, userKey) = makeAddrAndKey("user1");
        feeInBps = 100;

        DataTypes.ReserveData memory usdcPoolData = IPool(AAVE_V3_POOL).getReserveData(USDC);
        DataTypes.ReserveData memory wethPoolData = IPool(AAVE_V3_POOL).getReserveData(WETH);
        aUsdc = usdcPoolData.aTokenAddress;
        aWeth = wethPoolData.aTokenAddress;
        variableDebtUsdcToken = usdcPoolData.variableDebtTokenAddress;
        variableDebtWethToken = wethPoolData.variableDebtTokenAddress;

        uint256 wethAmount = 5 * 10 ** (IERC20Metadata(WETH).decimals() - 1);
        uint256 usdcAmount = 1_200 * 10 ** IERC20Metadata(USDC).decimals();
        uint256 expectedWethFeeAmount = (wethAmount * 2 * feeInBps) / BPS;

        uint256 usdcBufferAmount = 0 * 10 ** IERC20Metadata(USDC).decimals();
        uint256 expectedUsdcFeeAmount = ((usdcAmount + usdcBufferAmount) * feeInBps) / BPS;

        sampleIncreaseLeveragedPositionParams = SampleLeveragedPositionParams({
            wethAmount: wethAmount,
            bufferAmount: wethAmount,
            usdcAmount: usdcAmount,
            expectedFeeAmount: expectedWethFeeAmount
        });
        sampleDecreaseLeveragedPositionParams = SampleLeveragedPositionParams({
            wethAmount: wethAmount,
            bufferAmount: usdcBufferAmount,
            usdcAmount: usdcAmount,
            expectedFeeAmount: expectedUsdcFeeAmount
        });

        leveragedPositionManager = new LeveragedPositionManager(UNISWAP_V2_FACTORY, owner, feeInBps);
        leveragedPositionMover = new LeveragedPositionMover(address(leveragedPositionManager));

        vm.label(USDC, "USDC");
        vm.label(WETH, "WETH");
        vm.label(UNISWAP_V2_FACTORY, "Uniswap V2 Factory");
        vm.label(UNISWAP_V2_USDC_WETH_PAIR, "Uniswap V2 USDC WETH Pair");
        vm.label(aUsdc, "aUSDC");
        vm.label(aWeth, "aWeth");
        vm.label(variableDebtUsdcToken, "Variable Debt USDC Token");
        vm.label(variableDebtWethToken, "Variable Debt WETH Token");
        vm.label(address(leveragedPositionManager), "LeveragedPositionManager");
        vm.label(address(leveragedPositionMover), "LeveragedPositionMover");
    }

    function _increaseLeveragedPosition(
        ILeveragedPositionManager.TakeLeveragedPosition memory _params,
        uint256 _feeAmount,
        address _user
    ) internal {
        deal(_params.supplyToken, _user, _params.bufferAmount + _feeAmount);

        vm.startPrank(_user);
        IERC20(_params.supplyToken).approve(address(leveragedPositionManager), _params.bufferAmount + _feeAmount);

        address variableDebtToken = _params.borrowToken == USDC
            ? variableDebtUsdcToken
            : _params.borrowToken == WETH ? variableDebtWethToken : address(0);
        if (variableDebtToken == address(0)) revert TestBase__InvalidTokensPassed();

        ICreditDelegationToken(variableDebtToken).approveDelegation(
            address(leveragedPositionManager), _params.amountBorrowToken
        );
        leveragedPositionManager.increaseLeveragedPosition(_params);
        vm.stopPrank();
    }

    function _decreaseLeveragedPosition(
        ILeveragedPositionManager.TakeLeveragedPosition memory _params,
        uint256 _feeAmount,
        address _user
    ) internal {
        vm.startPrank(_user);
        deal(_params.borrowToken, _user, _params.bufferAmount + _feeAmount);
        IERC20(_params.borrowToken).approve(address(leveragedPositionManager), _params.bufferAmount + _feeAmount);

        address aToken = _params.supplyToken == USDC ? aUsdc : _params.supplyToken == WETH ? aWeth : address(0);
        if (aToken == address(0)) revert TestBase__InvalidTokensPassed();

        (uint256 approvedATokenAmount, uint256 supplyTokenBufferAmount) =
            abi.decode(_params.additionalData, (uint256, uint256));
        IERC20(aToken).approve(address(leveragedPositionManager), approvedATokenAmount);

        deal(_params.supplyToken, _user, supplyTokenBufferAmount);
        IERC20(_params.supplyToken).approve(address(leveragedPositionManager), supplyTokenBufferAmount);

        leveragedPositionManager.decreaseLeveragedPosition(_params);
        vm.stopPrank();
    }

    function _setFees(uint16 _feeInBps) internal {
        vm.startPrank(owner);
        leveragedPositionManager.setFeeInBps(_feeInBps);
        vm.stopPrank();
    }

    function _setOperator(address _user, address _operator, bool _set) internal {
        vm.startPrank(_user);
        leveragedPositionManager.setOperator(_operator, _set);
        vm.stopPrank();
    }

    function _move(
        ILeveragedPositionManager.TakeLeveragedPosition memory _initialPosition,
        uint256 _initialPositionFeeAmount,
        uint256 _amountToWithdraw,
        ILeveragedPositionManager.TakeLeveragedPosition memory _finalPosition,
        uint256 _finalPositionFeeAmount,
        address _user
    ) internal {
        vm.startPrank(_user);
        leveragedPositionManager.setOperator(address(leveragedPositionMover), true);

        deal(_initialPosition.borrowToken, _user, _initialPosition.bufferAmount + _initialPositionFeeAmount);
        IERC20(_initialPosition.borrowToken).approve(
            address(leveragedPositionMover), _initialPosition.bufferAmount + _initialPositionFeeAmount
        );
        address initialPositionAToken =
            IPool(_initialPosition.aaveV3Pool).getReserveData(_initialPosition.supplyToken).aTokenAddress;
        (uint256 aTokensApproved, uint256 supplyTokenBufferAmount) =
            abi.decode(_initialPosition.additionalData, (uint256, uint256));
        IERC20(initialPositionAToken).approve(address(leveragedPositionManager), aTokensApproved);
        deal(_initialPosition.supplyToken, _user, supplyTokenBufferAmount);
        IERC20(_initialPosition.supplyToken).approve(address(leveragedPositionManager), supplyTokenBufferAmount);

        address aToken = IPool(_initialPosition.aaveV3Pool).getReserveData(_initialPosition.supplyToken).aTokenAddress;
        IERC20(aToken).approve(address(leveragedPositionMover), _amountToWithdraw);

        deal(_finalPosition.supplyToken, _user, _finalPosition.bufferAmount + _finalPositionFeeAmount);
        IERC20(_finalPosition.supplyToken).approve(
            address(leveragedPositionMover), _finalPosition.bufferAmount + _finalPositionFeeAmount
        );
        address finalPositionVariableDebtToken =
            IPool(_finalPosition.aaveV3Pool).getReserveData(_finalPosition.borrowToken).variableDebtTokenAddress;
        ICreditDelegationToken(finalPositionVariableDebtToken).approveDelegation(
            address(leveragedPositionManager), _finalPosition.amountBorrowToken
        );

        leveragedPositionMover.move(_initialPosition, _amountToWithdraw, _finalPosition);
        vm.stopPrank();
    }
}
