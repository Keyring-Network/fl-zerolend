// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";

import {Test} from "forge-std/Test.sol";

import {ILeveragedPositionManager} from "@src/interfaces/ILeveragedPositionManager.sol";
import {ICreditDelegationToken} from "@src/vendors/aaveV3/interfaces/ICreditDelegationToken.sol";
import {IPool} from "@src/vendors/aaveV3/interfaces/IPool.sol";
import {DataTypes} from "@src/vendors/aaveV3/DataTypes.sol";

import {LeveragedPositionManager} from "@src/LeveragedPositionManager.sol";

contract TestBase is Test {
    uint256 internal mainnetFork;
    uint256 internal startBlockNumber;

    address internal user1;
    uint256 internal userKey;

    address internal usdc;
    address internal weth;

    address internal uniswapUsdcWethPair;
    address internal aaveV3Pool;
    address internal aUSDC;
    address internal aWeth;
    address internal variableDebtUsdcToken;
    address internal variableDebtWethToken;

    LeveragedPositionManager internal leveragedPositionManager;

    error TestBase__InvalidTokensPassed();

    function setUp() public {
        string memory RPC_URL = vm.envString("RPC_URL");
        if (bytes(RPC_URL).length == 0) {
            RPC_URL = "https://ethereum-rpc.publicnode.com";
        }
        mainnetFork = vm.createSelectFork(RPC_URL);

        startBlockNumber = 22451521;
        vm.rollFork(startBlockNumber);

        (user1, userKey) = makeAddrAndKey("user1");

        usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

        uniswapUsdcWethPair = 0xB4e16d0168e52d35CaCD2c6185b44281Ec28C9Dc;
        aaveV3Pool = 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2;

        DataTypes.ReserveData memory usdcPoolData = IPool(aaveV3Pool).getReserveData(usdc);
        DataTypes.ReserveData memory wethPoolData = IPool(aaveV3Pool).getReserveData(weth);
        aUSDC = usdcPoolData.aTokenAddress;
        aWeth = wethPoolData.aTokenAddress;
        variableDebtUsdcToken = usdcPoolData.variableDebtTokenAddress;
        variableDebtWethToken = wethPoolData.variableDebtTokenAddress;

        leveragedPositionManager = new LeveragedPositionManager();
    }

    function _increaseLeveragedPosition(ILeveragedPositionManager.TakeLeveragedPosition memory _params, address _user)
        internal
    {
        deal(_params.supplyToken, _user, _params.bufferAmount);

        vm.startPrank(_user);
        IERC20(_params.supplyToken).approve(address(leveragedPositionManager), _params.bufferAmount);

        address variableDebtToken = _params.borrowToken == usdc
            ? variableDebtUsdcToken
            : _params.borrowToken == weth ? variableDebtWethToken : address(0);
        if (variableDebtToken == address(0)) revert TestBase__InvalidTokensPassed();

        ICreditDelegationToken(variableDebtToken).approveDelegation(
            address(leveragedPositionManager), _params.amountBorrowToken
        );
        leveragedPositionManager.increaseLeveragedPosition(_params);
        vm.stopPrank();
    }
}
