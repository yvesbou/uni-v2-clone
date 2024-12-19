// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console} from "forge-std-1.9.2/src/Test.sol";

import {IPair, IFactory} from "../src/Interfaces.sol";
import {ERC20} from "@openzeppelin-contracts-5.0.2/token/ERC20/ERC20.sol";
import {Token} from "../src/Token.sol";
import {Factory} from "../src/Factory.sol";

contract UniTest is Test {
    uint256 mainnetFork; // access to real deployed tokens
    uint256 MAX = type(uint256).max;

    address owner = address(1);
    address lp = address(16);
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

    function test_supply() public {
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

        IPair(pair).provideLiquidity(1000e18, 200e18, lp); // this fails
    }
}
