// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";

import {SafeERC20} from "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/access/Ownable.sol";

import {IPool} from "@src/vendors/aaveV3/interfaces/IPool.sol";
import {IUniswapV2Pair} from "@src/vendors/uniswapV2Core/interfaces/IUniswapV2Pair.sol";
import {IUniswapV2Callee} from "@src/vendors/uniswapV2Core/interfaces/IUniswapV2Callee.sol";
import {IFeeCollector} from "@src/interfaces/IFeeCollector.sol";
import {IUniswapV2Factory} from "@src/vendors/uniswapV2Core/interfaces/IUniswapV2Factory.sol";

import {FeeCollector} from "@src/FeeCollector.sol";
import {ILeveragedPositionManager} from "@src/interfaces/ILeveragedPositionManager.sol";

/// @title LeveragedPositionManagerBase.
/// @author Keyring Network -- mgnfy-view.
/// @notice A contract to manage leveraged positions on Aave V3 or its forks.
contract LeveragedPositionManager is Ownable, ILeveragedPositionManager, IUniswapV2Callee {
    using SafeERC20 for IERC20;

    /// @dev Basis points, 10,000.
    uint16 internal constant BPS = 1e4;
    /// @dev The default referral code to be used while performing different actions on
    /// Aave V3.
    uint8 internal constant DEFAULT_REFERRAL_CODE = 0;

    /// @dev The Uniswap V2 factory address.
    IUniswapV2Factory internal immutable i_uniswapV2Factory;
    /// @dev The fee charged for managing leveraged positions via this contract.
    uint16 internal s_feeInBps;
    /// @dev The fee collector contract address.
    IFeeCollector internal immutable i_feeCollector;
    /// @dev Caching this contract's address.
    address internal immutable i_thisAddress;

    /// @notice Initializes the contract. Also creates a fee vault to store any accumulated
    /// fees.
    /// @param _initialOwner The initial owner.
    /// @param _initialFeeInBps The initial fee in basis points.
    constructor(address _uniswapV2Factory, address _initialOwner, uint16 _initialFeeInBps) Ownable(_initialOwner) {
        i_uniswapV2Factory = IUniswapV2Factory(_uniswapV2Factory);

        if (_initialFeeInBps > BPS / 2) revert LeveragedPositionManager__MaxFeeExceeded();
        s_feeInBps = _initialFeeInBps;

        i_feeCollector = new FeeCollector();

        i_thisAddress = address(this);
    }

    /// @notice Allows the owner to charge a fee in basis points for managing leveraged positions.
    /// @param _newFeeInBps The new fee in basis points.
    function setFeeInBps(uint16 _newFeeInBps) external onlyOwner {
        if (_newFeeInBps > BPS / 2) revert LeveragedPositionManager__MaxFeeExceeded();

        s_feeInBps = _newFeeInBps;

        emit FeeSet(_newFeeInBps);
    }

    /// @notice Allows the owner to withdraw any collected fees.
    /// @param _token The token address.
    /// @param _amount The token amount to withdraw.
    /// @param _to The address to direct the withdrawn tokens to.
    function collectFees(address _token, uint256 _amount, address _to) external onlyOwner {
        i_feeCollector.withdrawFees(_token, _amount, _to);
    }

    /// @notice Allows you to increase the size of your leveraged position. Also used to open a
    /// leveraged position.
    /// @param _params The params to open the position or increase the position size with.
    function increaseLeveragedPosition(TakeLeveragedPosition memory _params) external {
        _validateParams(_params);

        IUniswapV2Pair pair = IUniswapV2Pair(_params.uniswapV2Pair);
        (uint256 amount0, uint256 amount1) = pair.token0() == _params.supplyToken
            ? (_params.amountSupplyToken, uint256(0))
            : (uint256(0), _params.amountSupplyToken);
        bytes memory positionDetails = abi.encode(_params, Direction.INCREASE);
        uint256 feeAmount = _calculateFees(_params.bufferAmount + _params.amountSupplyToken);

        IERC20(_params.supplyToken).safeTransferFrom(msg.sender, i_thisAddress, _params.bufferAmount);
        if (feeAmount > 0) IERC20(_params.supplyToken).safeTransferFrom(msg.sender, address(i_feeCollector), feeAmount);
        pair.swap(amount0, amount1, i_thisAddress, positionDetails);

        emit IncreaseLeveragedPosition(msg.sender, _params);
    }

    /// @notice Allows you to decrease the size of your leveraged position, or close it completely.
    /// Only the owner of the position can close
    /// @param _params The params to close the position or decrease the position size with.
    function decreaseLeveragedPosition(TakeLeveragedPosition memory _params) external {
        _validateParams(_params);

        IUniswapV2Pair pair = IUniswapV2Pair(_params.uniswapV2Pair);
        (uint256 amount0, uint256 amount1) = pair.token0() == _params.borrowToken
            ? (_params.amountBorrowToken, uint256(0))
            : (uint256(0), _params.amountBorrowToken);
        bytes memory positionDetails = abi.encode(_params, Direction.DECREASE);
        uint256 feeAmount = _calculateFees(_params.bufferAmount + _params.amountBorrowToken);

        IERC20(_params.borrowToken).safeTransferFrom(msg.sender, i_thisAddress, _params.bufferAmount);
        if (feeAmount > 0) IERC20(_params.borrowToken).safeTransferFrom(msg.sender, address(i_feeCollector), feeAmount);
        pair.swap(amount0, amount1, i_thisAddress, positionDetails);

        emit DecreaseLeveragedPosition(msg.sender, _params);
    }

    /// @notice Flash swap callback by Uniswap V2 pair. Based on whether the action is to increase or
    /// decrease the position, specific steps to fulfill that are carried out.
    /// @param _sender The address that initiated the flash swap. Only flash swaps initiated by this
    /// contract are allowed.
    /// @param _data The bytes encoded data required to increase or decrease the position.
    function uniswapV2Call(address _sender, uint256, uint256, bytes calldata _data) external {
        (TakeLeveragedPosition memory params, Direction direction) =
            abi.decode(_data, (TakeLeveragedPosition, Direction));
        IPool aaveV3Pool = IPool(params.aaveV3Pool);

        _validateFlashLoanCaller(_sender);

        if (direction == Direction.INCREASE) {
            uint256 supplyAmount = params.amountSupplyToken + params.bufferAmount;

            IERC20(params.supplyToken).approve(params.aaveV3Pool, supplyAmount);
            aaveV3Pool.supply(params.supplyToken, supplyAmount, params.user, DEFAULT_REFERRAL_CODE);
            aaveV3Pool.borrow(
                params.borrowToken,
                params.amountBorrowToken,
                params.interestRateMode,
                DEFAULT_REFERRAL_CODE,
                params.user
            );
            IERC20(params.borrowToken).safeTransfer(params.uniswapV2Pair, params.amountBorrowToken);
        } else {
            uint256 repayAmount = params.amountBorrowToken + params.bufferAmount;
            address aToken = aaveV3Pool.getReserveData(params.supplyToken).aTokenAddress;
            (uint256 aTokensApproved, uint256 supplyTokenBufferAmount) =
                abi.decode(params.additionalData, (uint256, uint256));

            if (supplyTokenBufferAmount > 0) {
                IERC20(params.supplyToken).safeTransferFrom(params.user, i_thisAddress, supplyTokenBufferAmount);
            }

            IERC20(params.borrowToken).approve(params.aaveV3Pool, repayAmount);
            aaveV3Pool.repay(params.borrowToken, repayAmount, params.interestRateMode, params.user);
            IERC20(aToken).safeTransferFrom(params.user, i_thisAddress, aTokensApproved);
            IERC20(aToken).approve(params.aaveV3Pool, aTokensApproved);
            aaveV3Pool.withdraw(params.supplyToken, params.amountSupplyToken, i_thisAddress);
            IERC20(params.supplyToken).safeTransfer(
                params.uniswapV2Pair, params.amountSupplyToken + supplyTokenBufferAmount
            );

            _sweepToken(aToken, params.user);
        }

        _sweepToken(params.supplyToken, params.user);
        _sweepToken(params.borrowToken, params.user);
    }

    /// @notice Validates the input params to increase or decrease a position size.
    /// @param _params The position management params.
    function _validateParams(TakeLeveragedPosition memory _params) internal view {
        IUniswapV2Pair pair = IUniswapV2Pair(_params.uniswapV2Pair);
        IPool aaveV3Pool = IPool(_params.aaveV3Pool);
        address token0 = pair.token0();
        address token1 = pair.token1();

        if (_params.user != msg.sender) revert LeveragedPositionManager__CallerNotPositionOwner();
        if (
            (_params.supplyToken != token0 && _params.borrowToken != token0)
                || (_params.supplyToken != token1 && _params.borrowToken != token1)
        ) {
            revert LeveragedPositionManager__InvalidUniswapV2Pair();
        }
        if (aaveV3Pool.getReserveData(_params.supplyToken).aTokenAddress == address(0)) {
            revert LeveragedPositionManager__InvalidAaveV3Pool();
        }
    }

    /// @notice Calculates the fee for the given token amount.
    /// @param _amount The token amount.
    function _calculateFees(uint256 _amount) internal view returns (uint256) {
        uint256 feeAmount = (_amount * s_feeInBps) / BPS;

        return feeAmount;
    }

    /// @notice Checks if the flash loan callback was initiated by a valid Uniswap v2 pair.
    function _validateFlashLoanCaller(address _sender) internal view {
        IUniswapV2Pair pair = IUniswapV2Pair(msg.sender);

        address token0 = pair.token0();
        address token1 = pair.token1();

        if (_sender != i_thisAddress) revert LeveragedPositionManager__InvalidFlashSwapInitiator();
        if (msg.sender != i_uniswapV2Factory.getPair(token0, token1)) {
            revert LeveragedPositionManager__InvalidUniswapV2Pair();
        }
    }

    /// @notice Sweeps tokens back to the caller at the end of the operation.
    /// @param _token The token to sweep.
    /// @param _to The address to direct the tokens to.
    function _sweepToken(address _token, address _to) internal {
        IERC20 token = IERC20(_token);

        uint256 tokenBalance = token.balanceOf(i_thisAddress);
        if (tokenBalance > 0) token.safeTransfer(_to, tokenBalance);
    }

    /// @notice Gets the Uniswap V2 factory address.
    /// @return The Uniswap V2 factory address.
    function getUniswapV2Factory() external view returns (address) {
        return address(i_uniswapV2Factory);
    }

    /// @notice Gets the current fee applied on managing leveraged
    /// position in basis points.
    /// @return The fee applicable in basis points.
    function getFeeInBps() external view returns (uint16) {
        return s_feeInBps;
    }

    /// @notice Gets the fee collector address.
    /// @return The fee collector address.
    function getFeeCollector() external view returns (address) {
        return address(i_feeCollector);
    }

    /// @notice Gets the total fee accumulated in the fee collector for a given token.
    /// @param _token The token contract address.
    /// @return The amount of fee accumulated.
    function checkAccumulatedFees(address _token) external view returns (uint256) {
        return IERC20(_token).balanceOf(address(i_feeCollector));
    }
}
