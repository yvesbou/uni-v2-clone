// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

import {Test, console} from "forge-std-1.9.2/src/Test.sol";

import {Token} from "../src/Token.sol";
import {Factory} from "../src/Factory.sol";
import {Pair} from "../src/Pair.sol";
import {FlashBorrower} from "../src/FlashloanBorrower.sol";

contract PoolCreationTest is Test {
    uint256 MAX = type(uint256).max;

    address owner = address(1);
    address lp = address(16);
    address lp2 = address(17);
    address trader = address(8);

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
    }

    function test_deploy_pair() public {
        factory.deployPair(address(TOKEN_A), address(TOKEN_B));
        address pair = factory.pairRegistry(address(TOKEN_A), address(TOKEN_B));
        assertTrue(address(pair) != address(0), "Address should not be zero");
    }

    function test_flashloan() public {
        factory.deployPair(address(TOKEN_A), address(TOKEN_B));
        address pair = factory.pairRegistry(address(TOKEN_A), address(TOKEN_B));

        uint256 startTime = 1735889903;
        uint256 startBlock = 21542601;
        vm.warp(startTime);
        vm.roll(startBlock);

        // fill pool w/ liquidity
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

        // second LP deposits
        vm.startPrank(lp2);
        TOKEN_A.approve(pair, MAX);
        TOKEN_B.approve(pair, MAX);

        Pair(pair).provideLiquidity(1000e18, 200e18, lp2);

        vm.stopPrank();

        vm.startPrank(trader);
        // create borrower
        FlashBorrower flashBorrower = new FlashBorrower(pair);
        // starting balance for borrower contract to pay flashloan fee
        TOKEN_A.transfer(address(flashBorrower), 10e17);
        assertEq(flashBorrower.trustedInitiators(trader), true);
        // execute flashloan
        bytes memory data = "";
        Pair(pair).flashLoan(flashBorrower, address(TOKEN_A), 10e18, data);
    }
}
