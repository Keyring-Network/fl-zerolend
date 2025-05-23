// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract MaliciousUniswapV2Pair {
    address private s_token0;
    address private s_token1;

    error MaliciousUniswapV2Pair__CallFailed();

    constructor(address _token0, address _token1) {
        s_token0 = _token0;
        s_token1 = _token1;
    }

    function token0() external view returns (address) {
        return s_token0;
    }

    function token1() external view returns (address) {
        return s_token1;
    }

    function externalCall(address _addressToCall, bytes memory _calldata, uint256 _value) external {
        (bool success,) = _addressToCall.call{value: _value}(_calldata);
        if (!success) revert MaliciousUniswapV2Pair__CallFailed();
    }
}
