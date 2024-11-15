// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/Math.sol";

interface IBondingCurve {
    /**
     * @notice Calculate the amount of funds received for selling tokens
     * @param x0 The current total supply of tokens
     * @param deltaX The amount of tokens to sell
     * @return deltaY The amount of funds to receive
     */
    function getFundsReceived(uint256 x0, uint256 deltaX) external view returns (uint256 deltaY);

    /**
     * @notice Calculate the amount of tokens received for a given amount of funds
     * @param x0 The current total supply of tokens
     * @param deltaY The amount of funds to spend
     * @return deltaX The amount of tokens to receive
     */
    function getAmountOut(uint256 x0, uint256 deltaY) external view returns (uint256 deltaX);

}