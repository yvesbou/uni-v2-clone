// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

import {Test, console} from "forge-std-1.9.2/src/Test.sol";

import {Token} from "../src/Token.sol";
import {Factory} from "../src/Factory.sol";
import {Pair} from "../src/Pair.sol";

contract SwapTest is Test {
    uint256 MAX = type(uint256).max;

    address owner = address(1);
    address lp = address(16);
    address lp2 = address(17);
    address trader = address(8);

    address pair;

    Factory public factory;
    Token public TOKEN_A;
    Token public TOKEN_B;

    function setUp() public {
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

        factory.deployPair(address(TOKEN_A), address(TOKEN_B));
        pair = factory.pairRegistry(address(TOKEN_A), address(TOKEN_B));
        assertTrue(address(pair) != address(0), "Address should not be zero");

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

        // second LP deposits
        vm.startPrank(lp2);
        TOKEN_A.approve(pair, MAX);
        TOKEN_B.approve(pair, MAX);

        Pair(pair).provideLiquidity(1000e18, 200e18, lp2);

        vm.stopPrank();
    }

    function test_simple_swap_in_tokenB() public {
        vm.prank(owner);
        TOKEN_A.mint(trader, 200e18);
        vm.startPrank(trader);
        TOKEN_A.approve(pair, MAX);

        uint256 reserve0Before = Pair(pair).reserve0();
        uint256 reserve1Before = Pair(pair).reserve1();

        // price before trade: 5

        // see readme chapter ## Amount Out
        Pair(pair).swapIn(trader, address(TOKEN_B), 100e18, 396e18, block.timestamp); // expected out is 1% less than current price -> fee
        vm.stopPrank();

        // price after trade:
        uint256 reserve0 = Pair(pair).reserve0();
        uint256 reserve1 = Pair(pair).reserve1();
        uint256 price = (reserve0 * 1e18) / reserve1;
        console.log(price);
        assertLt(price, 5e18);
        assertLt(reserve0, reserve0Before); // token B was bought from the pool
        assertGt(reserve1, reserve1Before); // token A was given in the pool to receive token B
        assertGt(TOKEN_B.balanceOf(trader), 396e18);
    }

    function test_simple_swap_in_tokenA() public {
        vm.prank(owner);
        TOKEN_B.mint(trader, 200e18);
        vm.startPrank(trader);
        TOKEN_B.approve(pair, MAX);

        uint256 reserve0Before = Pair(pair).reserve0();
        uint256 reserve1Before = Pair(pair).reserve1();

        // price before trade: 5

        // see readme chapter ## Amount Out
        Pair(pair).swapIn(trader, address(TOKEN_A), 100e18, 18e18, block.timestamp); // expected out is 1% less than current price -> fee
        vm.stopPrank();

        // price after trade:
        uint256 reserve0 = Pair(pair).reserve0();
        uint256 reserve1 = Pair(pair).reserve1();
        uint256 price = (reserve0 * 1e18) / reserve1;
        console.log(price);
        assertGt(price, 5e18);
        assertLt(reserve0Before, reserve0); // token B was given in the pool to receive token A
        assertGt(reserve1Before, reserve1); // token A was bought from the pool

        assertGt(TOKEN_A.balanceOf(trader), 18e18);
    }

    function test_simple_swap_out() public {
        vm.prank(owner);
        TOKEN_A.mint(trader, 200e18);
        vm.startPrank(trader);
        TOKEN_A.approve(pair, MAX);
        // see readme chapter ## Amount Out

        // price before trade: 5

        Pair(pair).swapOut(trader, address(TOKEN_B), 102e18, 400e18, block.timestamp); // expected out is 1% less than current price -> fee
        vm.stopPrank();

        // price after trade:
        uint256 reserve0 = Pair(pair).reserve0();
        uint256 reserve1 = Pair(pair).reserve1();
        uint256 price = (reserve0 * 1e18) / reserve1;
        console.log(price);
        assertLt(price, 5e18);

        assertEq(TOKEN_B.balanceOf(trader), 400e18);
    }
}
