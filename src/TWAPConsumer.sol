// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

import {Pair} from "./Pair.sol";

contract TWAPConsumer {
    Pair public pair;
    uint256 public lastSnapshot; // timestamp (t_x), t_4-t_2 = T_4+T_3
    uint256 public lastCumulativePrice0;
    uint256 public lastCumulativePrice1;
    uint256 public lastTWAP0;
    uint256 public lastTWAP1;

    uint256 public constant MAX_PERCENTAGE_CHANGE = 10;

    error ErrorOracleStale();
    error ErrorTooBigPriceDifference();
    error NotActiveStillInitialising();

    constructor(address pair_) {
        pair = Pair(pair_);
    }

    function takeSnapshot() public {
        // set latest
        lastCumulativePrice0 = pair.price0CumulativeLast();
        lastCumulativePrice1 = pair.price1CumulativeLast();
        lastSnapshot = pair.blockTimestampLast();
    }

    function getPrice() public returns (uint256, uint256, uint256) {
        // check if stale, if the price on the AMM pool has not updated since 1 hour
        uint256 latestTimestamp = pair.blockTimestampLast();
        uint256 timestampNow = block.timestamp;
        if (timestampNow - latestTimestamp > 1 hours) revert ErrorOracleStale();

        // get latest
        uint256 latestCumulativePrice0 = pair.price0CumulativeLast();
        uint256 latestCumulativePrice1 = pair.price1CumulativeLast();

        // savings
        uint256 lastTWAP0_ = lastTWAP0;
        uint256 lastTWAP1_ = lastTWAP1;

        // do calculation
        uint256 timeDelta = latestTimestamp - lastSnapshot;
        if (timeDelta < 1 hours && lastTWAP0_ == 0 && lastTWAP1_ == 0) {
            revert NotActiveStillInitialising();
        }
        if (timeDelta < 1 hours) {
            // protect against too short TWAPs
            return (lastTWAP0_, lastTWAP1_, lastSnapshot);
        }

        uint256 weightedPrices0;
        uint256 weightedPrices1;
        unchecked {
            weightedPrices0 = latestCumulativePrice0 - lastCumulativePrice0;
            weightedPrices1 = latestCumulativePrice1 - lastCumulativePrice1;
        }

        // twap
        uint256 twap0 = weightedPrices0 * 1e18 / timeDelta;
        uint256 twap1 = weightedPrices1 * 1e18 / timeDelta;

        if (lastTWAP0_ == 0 && lastTWAP1_ == 0) {
            // not initialised yet
            lastTWAP0 = twap0;
            lastTWAP1 = twap1;

            // set latest
            lastCumulativePrice0 = latestCumulativePrice0;
            lastCumulativePrice1 = latestCumulativePrice1;
            lastSnapshot = timestampNow;

            // return
            return (twap0, twap1, timestampNow);
        }

        if (twap0 * 100 > lastTWAP0_ * 110 && twap0 * 100 < lastTWAP0_ * 90) revert ErrorTooBigPriceDifference();
        if (twap1 * 100 > lastTWAP1_ * 110 && twap1 * 100 < lastTWAP1_ * 90) revert ErrorTooBigPriceDifference();

        lastTWAP0 = twap0;
        lastTWAP1 = twap1;

        // set latest
        lastCumulativePrice0 = latestCumulativePrice0;
        lastCumulativePrice1 = latestCumulativePrice1;
        lastSnapshot = timestampNow;

        // return
        return (twap0, twap1, timestampNow);
    }
}
