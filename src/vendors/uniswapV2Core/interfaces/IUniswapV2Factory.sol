// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IUniswapV2Factory {
    function feeTo() external view returns (address);
    function feeToSetter() external view returns (address);
    function getPair(address _tokenA, address _tokenB) external view returns (address);
    function allPairs(uint256) external view returns (address);
    function allPairsLength() external view returns (uint256);
    function createPair(address _tokenA, address _tokenB) external returns (address);
    function setFeeTo(address) external;
    function setFeeToSetter(address) external;
}
