// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IFeeCollector {
    event FeeCollected(address indexed token, uint256 indexed amount, address indexed to);

    error FeeCollector__NotLeveragedPositionManager();

    function withdrawFees(address _token, uint256 _amount, address _to) external;
    function getLeveragedPositionManager() external view returns (address);
}
