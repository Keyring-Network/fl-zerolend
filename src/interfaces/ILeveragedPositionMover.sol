// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ILeveragedPositionManager} from "@src/interfaces/ILeveragedPositionManager.sol";

interface ILeveragedPositionMover {
    event PositionMoved(
        ILeveragedPositionManager.TakeLeveragedPosition indexed _initialPosition,
        ILeveragedPositionManager.TakeLeveragedPosition indexed _finalPosition
    );

    error PositionMover__CallerNotPositionOwner();
    error PositionMover__InvalidPositionsToMove();
    error PositionMover__InvalidUniswapV2Pair();
    error PositionMover__InvalidLendingPools();

    function move(
        ILeveragedPositionManager.TakeLeveragedPosition memory _initialPosition,
        uint256 _amountToWithdraw,
        ILeveragedPositionManager.TakeLeveragedPosition memory _finalPosition
    ) external;
    function getLeveragedPositionManager() external view returns (address);
}
