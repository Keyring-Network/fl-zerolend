// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title MathHelper.
/// @author Keyring Network -- mgnfy-view.
/// @notice A math helper library.
library MathHelper {
    /// @dev Basis points, 10,000.
    uint16 internal constant BPS = 1e4;

    /// @notice Calculates the fee for the given token amount.
    /// @param _amount The token amount.
    function calculateFees(uint16 _feeInBps, uint256 _amount) internal pure returns (uint256) {
        uint256 feeAmount = (_amount * _feeInBps) / BPS;

        return feeAmount;
    }
}
