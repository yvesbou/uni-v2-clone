// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

import {Test, console} from "forge-std-1.9.2/src/Test.sol";

import {FixedPointMathLib} from "@solady-0.0.287/utils/FixedPointMathLib.sol";

import {Token} from "../src/Token.sol";
import {Factory} from "../src/Factory.sol";
import {Pair} from "../src/Pair.sol";

contract ProtocolFeeTest is Test {
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

        factory.deployPair(address(TOKEN_A), address(TOKEN_B));
        pair = factory.pairRegistry(address(TOKEN_A), address(TOKEN_B));
        assertTrue(address(pair) != address(0), "Address should not be zero");

        ///////////////////////
        ///////////////////////
        //// FEE IS SET ON ////
        ///////////////////////
        ///////////////////////
        factory.setFee(address(TOKEN_A), address(TOKEN_B), true);

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

        // second LP deposits
        vm.startPrank(lp2);
        TOKEN_A.approve(pair, MAX);
        TOKEN_B.approve(pair, MAX);

        Pair(pair).provideLiquidity(1000e18, 200e18, lp2);

        vm.stopPrank();
    }

    function test_protocolFee() public {
        // compute kLast (l1)
        (uint112 reserve0, uint112 reserve1,) = Pair(pair).getReserves();
        uint256 kLast = FixedPointMathLib.sqrt(uint256(reserve0) * reserve1);

        vm.startPrank(trader);
        TOKEN_A.approve(pair, MAX);

        // price before trade: 5

        Pair(pair).swapIn(trader, address(TOKEN_B), 100e18, 396e18, block.timestamp); // expected out is 1% less than current price -> fee
        vm.stopPrank();

        // compute updated k (l2)
        (reserve0, reserve1,) = Pair(pair).getReserves();
        uint256 kUpdated = FixedPointMathLib.sqrt(uint256(reserve0) * reserve1);

        uint256 s = Pair(pair).totalSupply();

        // compute eta
        uint256 eta = s * (kUpdated - kLast) / (kLast + 5 * kUpdated); // if 1/6 is fees is protocol fee

        // someone needs to supply or withdraw
        vm.startPrank(lp);
        uint256 lpTokensToReturn = Pair(pair).balanceOf(lp);

        Pair(pair).redeemLiquidity(lpTokensToReturn, lp); // through this fees are accounted

        vm.stopPrank();

        uint256 lpTokensForFee = Pair(pair).balanceOf(address(factory));

        // eta + 1 because we round in favor of the protocol
        assertEq(eta + 1, lpTokensForFee);
    }
}
