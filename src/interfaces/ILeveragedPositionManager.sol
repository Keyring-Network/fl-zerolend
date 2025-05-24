// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title ILeveragedPositionManager.
/// @author Keyring Network -- mgnfy-view.
/// @notice Interface for the Leveraged Position Manager contract.
interface ILeveragedPositionManager {
    /// @notice Enum indicating whether to increase the leveraged position size,
    /// or decrease it.
    enum Direction {
        INCREASE,
        DECREASE
    }

    /// @notice Struct to open, close, or adjust leveraged position size.
    /// @param user Address of the owner of the leveraged position.
    /// @param supplyToken The token to supply.
    /// @param borrowToken The token to borrow.
    /// @param amountSupplyToken The amount of supply token to flash loan while increasing
    /// position size, or the amount to repay while decreasing position size.
    /// @param bufferAmount The initial supply token amount to procure to increase position size,
    /// or the initial borrow token amount to use to repay the debt with.
    /// @param amountBorrowToken The amount of tokens to borrow while increasing position size, or the amount
    /// of tokens to repay (along with buffer amount) while decreasing position size.
    /// @param uniswapV2Pair The uniswap v2 pool to flash swap from.
    /// @param aaveV3Pool The aave v3 pool to open a leveraged position on.
    /// @param interestRateMode The interest rate mode (variable or stable) to use for borrowing.
    /// @param additionalData Used exclusively for decreasing position size. Specifies the amount of aTokens to
    /// use to withdraw the supplied tokens, and a buffer supply token amount to cover any fees.
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

    event FeeSet(uint16 indexed feeInBps);
    event PositionManagerSet(address user, address operator, bool status);
    event IncreaseLeveragedPosition(address indexed caller, TakeLeveragedPosition indexed params);
    event DecreaseLeveragedPosition(address indexed caller, TakeLeveragedPosition indexed params);

    error LeveragedPositionManager__MaxFeeExceeded();
    error LeveragedPositionManager__InvalidUniswapV2Pair();
    error LeveragedPositionManager__CallerNotPositionOwner();
    error LeveragedPositionManager__InvalidFlashSwapInitiator();
    error LeveragedPositionManager__InvalidAaveV3Pool();

    function setFeeInBps(uint16 _newFeeInBps) external;
    function setOperator(address _operator, bool _set) external;
    function collectFees(address _token, uint256 _amount, address _to) external;
    function increaseLeveragedPosition(TakeLeveragedPosition memory _params) external;
    function decreaseLeveragedPosition(TakeLeveragedPosition memory _params) external;
    function getUniswapV2Factory() external view returns (address);
    function getFeeInBps() external view returns (uint16);
    function getFeeCollector() external view returns (address);
    function isPermittedPositionManager(address _user, address _operator) external view returns (bool);
    function checkAccumulatedFees(address _token) external view returns (uint256);
}
