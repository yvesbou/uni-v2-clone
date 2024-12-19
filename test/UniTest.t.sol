// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console} from "forge-std-1.9.2/src/Test.sol";

import {IPair, IFactory} from "../src/Interfaces.sol";
import {ERC20} from "@openzeppelin-contracts-5.0.2/token/ERC20/ERC20.sol";
import {Token} from "../src/Token.sol";
import {Factory} from "../src/Factory.sol";

contract UniTest is Test {
    uint256 mainnetFork; // access to real deployed tokens

    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");

    Factory public factory;
    ERC20 public TOKEN_A; // make fork test and use real tokens
    ERC20 public TOKEN_B;

    function setUp() public {
        // setup fork
        mainnetFork = vm.createSelectFork(MAINNET_RPC_URL);
        vm.rollFork(21_435_306);

        // create tokens
        TOKEN_A = new Token("A-Token", "AT");
        TOKEN_B = new Token("B-Token", "BT");
        // give one token to the user

        // setup my uni-v2 clone
        factory = new Factory();
    }

    function test_deploy_pair() public {
        factory.deployPair(address(TOKEN_A), address(TOKEN_B));
        address pair = factory.pairRegistry(address(TOKEN_A), address(TOKEN_B));
        assertTrue(address(pair) != address(0), "Address should not be zero");
    }
}
