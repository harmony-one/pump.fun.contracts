// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "@contracts/TokenFactoryBase.sol";
import "@contracts/BancorBondingCurve.sol";
import "@contracts/Token.sol";
import "openzeppelin/contracts/proxy/Clones.sol";

contract TokenFactoryTest is Test {
    TokenFactoryBase tokenFactory;
    BancorBondingCurve bondingCurve;
    Token token;
    address user = address(0x1);
    address owner = address(this);
    
    function setUp() public {
        bondingCurve = new BancorBondingCurve();
        tokenFactory = new TokenFactoryBase();
        tokenFactory.initialize(address(new Token()), address(bondingCurve), 500); // 5% fee
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
        
        uint256 feeBefore = address(owner).balance;
        vm.startPrank(owner);
        tokenFactory.withdrawFee();
        vm.stopPrank();
        
        assertGt(owner.balance, feeBefore);
    }
}
