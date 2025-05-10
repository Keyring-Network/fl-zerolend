// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";

import {SafeERC20} from "@openzeppelin/token/ERC20/utils/SafeERC20.sol";

import {IFeeCollector} from "@src/interfaces/IFeeCollector.sol";

/// @title FeeCollector.
/// @author Keyring Network -- mgnfy-view.
/// @notice A contract to collect and withdraw fees, owned by the leveraged position manager.
/// We require this contract since leveraged position manager is not supposed to hold any tokens
/// at any point in time, and any excess tokens after performing increase/decrease position size
/// operations are sweeped to the caller.
contract FeeCollector is IFeeCollector {
    using SafeERC20 for IERC20;

    /// @dev Address of the leveraged position manager contract.
    address private immutable i_leveragedPositionManager;

    /// @notice Initializes the contract by setting the leveraged position manager
    /// address.
    constructor() {
        i_leveragedPositionManager = msg.sender;
    }

    /// @notice Allows the leveraged position manager to withdraw fees to any address.
    /// @param _token The token to withdraw.
    /// @param _amount The amount to withdraw.
    /// @param _to The address to withdraw to.
    function withdrawFees(address _token, uint256 _amount, address _to) external {
        _onlyLeveragedPositionManager();

        IERC20(_token).safeTransfer(_to, _amount);

        emit FeeCollected(_token, _amount, _to);
    }

    /// @notice Checks if the caller is the leveraged position manager contract. Reverts if not.
    function _onlyLeveragedPositionManager() internal view {
        if (msg.sender != i_leveragedPositionManager) {
            revert FeeCollector__NotLeveragedPositionManager();
        }
    }

    /// @notice Gets the address of the leveraged position manager.
    /// @return The address of the leveraged position manager contract.
    function getLeveragedPositionManager() external view returns (address) {
        return i_leveragedPositionManager;
    }
}
