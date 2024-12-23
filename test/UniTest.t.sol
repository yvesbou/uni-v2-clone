// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console} from "forge-std-1.9.2/src/Test.sol";

import {ERC20} from "@openzeppelin-contracts-5.0.2/token/ERC20/ERC20.sol";
import {Token} from "../src/Token.sol";
import {Factory} from "../src/Factory.sol";
import {Pair} from "../src/Pair.sol";

contract UniTest is Test {
    uint256 mainnetFork; // access to real deployed tokens
    uint256 MAX = type(uint256).max;

    address owner = address(1);
    address lp = address(16);
    address lp2 = address(17);
    address trader = address(8);

    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");

    Factory public factory;
    Token public TOKEN_A; // make fork test and use real tokens
    Token public TOKEN_B;

    function setUp() public {
        // setup fork
        mainnetFork = vm.createSelectFork(MAINNET_RPC_URL);
        vm.rollFork(21_435_306);

        // create tokens
        vm.startPrank(owner);
        TOKEN_A = new Token("A-Token", "AT");
        console.log(address(TOKEN_A));
        TOKEN_B = new Token("B-Token", "BT");
        console.log(address(TOKEN_B));
        // give one token to the user

        // setup my uni-v2 clone
        factory = new Factory();
        vm.stopPrank();
    }

    function test_deploy_pair() public {
        factory.deployPair(address(TOKEN_A), address(TOKEN_B));
        address pair = factory.pairRegistry(address(TOKEN_A), address(TOKEN_B));
        assertTrue(address(pair) != address(0), "Address should not be zero");
    }

    function test_simple_supply() public {
        factory.deployPair(address(TOKEN_A), address(TOKEN_B));
        address pair = factory.pairRegistry(address(TOKEN_A), address(TOKEN_B));

        vm.startPrank(owner);
        // let's assume token A is 5x more valuable at the start, 5B -> 1A
        TOKEN_A.mint(lp, 200e18);
        TOKEN_B.mint(lp, 1000e18);
        TOKEN_B.mint(trader, 100e18);
        vm.stopPrank();

        vm.startPrank(lp);
        TOKEN_A.approve(pair, MAX);
        TOKEN_B.approve(pair, MAX);

        Pair(pair).provideLiquidity(1000e18, 200e18, lp);

        uint256 totalLPTokens = Pair(pair).totalSupply();
        assertEq(totalLPTokens, 1200e18);
    }

    function test_two_supply_same_amount() public {
        factory.deployPair(address(TOKEN_A), address(TOKEN_B));
        address pair = factory.pairRegistry(address(TOKEN_A), address(TOKEN_B));

        vm.startPrank(owner);
        // let's assume token A is 5x more valuable at the start, 5B -> 1A

        // LPs get their tokens
        TOKEN_A.mint(lp, 200e18);
        TOKEN_B.mint(lp, 1000e18);
        TOKEN_A.mint(lp2, 200e18);
        TOKEN_B.mint(lp2, 1000e18);

        vm.stopPrank();

        // first LP deposits
        vm.startPrank(lp);
        TOKEN_A.approve(pair, MAX);
        TOKEN_B.approve(pair, MAX);

        Pair(pair).provideLiquidity(1000e18, 200e18, lp);

        vm.stopPrank();

        uint256 totalLPTokens = Pair(pair).totalSupply();
        assertEq(totalLPTokens, 1200e18);

        // second LP deposits
        vm.startPrank(lp2);
        TOKEN_A.approve(pair, MAX);
        TOKEN_B.approve(pair, MAX);

        Pair(pair).provideLiquidity(1000e18, 200e18, lp2);

        vm.stopPrank();

        totalLPTokens = Pair(pair).totalSupply();
        // double amount of LP tokens
        assertEq(totalLPTokens, 2400e18);
        uint256 balanceLP1 = Pair(pair).balanceOf(lp);
        uint256 balanceLP2 = Pair(pair).balanceOf(lp2);
        assertEq(balanceLP1, balanceLP2);
    }

    // first LP deposits 2x of second LP
    function test_two_supply_different_amount() public {
        factory.deployPair(address(TOKEN_A), address(TOKEN_B));
        address pair = factory.pairRegistry(address(TOKEN_A), address(TOKEN_B));

        vm.startPrank(owner);
        // let's assume token A is 5x more valuable at the start, 5B -> 1A

        // LPs get their tokens
        TOKEN_A.mint(lp, 200e18);
        TOKEN_B.mint(lp, 1000e18);
        TOKEN_A.mint(lp2, 200e18);
        TOKEN_B.mint(lp2, 1000e18);

        vm.stopPrank();

        // first LP deposits
        vm.startPrank(lp);
        TOKEN_A.approve(pair, MAX);
        TOKEN_B.approve(pair, MAX);

        Pair(pair).provideLiquidity(1000e18, 200e18, lp);

        vm.stopPrank();

        uint256 totalLPTokens = Pair(pair).totalSupply();
        assertEq(totalLPTokens, 1200e18);

        // second LP deposits
        vm.startPrank(lp2);
        TOKEN_A.approve(pair, MAX);
        TOKEN_B.approve(pair, MAX);

        Pair(pair).provideLiquidity(500e18, 100e18, lp2);

        vm.stopPrank();

        totalLPTokens = Pair(pair).totalSupply();
        // double amount of LP tokens
        assertEq(totalLPTokens, 1800e18); // 1200 + 600
        uint256 balanceLP1 = Pair(pair).balanceOf(lp);
        uint256 balanceLP2 = Pair(pair).balanceOf(lp2);
        assertEq(balanceLP1, 1200e18);
        assertEq(balanceLP2, 600e18);
    }

    function test_lp_redeems_before_1st_swap() public {
        factory.deployPair(address(TOKEN_A), address(TOKEN_B));
        address pair = factory.pairRegistry(address(TOKEN_A), address(TOKEN_B));

        vm.startPrank(owner);
        // let's assume token A is 5x more valuable at the start, 5B -> 1A

        // LPs get their tokens
        TOKEN_A.mint(lp, 200e18);
        TOKEN_B.mint(lp, 1000e18);
        TOKEN_A.mint(lp2, 200e18);
        TOKEN_B.mint(lp2, 1000e18);

        vm.stopPrank();

        // first LP deposits
        vm.startPrank(lp);
        TOKEN_A.approve(pair, MAX);
        TOKEN_B.approve(pair, MAX);

        Pair(pair).provideLiquidity(1000e18, 200e18, lp);

        vm.stopPrank();

        uint256 totalLPTokens = Pair(pair).totalSupply();
        assertEq(totalLPTokens, 1200e18);

        // second LP deposits
        vm.startPrank(lp2);
        TOKEN_A.approve(pair, MAX);
        TOKEN_B.approve(pair, MAX);

        Pair(pair).provideLiquidity(500e18, 100e18, lp2);

        vm.stopPrank();

        // first LP re-claims all tokens again
        vm.startPrank(lp);
        Pair(pair).approve(pair, MAX);
        Pair(pair).redeemLiquidity(1200e18, lp);
        vm.stopPrank();

        totalLPTokens = Pair(pair).totalSupply();
        // double amount of LP tokens
        assertEq(totalLPTokens, 600e18); // 0 + 600
        uint256 balanceLP1 = Pair(pair).balanceOf(lp);
        uint256 balanceLP2 = Pair(pair).balanceOf(lp2);
        assertEq(balanceLP1, 0);
        assertEq(balanceLP2, 600e18);

        uint256 balanceToken0 = TOKEN_B.balanceOf(lp);
        uint256 balanceToken1 = TOKEN_A.balanceOf(lp);
        assertEq(balanceToken0, 1000e18);
        assertEq(balanceToken1, 200e18);
    }

    function test_simple_swap() public {
        factory.deployPair(address(TOKEN_A), address(TOKEN_B));
        address pair = factory.pairRegistry(address(TOKEN_A), address(TOKEN_B));

        vm.startPrank(owner);
        // let's assume token A is 5x more valuable at the start, 5B -> 1A

        // LPs get their tokens
        TOKEN_A.mint(lp, 200e18);
        TOKEN_B.mint(lp, 1000e18);
        TOKEN_A.mint(lp2, 200e18);
        TOKEN_B.mint(lp2, 1000e18);

        TOKEN_A.mint(trader, 200e18);

        vm.stopPrank();

        // first LP deposits
        vm.startPrank(lp);
        TOKEN_A.approve(pair, MAX);
        TOKEN_B.approve(pair, MAX);

        Pair(pair).provideLiquidity(1000e18, 200e18, lp);

        vm.stopPrank();

        uint256 totalLPTokens = Pair(pair).totalSupply();
        assertEq(totalLPTokens, 1200e18);

        // second LP deposits
        vm.startPrank(lp2);
        TOKEN_A.approve(pair, MAX);
        TOKEN_B.approve(pair, MAX);

        Pair(pair).provideLiquidity(1000e18, 200e18, lp2);

        vm.stopPrank();

        vm.startPrank(trader);
        TOKEN_A.approve(pair, MAX);
        // dy = 131.56 = ( k / (x-dx) ) - y
        Pair(pair).swap(trader, address(TOKEN_B), 132e18, 490e18); // expected out is 1% less than current price -> fee
        vm.stopPrank();
    }

    // TODO
    /**
     * swap
     * swap different rate
     * swap and redeem
     */
}
