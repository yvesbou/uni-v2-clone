// SPDX-License-Identifier: MIT

import {ERC20} from "@openzeppelin-contracts-5.0.2/token/ERC20/ERC20.sol";
import {Pair} from "./Pair.sol"

contract Factory {
    mapping(address => mapping(address => address pair)) pairRegistry;
    address[] public allPairs;

    event PairCreated(address indexed pair, address indexed token0, address indexed token1);

    error PairAlreadyExists();
    error SameAddressNotAllowed();
    error ZeroAddressNotAllowed();

    constructor() {}

    function deployPair(address tokenA, address tokenB) external {
        if (tokenA == tokenB) revert SameAddressNotAllowed();
        
        // only one pool per token pair
        (address token0, address token1) = tokenA > tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        if (token0 == address(0)) revert PairAlreadyExists();
        if (pairRegistry[token0][token1] != address0) revert PairAlreadyExists();

        string memory pairName = ERC20(tokenA).name() + "_" + ERC20(tokenB).name();
        string memory pairSymbol = ERC20(tokenA).symbol() + "_" + ERC20(tokenB).symbol();

        Pair newPool = new Pair(pairName, pairSymbol, tokenA, tokenB);
        
        pairRegistry[token0][token1] = address(newPool);
        pairRegistry[token1][token0] = address(newPool);
        
        allPairs.push(address(newPool));

        emit PairCreated(address(newPool), token0, token1)
    }
}
