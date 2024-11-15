// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/Math.sol";

contract BondingCurve {
    struct Step {
        uint256 supply;
        uint256 price;
    }

    uint256 public immutable stepsLength;
    mapping(uint256 => uint256) public supplies;
    mapping(uint256 => uint256) public prices;

    constructor(uint256[] memory _supplies, uint256[] memory _prices) {
        require(_supplies.length == _prices.length, "Supplies and prices must have the same length");
        require(_supplies.length > 0, "Must provide at least one step");
        
        // Verify supplies are in ascending order
        for (uint256 i = 1; i < _supplies.length; i++) {
            require(_supplies[i] > _supplies[i-1], "Supplies must be in ascending order");
        }

        stepsLength = _supplies.length;
        
        // Copy arrays to immutable storage
        for (uint256 i = 0; i < _supplies.length; i++) {
            supplies[i] = _supplies[i];
            prices[i] = _prices[i];
        }
    }


    /**
     * @notice Calculate funds received when selling tokens using a stepped bonding curve
     * @dev For each step in the curve, calculates the refund based on current price
     * @param x0 Current total supply before the sale
     * @param deltaX Amount of tokens to sell
     * @return deltaY Amount of funds to receive for the tokens
     **/
    function getFundsReceived(uint256 x0, uint256 deltaX) public view returns (uint256 deltaY) {
        require(x0 >= deltaX, "Not enough tokens to sell");
        
        uint256 remainingAmount = deltaX;
        uint256 currentSupply = x0;
        
        for (uint256 i = 0; i < stepsLength; i++) {
            uint256 stepLowerBound = i > 0 ? supplies[i-1] : 0;
            
            if (currentSupply <= stepLowerBound) continue;
            
            uint256 tokensInStep = currentSupply - stepLowerBound;
            uint256 saleInStep = remainingAmount > tokensInStep ? tokensInStep : remainingAmount;
            
            deltaY += saleInStep * prices[i];
            remainingAmount -= saleInStep;
            currentSupply -= saleInStep;
            
            if (remainingAmount == 0) break;
        }
        
        require(remainingAmount == 0, "Refund calculation failed");
        return deltaY;
    }

    /**
     * @notice Calculate tokens received when buying with funds using a stepped bonding curve
     * @dev For each step in the curve, calculates tokens that can be bought at current price
     * @param x0 Current total supply before the purchase
     * @param deltaY Amount of funds to spend
     * @return deltaX Amount of tokens to receive for the funds
     **/
    function getAmountOut(uint256 x0, uint256 deltaY) public view returns (uint256 deltaX) {
        uint256 remainingFunds = deltaY;
        uint256 currentSupply = x0;
        
        for (uint256 i = 0; i < stepsLength; i++) {
            if (currentSupply >= supplies[i]) {
                continue;
            }
            
            uint256 stepSupply = (i == stepsLength - 1) ? type(uint256).max : supplies[i];
            uint256 availableInStep = stepSupply - currentSupply;
            uint256 priceInStep = prices[i];
            
            uint256 purchasableInStep = remainingFunds / priceInStep;
            uint256 purchaseInStep = Math.min(purchasableInStep, availableInStep);
            
            deltaX += purchaseInStep;
            remainingFunds -= purchaseInStep * priceInStep;
            currentSupply += purchaseInStep;
            
            if (remainingFunds < priceInStep) break;
        }
        
        return deltaX;
    }

}