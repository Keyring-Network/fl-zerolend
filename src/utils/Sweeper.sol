// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";

import {SafeERC20} from "@openzeppelin/token/ERC20/utils/SafeERC20.sol";

/// @title Sweeper.
/// @author Keyring Network -- mgnfy-view.
/// @notice An abstract contract to sweep tokens in the contract to
/// the specified address.
abstract contract Sweeper {
    using SafeERC20 for IERC20;

    /// @notice Sweeps tokens in the contract back to the specified user when called.
    /// @param _token The token to sweep.
    /// @param _to The address to direct the tokens to.
    function _sweepToken(address _token, address _to) internal {
        IERC20 token = IERC20(_token);
        address thisAddress = address(this);

        uint256 tokenBalance = token.balanceOf(thisAddress);
        if (tokenBalance > 0) token.safeTransfer(_to, tokenBalance);
    }
}
