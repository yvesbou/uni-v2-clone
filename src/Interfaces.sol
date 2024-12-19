// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

interface IFactory {
    function deployPair(address tokenA, address tokenB) external;
    function allPairs() external;
}

interface IPair {
    function asset0() external;
    function asset1() external;
    function swap(address receiver, address buyingAsset, uint256 amountIn, uint256 amountOutMin) external;
    function provideLiquidity(uint256 asset0_, uint256 asset1_, address receiver) external;
    function redeemLiquidity(uint256 amountLPToken, address receiverOfAssets) external;
    function getReserves() external;
}
