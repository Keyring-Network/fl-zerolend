// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IUniswapV2Callee {
    function uniswapV2Call(address _sender, uint256 _amount0, uint256 _amount1, bytes calldata _data) external;
}
