// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";

import {SafeERC20} from "@openzeppelin/token/ERC20/utils/SafeERC20.sol";

import {IPool} from "@src/vendors/aaveV3/interfaces/IPool.sol";
import {ILeveragedPositionManager} from "@src/interfaces/ILeveragedPositionManager.sol";
import {ILeveragedPositionMover} from "@src/interfaces/ILeveragedPositionMover.sol";

import {Sweeper} from "@src/utils/Sweeper.sol";
import {MathHelper} from "@src/utils/MathHelper.sol";

/// @title PositionMover.
/// @author Keyring Network -- mgnfy-view.
/// @notice A contract that allows you to move your leveraged position from
/// Aave to another Aave fork, vice-versa, and between Aave forks.
contract PositionMover is Sweeper, ILeveragedPositionMover {
    using SafeERC20 for IERC20;

    /// @dev The leveraged position mnager contract.
    ILeveragedPositionManager internal immutable i_leveragedPositionManager;
    /// @dev Caching this contract's address.
    address internal immutable i_thisAddress;

    /// @notice Caches the contract address.
    constructor() {
        i_thisAddress = address(this);
    }

    /// @notice Allows a user to move their leveraged position from Aave to another Aave fork,
    /// vice-versa, and between Aave forks.
    /// @param _initialPosition The position to close/decrease.
    /// @param _amountToWithdraw The amount of tokens to withdraw from the pool to leave.
    /// @param _finalPosition The final position to obtain on the new pool.
    function move(
        ILeveragedPositionManager.TakeLeveragedPosition memory _initialPosition,
        uint256 _amountToWithdraw,
        ILeveragedPositionManager.TakeLeveragedPosition memory _finalPosition
    ) external {
        _validateParams(_initialPosition, _finalPosition);

        _decreaseLeveragedPosition(_initialPosition, _amountToWithdraw);
        _increaseLeveragedPosition(_finalPosition);

        _sweepToken(_initialPosition.supplyToken, msg.sender);
        _sweepToken(_initialPosition.borrowToken, msg.sender);

        emit PositionMoved(_initialPosition, _finalPosition);
    }

    /// @notice Validates the input params to increase or decrease a position size.
    /// @param _initialPosition The initial position params.
    /// @param _finalPosition The final position params.
    function _validateParams(
        ILeveragedPositionManager.TakeLeveragedPosition memory _initialPosition,
        ILeveragedPositionManager.TakeLeveragedPosition memory _finalPosition
    ) internal view {
        if (_initialPosition.user != _finalPosition.user && _finalPosition.user != msg.sender) {
            revert PositionMover__CallerNotPositionOwner();
        }
        if (
            _initialPosition.supplyToken != _finalPosition.supplyToken
                || _initialPosition.borrowToken != _initialPosition.borrowToken
        ) {
            revert PositionMover__InvalidPositionsToMove();
        }
        if (_initialPosition.uniswapV2Pair != _finalPosition.uniswapV2Pair) {
            revert PositionMover__InvalidUniswapV2Pair();
        }
        if (_initialPosition.aaveV3Pool == _finalPosition.aaveV3Pool) {
            revert PositionMover__InvalidLendingPools();
        }
    }

    /// @notice Closes/decreases the position size on the initial pool.
    /// @param _initialPosition The initial position params.
    /// @param _amountToWithdraw The amount of tokens supplied to withdraw.
    function _decreaseLeveragedPosition(
        ILeveragedPositionManager.TakeLeveragedPosition memory _initialPosition,
        uint256 _amountToWithdraw
    ) internal {
        IERC20(_initialPosition.borrowToken).safeTransferFrom(msg.sender, i_thisAddress, _initialPosition.bufferAmount);

        uint256 feeAmount = MathHelper.calculateFees(
            i_leveragedPositionManager.getFeeInBps(), _initialPosition.bufferAmount + _initialPosition.amountBorrowToken
        );
        if (feeAmount > 0) {
            IERC20(_initialPosition.borrowToken).safeTransferFrom(msg.sender, i_thisAddress, feeAmount);
        }

        IERC20(_initialPosition.borrowToken).approve(
            address(i_leveragedPositionManager), _initialPosition.bufferAmount + feeAmount
        );
        i_leveragedPositionManager.decreaseLeveragedPosition(_initialPosition);

        if (_amountToWithdraw > 0) {
            IPool(_initialPosition.aaveV3Pool).withdraw(
                _initialPosition.supplyToken, _amountToWithdraw, _initialPosition.user
            );
        }
    }

    /// @notice Opens/increases the position size on the final pool.
    /// @param _finalPosition The final position params.
    function _increaseLeveragedPosition(ILeveragedPositionManager.TakeLeveragedPosition memory _finalPosition)
        internal
    {
        IERC20(_finalPosition.supplyToken).safeTransferFrom(msg.sender, i_thisAddress, _finalPosition.bufferAmount);

        uint256 feeAmount = MathHelper.calculateFees(
            i_leveragedPositionManager.getFeeInBps(), _finalPosition.bufferAmount + _finalPosition.amountSupplyToken
        );
        if (feeAmount > 0) {
            IERC20(_finalPosition.supplyToken).safeTransferFrom(msg.sender, i_thisAddress, feeAmount);
        }

        IERC20(_finalPosition.supplyToken).approve(
            address(i_leveragedPositionManager), _finalPosition.bufferAmount + feeAmount
        );
        i_leveragedPositionManager.increaseLeveragedPosition(_finalPosition);
    }

    /// @notice Gets the leveraged position manager contract address.
    /// @return The leveraged position manager contract address.
    function getLeveragedPositionManager() external view returns (address) {
        return address(i_leveragedPositionManager);
    }
}
