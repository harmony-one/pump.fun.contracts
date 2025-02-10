// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {BancorBondingCurve} from "./BancorBondingCurve.sol";
import {Token} from "./Token.sol";

contract TokenFactoryBase is Initializable, OwnableUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable {
    uint256 public VERSION;
    uint256 public constant FEE_DENOMINATOR = 10000;

    address public tokenImplementation;
    BancorBondingCurve public bondingCurve;
    uint256 public feePercent; // bp
    uint256 public feeAccumulated;
    uint256 public feeWithdrawn;

    mapping(uint256 => address) public winners;
    mapping(address => uint256) public collateralById;

    mapping(address => address) public tokensCreators;
    mapping(address => address) public tokensPools;
    mapping(address => uint256) public liquidityPositionTokenIds;

    // Events
    event TokenCreated(address indexed token, string name, string symbol, string uri, address creator, uint256 timestamp);
    event TokenBuy(address indexed token, uint256 amount0In, uint256 amount0Out, uint256 fee, uint256 timestamp);
    event TokenMinted(address indexed token, uint256 assetAmount, uint256 tokenAmount, uint256 timestamp);
    event TokenSell(address indexed token, uint256 amount0In, uint256 amount0Out, uint256 fee, uint256 timestamp);

    function initialize(
        address _tokenImplementation,
        address _bondingCurve,
        uint256 _feePercent
    ) public initializer {
        __Ownable_init();
        __ReentrancyGuard_init();

        tokenImplementation = _tokenImplementation;
        VERSION = 20241221;
        bondingCurve = BancorBondingCurve(_bondingCurve);
        feePercent = _feePercent;
    }

    /// @dev Required by UUPSUpgradeable to authorize upgrades
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    // Admin functions

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

        tokensCreators[tokenAddress] = msg.sender;

        emit TokenCreated(tokenAddress, name, symbol, uri, msg.sender, block.timestamp);

        return token;
    }

    function buy(address tokenAddress) external payable nonReentrant {
        _buy(tokenAddress, msg.sender, msg.value);
    }

    function _buy(address tokenAddress, address receiver, uint256 paymentAmount) internal returns (uint256) {
        require(paymentAmount > 0, "ETH not enough");

        Token token = Token(tokenAddress);
        (uint256 paymentWithoutFee, uint256 fee) = _getCollateralAmountAndFee(paymentAmount);
        uint256 tokenAmount = _getBuyTokenAmount(tokenAddress, paymentWithoutFee);
        collateralById[tokenAddress] += paymentWithoutFee;
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
        return bondingCurve.computeMintingAmountFromPrice(collateralById[tokenAddress], token.totalSupply(), paymentWithoutFee);
    }

    function _buyReceivedAmount(address tokenAddress, uint256 paymentAmount) public view returns (uint256 tokenAmount) {
        (uint256 paymentWithoutFee,) = _getCollateralAmountAndFee(paymentAmount);
        return _getBuyTokenAmount(tokenAddress, paymentWithoutFee);
    }

    function _sellReceivedAmount(address tokenAddress, uint256 amount) public view returns (uint256) {
        Token token = Token(tokenAddress);
        require(amount <= token.totalSupply(), "amount exceeds supply");
        uint256 receivedETH = bondingCurve.computeRefundForBurning(collateralById[tokenAddress], token.totalSupply(), amount);
        uint256 fee = calculateFee(receivedETH, feePercent);
        receivedETH -= fee;
        return receivedETH;
    }

    function sell(address tokenAddress, uint256 amount) external nonReentrant {
        _sell(tokenAddress, amount, msg.sender, msg.sender);
    }

    function _sell(address tokenAddress, uint256 tokenAmount, address from, address to) internal returns (uint256) {
        require(tokenAmount > 0, "Amount should be greater than zero");
        Token token = Token(tokenAddress);
        uint256 paymentAmountWithFee = bondingCurve.computeRefundForBurning(collateralById[tokenAddress], token.totalSupply(), tokenAmount);
        collateralById[tokenAddress] -= paymentAmountWithFee;

        uint256 fee = calculateFee(paymentAmountWithFee, feePercent);
        uint256 paymentAmountWithoutFee = paymentAmountWithFee - fee;
        feeAccumulated += fee;
        token.burn(from, tokenAmount);
        if (to != address(this)) {
            //slither-disable-next-line arbitrary-send-eth
            (bool success,) = to.call{value: paymentAmountWithoutFee}(new bytes(0));
            require(success, "ETH send failed");
        }
        emit TokenSell(tokenAddress, tokenAmount, paymentAmountWithoutFee, fee, block.timestamp);
        return paymentAmountWithoutFee;
    }

    function calculateFee(uint256 _amount, uint256 _feePercent) internal pure returns (uint256) {
        return (_amount * _feePercent) / FEE_DENOMINATOR;
    }

    function withdrawFee() external onlyOwner {
        uint256 feeWithdrawable = feeAccumulated - feeWithdrawn > address(this).balance ? address(this).balance : feeAccumulated - feeWithdrawn;
        (bool success,) = owner().call{value: feeWithdrawable}("");
        require(success, "transfer failed");
        feeWithdrawn += feeWithdrawable;
    }
}
