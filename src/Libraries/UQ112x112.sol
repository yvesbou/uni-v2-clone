// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

library UQ112x112 {
    uint224 constant Q112_BASIS = 112;
    uint224 constant UQ112_MAX = type(uint224).max;

    error ERROR_EXCEED_MAX();

    function toUQ112x112(uint256 y) internal pure returns (uint224) {
        if (y > UQ112_MAX) revert ERROR_EXCEED_MAX();
        return uint224(y) << Q112_BASIS;
    }

    /// @notice divide a UQ112x112 by a uint112 returning a UQ112x112
    /// @param x an unsigned 112.112 bit number
    /// @param y an unsigned 112bit number
    function uqdiv(uint224 x, uint112 y) internal pure returns (uint224 z) {
        z = x / uint224(y);
    }
}
