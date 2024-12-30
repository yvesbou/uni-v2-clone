// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console} from "forge-std-1.9.2/src/Test.sol";

import {ERC20} from "@openzeppelin-contracts-5.0.2/token/ERC20/ERC20.sol";
import {Token} from "../src/Token.sol";
import {Factory} from "../src/Factory.sol";
import {Pair} from "../src/Pair.sol";
import {FixedPointMathLib} from "@solady-0.0.287/utils/FixedPointMathLib.sol";

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

        uint256 receivedLPTokens = FixedPointMathLib.sqrt(1000e18 * 200e18) - 1000;
        assertEq(receivedLPTokens, totalLPTokens - 1000);
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
        uint256 receivedLPTokens = FixedPointMathLib.sqrt(1000e18 * 200e18) - 1000;
        assertEq(receivedLPTokens, totalLPTokens - 1000);

        // second LP deposits
        vm.startPrank(lp2);
        TOKEN_A.approve(pair, MAX);
        TOKEN_B.approve(pair, MAX);

        Pair(pair).provideLiquidity(1000e18, 200e18, lp2);

        vm.stopPrank();

        totalLPTokens = Pair(pair).totalSupply();

        uint256 balanceLP1 = Pair(pair).balanceOf(lp);
        uint256 balanceLP2 = Pair(pair).balanceOf(lp2);
        assertEq(balanceLP1 + 1000, balanceLP2); // first user donated 1000LP tokens
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
        uint256 receivedLPTokens = FixedPointMathLib.sqrt(1000e18 * 200e18) - 1000;
        assertEq(receivedLPTokens, totalLPTokens - 1000);

        // second LP deposits
        vm.startPrank(lp2);
        TOKEN_A.approve(pair, MAX);
        TOKEN_B.approve(pair, MAX);

        Pair(pair).provideLiquidity(500e18, 100e18, lp2);
        uint256 receivedLPTokensLP2 = FixedPointMathLib.sqrt(500e18 * 100e18);

        vm.stopPrank();

        totalLPTokens = Pair(pair).totalSupply();

        assertEq(receivedLPTokensLP2 + receivedLPTokens, totalLPTokens - 1000);
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
        uint256 receivedLPTokens = FixedPointMathLib.sqrt(1000e18 * 200e18) - 1000;

        // second LP deposits
        vm.startPrank(lp2);
        TOKEN_A.approve(pair, MAX);
        TOKEN_B.approve(pair, MAX);

        Pair(pair).provideLiquidity(500e18, 100e18, lp2);

        vm.stopPrank();

        // first LP re-claims all tokens again
        vm.startPrank(lp);
        Pair(pair).approve(pair, MAX);
        Pair(pair).redeemLiquidity(receivedLPTokens, lp);
        vm.stopPrank();

        totalLPTokens = Pair(pair).totalSupply();

        uint256 receivedLPTokensLP2 = FixedPointMathLib.sqrt(500e18 * 100e18);

        assertEq(receivedLPTokensLP2 + 1000, totalLPTokens); // lp2 + 1000 deadshares
        uint256 balanceLP1 = Pair(pair).balanceOf(lp);
        uint256 balanceLP2 = Pair(pair).balanceOf(lp2);
        assertEq(balanceLP1, 0);
        assertEq(balanceLP2, receivedLPTokensLP2);

        uint256 balanceToken0 = TOKEN_B.balanceOf(lp);
        uint256 balanceToken1 = TOKEN_A.balanceOf(lp);
        assertLt(balanceToken0, 1000e18); // bc of deadshares not everything is received
        assertLt(balanceToken1, 200e18);
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

        // second LP deposits
        vm.startPrank(lp2);
        TOKEN_A.approve(pair, MAX);
        TOKEN_B.approve(pair, MAX);

        Pair(pair).provideLiquidity(1000e18, 200e18, lp2);

        vm.stopPrank();

        vm.startPrank(trader);
        TOKEN_A.approve(pair, MAX);
        // see readme chapter ## Amount Out

        // price before trade: 5

        Pair(pair).swap(trader, address(TOKEN_B), 100e18, 396e18); // expected out is 1% less than current price -> fee
        vm.stopPrank();

        // price after trade:
        uint256 reserve0 = Pair(pair).reserve0();
        uint256 reserve1 = Pair(pair).reserve1();
        uint256 price = (reserve0 * 1e18) / reserve1;
        console.log(price);
        assertLt(price, 5e18);

        assertGt(TOKEN_B.balanceOf(trader), 396e18);
    }

    // TODO
    /**
     * swap different rate
     * swap and redeem
     */
}
