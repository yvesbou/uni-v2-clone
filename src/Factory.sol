// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

import {ERC20} from "@openzeppelin-contracts-5.0.2/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin-contracts-5.0.2/access/Ownable.sol";
import {Pair} from "./Pair.sol";

contract Factory is Ownable {
    mapping(address => mapping(address => address pair)) public pairRegistry;
    address[] public allPairs;

    event PairCreated(address indexed pair, address indexed token0, address indexed token1);

    error PairAlreadyExists();
    error SameAddressNotAllowed();
    error ZeroAddressNotAllowed();

    constructor() Ownable(msg.sender) {}

    function deployPair(address tokenA, address tokenB) external {
        if (tokenA == tokenB) revert SameAddressNotAllowed();

        // only one pool per token pair
        (address token0, address token1) = tokenA > tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        if (token0 == address(0)) revert ZeroAddressNotAllowed();
        if (pairRegistry[token0][token1] != address(0)) revert PairAlreadyExists();

        Pair newPool = new Pair(address(this), token0, token1);

        pairRegistry[token0][token1] = address(newPool);
        pairRegistry[token1][token0] = address(newPool);

        allPairs.push(address(newPool));

        emit PairCreated(address(newPool), token0, token1);
    }

    function collectFees() public onlyOwner {
        uint256 length = allPairs.length; // savings
        for (uint256 index = 0; index < length;) {
            address pool = allPairs[index]; // savings
            Pair(pool).redeemLiquidity(Pair(pool).balanceOf(address(this)), address(this));
            unchecked {
                index++; // savings
            }
        }
    }
}
