// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {IPool} from "@src/vendors/aaveV3/interfaces/IPool.sol";
import {IUniswapV2Pair} from "@src/vendors/uniswapV2Core/interfaces/IUniswapV2Pair.sol";
import {IUniswapV2Callee} from "@src/vendors/uniswapV2Core/interfaces/IUniswapV2Callee.sol";

import {SafeERC20} from "@openzeppelin/token/ERC20/utils/SafeERC20.sol";

import {ILeveragedPositionManager} from "@src/interface/ILeveragedPositionManager.sol";

/// @title LeveragedPositionManagerBase.
/// @author Keyring Network -- mgnfy-view.
/// @notice A contract to open leveraged positions on Aave V3 or it's forks.
contract LeveragedPositionManager is ILeveragedPositionManager, IUniswapV2Callee {
    using SafeERC20 for IERC20;

    /// @dev Basis points, 10,000.
    uint16 private constant BPS = 1e4;
    /// @dev The default referral code to be used while performing different actions on
    /// Aave V3.
    uint8 private constant DEFAULT_REFERRAL_CODE = 0;

    /// @notice Allows you to increase the size of your leveraged position. Also used to open a
    /// leveraged position. Anyone can open a leveraged position on behalf of any other user.
    /// @param _params The params to open the position or increase the position size with.
    function increaseLeveragedPosition(TakeLeveragedPosition memory _params) external {
        _validateParams(_params);

        address thisAddress = address(this);
        IUniswapV2Pair pair = IUniswapV2Pair(_params.uniswapV2Pair);
        (uint256 amount0, uint256 amount1) = pair.token0() == _params.supplyToken
            ? (_params.amountSupplyToken, uint256(0))
            : (uint256(0), _params.amountSupplyToken);
        bytes memory positionDetails = abi.encode(_params, Direction.INCREASE);

        IERC20(_params.supplyToken).safeTransferFrom(msg.sender, thisAddress, _params.bufferAmount);
        pair.swap(amount0, amount1, thisAddress, positionDetails);

        emit IncreaseLeveragedPosition(msg.sender, _params);
    }

    /// @notice Allows you to decrease the size of your leveraged position, or close it completely.
    /// Only the owner of the position can close
    /// @param _params The params to close the position or decrease the position size with.
    function decreaseLeveragedPosition(TakeLeveragedPosition memory _params) external {
        _validateParams(_params);
        if (_params.user != msg.sender) revert LeveragedPositionManager__CallerNotPositionOwner();

        address thisAddress = address(this);
        IUniswapV2Pair pair = IUniswapV2Pair(_params.uniswapV2Pair);
        (uint256 amount0, uint256 amount1) = pair.token0() == _params.borrowToken
            ? (_params.amountBorrowToken, uint256(0))
            : pair.token1() == _params.borrowToken ? (uint256(0), _params.amountBorrowToken) : (uint256(0), uint256(0));
        bytes memory positionDetails = abi.encode(_params, Direction.INCREASE);

        IERC20(_params.borrowToken).safeTransferFrom(msg.sender, thisAddress, _params.bufferAmount);
        pair.swap(amount0, amount1, thisAddress, positionDetails);

        emit DecreaseLeveragedPosition(msg.sender, _params);
    }

    /// @notice Flash swap callback by Uniswap V2 pair. Based on whether the action is to increase or
    /// decrease the position, specific steps to fulfill that are carried out.
    /// @param _sender The address that initiated the flash swap. Only flash swaps initiated by this
    /// contract are allowed.
    /// @param _data The bytes encoded data required to increase or decrease the position.
    function uniswapV2Call(address _sender, uint256, uint256, bytes calldata _data) external {
        address thisAddress = address(this);
        (TakeLeveragedPosition memory params, Direction direction) =
            abi.decode(_data, (TakeLeveragedPosition, Direction));
        IPool aaveV3Pool = IPool(params.aaveV3Pool);
        address aToken = aaveV3Pool.getReserveData(params.supplyToken).aTokenAddress;

        if (_sender != thisAddress) revert LeveragedPositionManager__InvalidFlashSwapInitiator();
        if (direction == Direction.INCREASE) {
            uint256 supplyAmount = params.amountSupplyToken + params.bufferAmount;

            aaveV3Pool.supply(params.supplyToken, supplyAmount, thisAddress, DEFAULT_REFERRAL_CODE);
            aaveV3Pool.borrow(
                params.borrowToken,
                params.amountBorrowToken,
                params.interestRateMode,
                DEFAULT_REFERRAL_CODE,
                thisAddress
            );
            IERC20(params.borrowToken).safeTransfer(params.uniswapV2Pair, params.amountBorrowToken);
        } else {
            uint256 repayAmount = params.amountBorrowToken + params.bufferAmount;
            uint256 aTokensApproved = abi.decode(params.additionalData, (uint256));

            IERC20(params.borrowToken).approve(params.aaveV3Pool, repayAmount);
            aaveV3Pool.repay(params.borrowToken, repayAmount, params.interestRateMode, params.user);
            IERC20(aToken).safeTransferFrom(params.user, thisAddress, aTokensApproved);
            IERC20(aToken).approve(params.aaveV3Pool, aTokensApproved);
            aaveV3Pool.withdraw(params.supplyToken, params.amountSupplyToken, thisAddress);
            IERC20(params.supplyToken).safeTransfer(params.uniswapV2Pair, params.amountSupplyToken);
        }

        _sweepToken(aToken, params.user);
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

    /// @notice Sweeps tokens back to the caller at the end of the operation.
    /// @param _token The token to sweep.
    /// @param _to The address to direct the tokens to.
    function _sweepToken(address _token, address _to) internal {
        IERC20 token = IERC20(_token);

        uint256 tokenBalance = token.balanceOf(address(this));
        if (tokenBalance > 0) token.safeTransfer(_to, tokenBalance);
    }
}
