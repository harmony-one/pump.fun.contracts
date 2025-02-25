// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "@contracts/TokenFactoryBase.sol";
import "@contracts/BancorBondingCurve.sol";
import "@contracts/Token.sol";

contract TokenFactoryTest is Test {
    TokenFactoryBase tokenFactory;
    BancorBondingCurve bondingCurve;
    Token token;
    address user = address(0x1);
    address owner = address(this);

    uint256 internal FEE_PERCENT = vm.envUint("FEE_PERCENT");
    uint256 internal SLOPE_SCALED = vm.envUint("SLOPE_SCALED");
    uint32 internal WEIGHT_SCALED = uint32(vm.envUint("WEIGHT_SCALED"));
    address internal UNISWAP_V3_FACTORY = vm.envAddress("UNISWAP_V3_FACTORY");
    address internal UNISWAP_V3_NPM = vm.envAddress("UNISWAP_V3_NPM");
    address internal WETH = vm.envAddress("WETH");
    
    function setUp() public {
        bondingCurve = new BancorBondingCurve(SLOPE_SCALE * 2.0, MAX_WEIGHT / (1 + 1));
        Token tref = new Token();

        tokenFactory = new TokenFactoryBase();
        
        tokenFactory.initialize(
            address(tref), 
            UNISWAP_V3_FACTORY, 
            UNISWAP_V3_NPM, 
            address(bondingCurve), 
            WETH, 
            FEE_PERCENT,
            1 ether
        );
    }
    
    function testCreateToken() public {
        vm.startPrank(user);
        Token newToken = tokenFactory.createToken("TestToken", "TTK", "testuri");
        vm.stopPrank();
        assertEq(tokenFactory.tokensCreators(address(newToken)), user);
    }
    
    function testBuyToken() public {
        Token newToken = tokenFactory.createToken("TestToken", "TTK", "testuri");
        
        vm.deal(user, 1 ether);
        vm.startPrank(user);
        tokenFactory.buy{value: 1 ether}(address(newToken));
        vm.stopPrank();
        
        assertGt(newToken.balanceOf(user), 0);
        assertGt(tokenFactory.collateralById(address(newToken)), 0);
    }
    
    function testSellToken() public {
        Token newToken = tokenFactory.createToken("TestToken", "TTK", "testuri");
        
        vm.deal(user, 1 ether);
        vm.startPrank(user);
        tokenFactory.buy{value: 1 ether}(address(newToken));
        uint256 balanceBefore = user.balance;
        uint256 tokenAmount = newToken.balanceOf(user);
        
        newToken.approve(address(tokenFactory), tokenAmount);
        tokenFactory.sell(address(newToken), tokenAmount);
        vm.stopPrank();
        
        assertGt(user.balance, balanceBefore);
    }
    
    function testWithdrawFee() public {
        Token newToken = tokenFactory.createToken("TestToken", "TTK", "testuri");
        
        vm.deal(user, 1 ether);
        vm.startPrank(user);
        tokenFactory.buy{value: 1 ether}(address(newToken));
        vm.stopPrank();
        
        uint256 feeBefore = address(user).balance;

        assertGt(newToken.balanceOf(address(user)), 0);
        assertGt(address(tokenFactory).balance, 0);

        vm.startPrank(owner);
        tokenFactory.withdrawFee(user);
        vm.stopPrank();
        
        assertGt(address(user).balance, feeBefore);
    }
}
