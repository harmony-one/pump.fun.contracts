## Version 20250213

This version mainly fixes bugs in version 20241221. Namely:

- `getSqrtPriceX96` was not implemented correctly. The result was in UD60x18 format, which means it was scaled by 1e18. This is now corrected.
- `burnTokenAndMintWinner` invokes the TWAP oracle on its execution path but did not correctly check sufficient time was elapsed as specified in version 20241221, thus resulting in a silent revert when elapsed time was insufficient. This error, among some other corner conditions, are now properly checked and raised.
- `burnTokenAndMintWinner` implementation mixed up winning token and the token being burned in computing amounts and liquidity, resulting non-sense values
- Tokens are now properly approved prior to adding more liquidity to Uniswap (during `burnTokenAndMintWinner`), including converting more ETH to WETH in the process.
- Fixed end-to-end tests. Now they properly verify publishing to Uniswap and burning-to-mint-winner are working without revert, and the resulting change of state makes sense (at least verifiable by manual inspection)

### Interface changes:

- `_sellReceivedAmount` (public function) now returns the fees charged, in addition to payment amount (in WETH) the user would have received
- `_sell` (internal function) similarly also returns the fees

### Bug fixes



## Version 20241221

### Mechanism changes:

- To ensure non-winning token holders able to convert their tokens to the winning token at a fair rate, the calculation and fee assessment for burning a non-winning token in exchange for winning token (after the winning token is published to Uniswap) is changed. The new mechanism addresses the problem that previously, non-winning token holders are only able to acquire the winning token (through burn-and-convert) at close to the highest price of the winning token, even the majority of the holders of the winning token already sold off their holdings on Uniswap. 
  - Fee is now only assessed once instead of twice from the conversion transaction.
  - The conversion rate is now based on the time-weighted average price over the last 120 seconds at the published pool on Uniswap, instead of based on the bonding curve of the winning token.
    - Specifically, first, the user's non-winning token is converted to native token (ONE) based on the bonding curve of the non-winning token
    - Then, a standard fee is deducted from the conversion. The amount is same as transactions for buying or selling tokens when a competition is still active
    - After that, the remaining native token is converted to the winning token, based on the current price at Uniswap.
    - If less than 120 seconds have elapsed since the pool was created, or at least 60 swaps have been executed on Uniswap, the conversion will fail.
- The collateral contributed by users who minted non-winning token is no longer immediately contributed to the pool as part of the initial liquidity when the pool is created. Instead, the collateral is contributed incrementally. Only the collateral contributed by users who minted the winning token is immediately contributed to the pool initially.
  - The collateral contributed by users who minted non-winning token is contributed to the pool only proportionally, when the user decides to burn the non-winning tokens to convert them into the winning token. 
  - An amount of winning-token is also minted to the factory and immediately contributed to the liquidity pool, equal to the amount minted to the user who executed the burn-and-convert. 

### Interface changes:

- Changed event structure `BurnTokenAndMintWinner`, removed a field that represents converted native token amount, added a field showing fees deducted
- Removed `claimFee()` function, which clears fee accumulator. Fees can only be withdrawn using `withdrawFee()` which does not reset statistics
- Changed `fee` public field to `feeAccumulated`
- Changed `WinnerLiquidityAdded` to use `actualTokenAmount` and `actualAssetAmount` fields instead of `amount0` and `amount1`

### Internal changes:

- Added function `getMintAmountPostPublish` to calculate the amount of tokens that should be minted based on Uniswap pool price, given the collateral amount. It reverts if the pool does not exist
- Added helper function `getSqrtPriceX96` to obtain current time-weighted average price from the Uniswap pool of the token
- Miscellaneous improvements on function mutability
- Changed `_mintLiquidity` parameters to `(address tokenAddress, uint256 tokenAmount, uint256 assetAmount, address recipient)` and making the function infers token0 and token1 internally, instead of relying on the caller. Similarly, it returns `uint256 actualTokenAmount, uint256 actualAssetAmount` in 3rd and 4th return parameters, instead of `amount0` and `amount1`