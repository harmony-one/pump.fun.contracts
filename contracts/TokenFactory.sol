// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {LiquidityManager} from "./LiquidityManager.sol";
import {BancorBondingCurve} from "./BancorBondingCurve.sol";
import {Token} from "./Token.sol";

contract TokenFactory is Initializable, OwnableUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable, LiquidityManager {
    uint256 public VERSION;
    uint256 public constant FEE_DENOMINATOR = 10000;
    mapping(uint256 => address[]) public tokensByCompetitionId;

    mapping(address => uint256) public competitionIds;
    uint256 public currentCompetitionId;

    address public tokenImplementation;
    BancorBondingCurve public bondingCurve;
    uint256 public feePercent; // bp
    uint256 public feeAccumulated;
    uint256 public feeWithdrawn;

    mapping(uint256 => address) public winners;
    mapping(uint256 => mapping(address => uint256)) public collateralById;

    mapping(address => address) public tokensCreators;
    mapping(address => address) public tokensPools;
    mapping(address => uint256) public liquidityPositionTokenIds;

    // Events
    event TokenCreated(address indexed token, string name, string symbol, string uri, address creator, uint256 competitionId, uint256 timestamp);
    event NewCompetitionStarted(uint256 competitionId, uint256 timestamp);
    event TokenBuy(address indexed token, uint256 amount0In, uint256 amount0Out, uint256 fee, uint256 timestamp);
    event TokenMinted(address indexed token, uint256 assetAmount, uint256 tokenAmount, uint256 timestamp);
    event TokenSell(address indexed token, uint256 amount0In, uint256 amount0Out, uint256 fee, uint256 timestamp);
    event SetWinner(address indexed winner, uint256 competitionId, uint256 timestamp);
    event BurnTokenAndMintWinner(
        address indexed sender,
        address indexed token,
        address indexed winnerToken,
        uint256 burnedAmount,
        uint256 mintedAmount,
        uint256 fee,
        uint256 timestamp
    );
    event WinnerLiquidityAdded(
        address indexed tokenAddress,
        address indexed tokenCreator,
        address indexed pool,
        address sender,
        uint256 tokenId,
        uint128 liquidity,
        uint256 actualTokenAmount,
        uint256 actualAssetAmount,
        uint256 timestamp
    );

    function initialize(
        address _tokenImplementation,
        address _uniswapV3Factory,
        address _nonfungiblePositionManager,
        address _bondingCurve,
        address _weth,
        uint256 _feePercent
    ) public initializer {
        __Ownable_init();
        __ReentrancyGuard_init();
        __LiquidityManager_init(_uniswapV3Factory, _nonfungiblePositionManager, _weth);

        VERSION = 20241221;
        tokenImplementation = _tokenImplementation;
        bondingCurve = BancorBondingCurve(_bondingCurve);
        feePercent = _feePercent;
        currentCompetitionId = 1;
    }

    /// @dev Required by UUPSUpgradeable to authorize upgrades
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    modifier inCompetition(address tokenAddress) {
        require(competitionIds[tokenAddress] == currentCompetitionId, "The competition for this token has already ended");
        _;
    }

    // Admin functions

    function startNewCompetition() external onlyOwner {
        currentCompetitionId = currentCompetitionId + 1;
        emit NewCompetitionStarted(currentCompetitionId, block.timestamp);
    }

    function setBondingCurve(address _bondingCurve) external onlyOwner {
        bondingCurve = BancorBondingCurve(_bondingCurve);
    }

    function setFeePercent(uint256 _feePercent) external onlyOwner {
        feePercent = _feePercent;
    }

    // Token functions

    function createToken(string memory name, string memory symbol, string memory uri) external returns (Token) {
        address tokenAddress = Clones.clone(tokenImplementation);
        Token token = Token(tokenAddress);
        token.initialize(name, symbol, uri, address(this));

        tokensByCompetitionId[currentCompetitionId].push(tokenAddress);
        competitionIds[tokenAddress] = currentCompetitionId;
        tokensCreators[tokenAddress] = msg.sender;

        emit TokenCreated(tokenAddress, name, symbol, uri, msg.sender, currentCompetitionId, block.timestamp);

        return token;
    }

    function buy(address tokenAddress) external payable nonReentrant inCompetition(tokenAddress) {
        _buy(tokenAddress, msg.sender, msg.value);
    }

    function _buy(address tokenAddress, address receiver, uint256 paymentAmount) internal returns (uint256) {
        uint256 _competitionId = competitionIds[tokenAddress];
        require(_competitionId > 0, "Token not found");
        require(paymentAmount > 0, "ETH not enough");

        Token token = Token(tokenAddress);
        (uint256 paymentWithoutFee, uint256 fee) = _getCollateralAmountAndFee(paymentAmount);
        uint256 tokenAmount = _getBuyTokenAmount(tokenAddress, paymentWithoutFee);
        collateralById[_competitionId][tokenAddress] += paymentWithoutFee;
        feeAccumulated += fee;
        token.mint(receiver, tokenAmount);
        emit TokenBuy(tokenAddress, paymentWithoutFee, tokenAmount, fee, block.timestamp);
        return tokenAmount;
    }

    function _getCollateralAmountAndFee(uint256 paymentAmount) internal view returns (uint256 paymentWithoutFee, uint256 fee) {
        fee = calculateFee(paymentAmount, feePercent);
        paymentWithoutFee = paymentAmount - fee;
    }

    function _getBuyTokenAmount(address tokenAddress, uint256 paymentWithoutFee) internal view returns (uint256) {
        Token token = Token(tokenAddress);
        uint256 _competitionId = competitionIds[tokenAddress];
        return bondingCurve.computeMintingAmountFromPrice(collateralById[_competitionId][tokenAddress], token.totalSupply(), paymentWithoutFee);
    }

    function _buyReceivedAmount(address tokenAddress, uint256 paymentAmount) public view returns (uint256 tokenAmount) {
        (uint256 paymentWithoutFee, ) = _getCollateralAmountAndFee(paymentAmount);
        return _getBuyTokenAmount(tokenAddress, paymentWithoutFee);
    }

    function _sellReceivedAmount(address tokenAddress, uint256 amount) public view returns (uint256, uint256) {
        Token token = Token(tokenAddress);
        require(amount <= token.totalSupply(), "amount exceeds supply");
        uint256 _competitionId = competitionIds[tokenAddress];
        uint256 paymentAmountWithFee = bondingCurve.computeRefundForBurning(collateralById[_competitionId][tokenAddress], token.totalSupply(), amount);
        uint256 fee = calculateFee(paymentAmountWithFee, feePercent);
        return (paymentAmountWithFee - fee, fee);
    }

    function sell(address tokenAddress, uint256 amount) external nonReentrant inCompetition(tokenAddress) {
        _sell(tokenAddress, amount, msg.sender, msg.sender);
    }

    function _sell(address tokenAddress, uint256 tokenAmount, address from, address to) internal returns (uint256, uint256) {
        uint256 _competitionId = competitionIds[tokenAddress];
        require(_competitionId > 0, "Token not found");
        require(tokenAmount > 0, "Amount should be greater than zero");
        Token token = Token(tokenAddress);
        uint256 paymentAmountWithFee = bondingCurve.computeRefundForBurning(collateralById[_competitionId][tokenAddress], token.totalSupply(), tokenAmount);
        collateralById[_competitionId][tokenAddress] -= paymentAmountWithFee;

        uint256 fee = calculateFee(paymentAmountWithFee, feePercent);
        uint256 paymentAmountWithoutFee = paymentAmountWithFee - fee;
        feeAccumulated += fee;
        token.burn(from, tokenAmount);
        if (to != address(this)) {
            //slither-disable-next-line arbitrary-send-eth
            (bool success, ) = to.call{value: paymentAmountWithoutFee}(new bytes(0));
            require(success, "ETH send failed");
        }
        emit TokenSell(tokenAddress, tokenAmount, paymentAmountWithoutFee, fee, block.timestamp);
        return (paymentAmountWithoutFee, fee);
    }

    function calculateFee(uint256 _amount, uint256 _feePercent) internal pure returns (uint256) {
        return (_amount * _feePercent) / FEE_DENOMINATOR;
    }

    function getWinnerByCompetitionId(uint256 competitionId) public view returns (address) {
        uint256 maxCollateral = 0;
        address winnerAddress;

        for (uint256 i = 0; i < tokensByCompetitionId[competitionId].length; i++) {
            address tokenAddress = tokensByCompetitionId[competitionId][i];
            uint256 _collateral = collateralById[competitionId][tokenAddress];
            if (_collateral > maxCollateral) {
                maxCollateral = _collateral;
                winnerAddress = tokenAddress;
            }
        }

        return winnerAddress;
    }

    function getCollateralByCompetitionId(uint256 competitionId) public view returns (uint256) {
        uint256 collateralWithoutFee = 0;
        address winnerTokenAddress = getWinnerByCompetitionId(competitionId);
        for (uint256 i = 0; i < tokensByCompetitionId[competitionId].length; i++) {
            address tokenAddress = tokensByCompetitionId[competitionId][i];
            if (winnerTokenAddress == tokenAddress) {
                collateralWithoutFee += collateralById[competitionId][tokenAddress];
            } else {
                (uint256 paymentWithoutFee, ) = _getCollateralAmountAndFee(collateralById[competitionId][tokenAddress]);
                collateralWithoutFee += paymentWithoutFee;
            }
        }
        return collateralWithoutFee;
    }

    function setWinnerByCompetitionId(uint256 competitionId) external {
        require(competitionId != currentCompetitionId, "The competition is still active");

        address winnerAddress = getWinnerByCompetitionId(competitionId);

        if (winners[competitionId] != winnerAddress) {
            winners[competitionId] = winnerAddress;
            emit SetWinner(winnerAddress, competitionId, block.timestamp);
        }
    }

    function publishToUniswap(address tokenAddress) external nonReentrant {
        uint256 currentCollateral;
        uint256 mintAmount;
        {
            uint256 _competitionId = competitionIds[tokenAddress];
            require(_competitionId != currentCompetitionId, "The competition is still active");
            address winnerToken = getWinnerByCompetitionId(_competitionId);
            require(winnerToken == tokenAddress, "Token address not winner");
            currentCollateral = collateralById[_competitionId][tokenAddress];
        }
        {
            uint256 numTokensPerEther = bondingCurve.computeMintingAmountFromPrice(currentCollateral, Token(tokenAddress).totalSupply(), 1 ether);
            WETH.deposit{value: currentCollateral}();
            mintAmount = (currentCollateral * numTokensPerEther) / 1e18;
            Token(tokenAddress).mint(address(this), mintAmount);
        }
        (address pool, uint256 tokenId, uint128 liquidity, uint256 actualTokenAmount, uint256 actualAssetAmount) = _mintLiquidity(
            tokenAddress,
            mintAmount,
            currentCollateral,
            address(this)
        );

        tokensPools[tokenAddress] = pool;
        liquidityPositionTokenIds[tokenAddress] = tokenId;
        emit WinnerLiquidityAdded(
            tokenAddress,
            tokensCreators[tokenAddress],
            pool,
            msg.sender,
            tokenId,
            liquidity,
            actualTokenAmount,
            actualAssetAmount,
            block.timestamp
        );
    }

    function burnTokenAndMintWinner(address tokenAddress) external nonReentrant {
        uint256 _competitionId = competitionIds[tokenAddress];
        require(_competitionId != currentCompetitionId, "The competition is still active");
        address winnerToken = getWinnerByCompetitionId(_competitionId);
        require(winnerToken != tokenAddress, "Token address is winner");
        require(liquidityPositionTokenIds[winnerToken] != 0, "Winner is not yet published");
        Token token = Token(tokenAddress);
        uint256 burnedAmount = token.balanceOf(msg.sender);
        uint256 feePrior = feeAccumulated;
        (uint256 netUserCollateral, uint256 fee) = _sell(tokenAddress, burnedAmount, msg.sender, address(this));
        _increaseObservationCardinality(winnerToken);
        uint256 mintAmount = getMintAmountPostPublish(netUserCollateral, winnerToken);
        Token(winnerToken).mint(msg.sender, mintAmount);
        Token(winnerToken).mint(address(this), mintAmount);
        WETH.deposit{value: netUserCollateral}();
        _increaseLiquidity(
            liquidityPositionTokenIds[winnerToken],
            tokenAddress < address(WETH) ? mintAmount : netUserCollateral,
            tokenAddress < address(WETH) ? netUserCollateral : mintAmount
        );
        emit TokenMinted(tokenAddress, netUserCollateral, mintAmount, block.timestamp);
        feeAccumulated += fee;
        emit BurnTokenAndMintWinner(msg.sender, tokenAddress, winnerToken, burnedAmount, mintAmount, fee, block.timestamp);
    }

    function withdrawFee() external onlyOwner {
        uint256 feeWithdrawable = feeAccumulated - feeWithdrawn > address(this).balance ? address(this).balance : feeAccumulated - feeWithdrawn;
        (bool success, ) = owner().call{value: feeWithdrawable}("");
        require(success, "transfer failed");
        feeWithdrawn += feeWithdrawable;
    }
}
