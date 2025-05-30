// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ILeveragedPositionManager} from "@src/interfaces/ILeveragedPositionManager.sol";

interface ILeveragedPositionMover {
    event LeveragedPositionMoved(
        ILeveragedPositionManager.TakeLeveragedPosition indexed _initialPosition,
        ILeveragedPositionManager.TakeLeveragedPosition indexed _finalPosition
    );

    error LeveragedPositionMover__CallerNotPositionOwner();
    error LeveragedPositionMover__InvalidPositionsToMove();
    error LeveragedPositionMover__InvalidUniswapV2Pair();
    error LeveragedPositionMover__InvalidLendingPools();

    function move(
        ILeveragedPositionManager.TakeLeveragedPosition memory _initialPosition,
        uint256 _amountToWithdraw,
        ILeveragedPositionManager.TakeLeveragedPosition memory _finalPosition
    ) external;
    function getLeveragedPositionManager() external view returns (address);
}
