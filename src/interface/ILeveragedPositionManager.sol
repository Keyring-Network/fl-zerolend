// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ILeveragedPositionManager {
    enum Direction {
        INCREASE,
        DECREASE
    }

    struct TakeLeveragedPosition {
        address user;
        address supplyToken;
        address borrowToken;
        uint256 amountSupplyToken;
        uint256 bufferAmount;
        uint256 amountBorrowToken;
        address uniswapV2Pair;
        address aaveV3Pool;
        uint256 interestRateMode;
        bytes additionalData;
    }

    event IncreaseLeveragedPosition(address indexed caller, TakeLeveragedPosition indexed params);
    event DecreaseLeveragedPosition(address indexed caller, TakeLeveragedPosition indexed params);

    error LeveragedPositionManager__InvalidUniswapV2Pair();
    error LeveragedPositionManager__CallerNotPositionOwner();
    error LeveragedPositionManager__InvalidFlashSwapInitiator();
    error LeveragedPositionManager__InvalidAaveV3Pool();
}
