// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import "./libraries/TickMath.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
// import "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import {INonfungiblePositionManager} from "./interfaces/INonfungiblePositionManager.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import {mulDiv, sqrt} from "@prb/math/src/Common.sol";
import {Token} from "./Token.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";

interface IWETH is IERC20 {
    function deposit() external payable;

    function withdraw(uint) external;
}

interface IERC721Receiver {
    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data) external returns (bytes4);
}

abstract contract LiquidityManager is IERC721Receiver, Initializable, ContextUpgradeable {
    uint24 public constant UNISWAP_FEE = 3000;
    int24 private constant MIN_TICK = -887272;
    int24 private constant MAX_TICK = -MIN_TICK;
    int24 private constant TICK_SPACING = 60;
    uint16 private constant MIN_OBSERVATION_CARDINALITY = 60;
    uint32 private constant TWAP_DURATION = 120;

    IWETH public WETH;
    INonfungiblePositionManager public nonfungiblePositionManager;
    IUniswapV3Factory public uniswapV3Factory;

    error PoolNonExist();
    error PoolTooNew();

    function __LiquidityManager_init(address _uniswapV3Factory, address _nonfungiblePositionManager, address _weth) internal onlyInitializing {
        uniswapV3Factory = IUniswapV3Factory(_uniswapV3Factory);
        nonfungiblePositionManager = INonfungiblePositionManager(_nonfungiblePositionManager);
        WETH = IWETH(_weth);
    }

    function onERC721Received(address /*operator*/, address /*from*/, uint256 /*tokenId*/, bytes calldata) external pure returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    function getSqrtPriceX96(uint256 ethAmount, uint256 tokenAmount) public pure returns (uint160) {
        require(tokenAmount > 0, "Token amount must be greater than zero");

        uint256 ratio = (ethAmount * (2 ** 96)) / tokenAmount; // Scale by 2^96 before division
        uint256 sqrtRatio = sqrt(ratio);
        return uint160(sqrtRatio * (2 ** 48)); // Scale the result by 2^48
    }

    function _createLiquidityPool(address token0, address token1, uint24 fee) internal returns (address pool) {
        require(token0 < token1, "token0 > token1");

        pool = uniswapV3Factory.getPool(token0, token1, fee);

        require(pool == address(0), "Pool already created");

        pool = uniswapV3Factory.createPool(token0, token1, fee);
    }

    function _mintLiquidity(
        address tokenAddress,
        uint256 tokenAmount,
        uint256 assetAmount,
        address recipient
    ) internal returns (address pool, uint256 tokenId, uint128 liquidity, uint256 actualTokenAmount, uint256 actualAssetAmount) {
        address token0;
        address token1;
        uint256 amount0Desired;
        uint256 amount1Desired;
        if (tokenAddress < address(WETH)) {
            token0 = tokenAddress;
            token1 = address(WETH);
            amount0Desired = tokenAmount;
            amount1Desired = assetAmount;
        } else {
            token1 = tokenAddress;
            token0 = address(WETH);
            amount1Desired = tokenAmount;
            amount0Desired = assetAmount;
        }
        //        console.log("mintAmount/currentCollateral", tokenAmount, assetAmount);
        pool = _createLiquidityPool(token0, token1, UNISWAP_FEE);

        uint160 sqrtPriceX96 = getSqrtPriceX96(amount1Desired, amount0Desired);
        //        console.log("initial sqrtPriceX96", sqrtPriceX96);

        IUniswapV3Pool(pool).initialize(sqrtPriceX96);

        Token(token0).approve(address(nonfungiblePositionManager), amount0Desired);
        Token(token1).approve(address(nonfungiblePositionManager), amount1Desired);

        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
            token0: token0,
            token1: token1,
            fee: UNISWAP_FEE,
            tickLower: (MIN_TICK / TICK_SPACING) * TICK_SPACING,
            tickUpper: (MAX_TICK / TICK_SPACING) * TICK_SPACING,
            amount0Desired: amount0Desired,
            amount1Desired: amount1Desired,
            amount0Min: 0,
            amount1Min: 0,
            recipient: recipient,
            deadline: block.timestamp
        });

        (tokenId, liquidity, actualTokenAmount, actualAssetAmount) = nonfungiblePositionManager.mint(params);
        if (tokenAddress >= address(WETH)) {
            (actualTokenAmount, actualAssetAmount) = (actualAssetAmount, actualTokenAmount);
        }
        //        console.log("mint amount0Desired", amount0Desired);
        //        console.log("mint tokenAmount", tokenAmount);
        //        console.log("mint amount1Desired", amount1Desired);
        //        console.log("mint assetAmount", assetAmount);
        //        console.log("mint actualTokenAmount", actualTokenAmount);
        //        console.log("mint actualAssetAmount", actualAssetAmount);
        //        console.log("amount 1 balance ", Token(token1).balanceOf(address(this)));
        //        console.log("amount 0 balance ", Token(token0).balanceOf(address(this)));
    }

    function _increaseLiquidity(
        uint256 tokenId,
        uint256 amount0Desired,
        uint256 amount1Desired
    ) internal returns (uint128 liquidity, uint256 amount0, uint256 amount1) {
        INonfungiblePositionManager.IncreaseLiquidityParams memory params = INonfungiblePositionManager.IncreaseLiquidityParams({
            tokenId: tokenId,
            amount0Desired: amount0Desired,
            amount1Desired: amount1Desired,
            amount0Min: 0,
            amount1Min: 0,
            deadline: block.timestamp
        });
        (, , address token0, address token1, , , , , , , , ) = nonfungiblePositionManager.positions(tokenId);
        Token(token0).approve(address(nonfungiblePositionManager), amount0Desired);
        Token(token1).approve(address(nonfungiblePositionManager), amount1Desired);
        //        console.log("amount1Desired", amount1Desired);
        //        console.log("amount0Desired", amount0Desired);
        //        console.log("amount 1 balance ", Token(token1).balanceOf(address(this)));
        //        console.log("amount 0 balance ", Token(token0).balanceOf(address(this)));
        (liquidity, amount0, amount1) = nonfungiblePositionManager.increaseLiquidity(params);
    }

    function _increaseObservationCardinality(address tokenAddress) internal {
        address token0;
        address token1;
        if (tokenAddress < address(WETH)) {
            token0 = tokenAddress;
            token1 = address(WETH);
        } else {
            token1 = tokenAddress;
            token0 = address(WETH);
        }
        address pool = uniswapV3Factory.getPool(token0, token1, UNISWAP_FEE);
        IUniswapV3Pool(pool).increaseObservationCardinalityNext(MIN_OBSERVATION_CARDINALITY);
    }

    function getSpotSqrtPriceX96(address tokenAddress) public view returns (uint160) {
        address t0a = (tokenAddress < address(WETH)) ? tokenAddress : address(WETH);
        address t1a = (tokenAddress < address(WETH)) ? address(WETH) : tokenAddress;
        address pa = uniswapV3Factory.getPool(t0a, t1a, UNISWAP_FEE);
        if (pa == address(0)) {
            revert PoolNonExist();
        }
        (uint160 sqrtPriceX96, , , , , , ) = IUniswapV3Pool(pa).slot0();
        return sqrtPriceX96;
    }

    function getTwapSqrtPriceX96(address tokenAddress, uint32 duration) public view returns (uint160) {
        if (duration == 0) {
            return getSpotSqrtPriceX96(tokenAddress);
        }
        address t0a = (tokenAddress < address(WETH)) ? tokenAddress : address(WETH);
        address t1a = (tokenAddress < address(WETH)) ? address(WETH) : tokenAddress;
        address pa = uniswapV3Factory.getPool(t0a, t1a, UNISWAP_FEE);
        if (pa == address(0)) {
            revert PoolNonExist();
        }
        uint32[] memory obs = new uint32[](2);
        obs[0] = duration;
        obs[1] = 0;
        (, , uint16 observationIndex, uint16 observationCardinality, , , ) = IUniswapV3Pool(pa).slot0();
        (uint32 observationTimestamp, , , bool initialized) = IUniswapV3Pool(pa).observations((observationIndex + 1) % observationCardinality);
        if (!initialized) {
            (observationTimestamp, , , ) = IUniswapV3Pool(pa).observations(0);
        }
        if (block.timestamp - observationTimestamp < duration) {
            revert PoolTooNew();
        }
        (int56[] memory tickCums, ) = IUniswapV3Pool(pa).observe(obs);
        return TickMath.getSqrtRatioAtTick(int24((tickCums[1] - tickCums[0]) / int56(int32(duration))));
    }

    function getMintAmountPostPublish(uint256 collateralAmount, address tokenAddress) public view returns (uint256) {
        // price = token1 / token0, i.e. how many token1 is equivalent to 1 unit of token0
        uint160 sqrtPriceX96 = getTwapSqrtPriceX96(tokenAddress, TWAP_DURATION);
        //        console.log("sqrtPriceX96", sqrtPriceX96);
        //        console.log("collateralAmount", collateralAmount);
        // if sqrtPriceX96 is more than this, squaring it would overflow uint256
        uint256 sqrtCeiling = 340275971719517849884101479065584693834;
        if (tokenAddress > address(WETH)) {
            // collateral is token 0, so token amount = collateralAmount * price
            if (sqrtPriceX96 < sqrtCeiling) {
                // just square it
                uint256 priceX196 = uint256(sqrtPriceX96) ** 2;
                return mulDiv(collateralAmount, priceX196, 2 ** 196);
            } else {
                // lower to price to X128 precision first
                uint256 priceX128 = mulDiv(sqrtPriceX96, sqrtPriceX96, 2 ** 64);
                return mulDiv(collateralAmount, priceX128, 2 ** 128);
            }
        } else {
            // token amount = collateralAmount / price
            if (sqrtPriceX96 < sqrtCeiling) {
                uint256 priceX196 = uint256(sqrtPriceX96) ** 2;
                return mulDiv(collateralAmount, 2 ** 196, priceX196);
            } else {
                uint256 priceX128 = mulDiv(sqrtPriceX96, sqrtPriceX96, 2 ** 64);
                return mulDiv(collateralAmount, 2 ** 128, priceX128);
            }
        }
    }
}
