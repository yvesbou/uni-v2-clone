// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

import {Test, console} from "forge-std-1.9.2/src/Test.sol";

import {Token} from "../src/Token.sol";
import {Factory} from "../src/Factory.sol";
import {Pair} from "../src/Pair.sol";
import {TWAPConsumer} from "../src/TWAPConsumer.sol";

contract TWAPTest is Test {
    uint256 MAX = type(uint256).max;

    address owner = address(1);
    address lp = address(16);
    address lp2 = address(17);
    address trader = address(8);

    address pair;

    uint256 startTime;
    uint256 startBlock;

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

        factory.deployPair(address(TOKEN_A), address(TOKEN_B));
        pair = factory.pairRegistry(address(TOKEN_A), address(TOKEN_B));
        assertTrue(address(pair) != address(0), "Address should not be zero");

        startTime = 1735889903;
        startBlock = 21542601;
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
        vm.stopPrank();
    }

    function testTWAP() public {
        // the inital price remained for 1 hour
        vm.warp(startTime + 1 hours);
        vm.roll(startBlock + 300);

        TWAPConsumer consumer = new TWAPConsumer(pair);

        /* note:
            last cumulative prices would be still 0,
            bc Pair._update not been triggered with >0 time elapsed
            even though time has passed
        */

        // trade
        vm.startPrank(trader);
        TOKEN_A.approve(pair, MAX);

        /* note:
            last cumulative prices have been updated, timeElapsed = 1h
            price of supply ratio was valid for 1h
        */
        Pair(pair).swapIn(trader, address(TOKEN_B), 10e18, 48e18, block.timestamp);

        // snapshot price
        consumer.takeSnapshot();
        ////////////////////////////////
        uint256 lastCumulativePrice0 = Pair(pair).price0CumulativeLast();
        uint256 lastCumulativePrice1 = Pair(pair).price1CumulativeLast();
        console.log("lastCumulativePrice0");
        console.log(lastCumulativePrice0);
        console.log("lastCumulativePrice1");
        console.log(lastCumulativePrice1);
        ////////////////////////////////

        // the new price after first swap remained for 1 hour
        vm.warp(startTime + 2 hours);
        vm.roll(startBlock + 600);
        console.log("----------------------");
        console.log("t+2");
        Pair(pair).sync(); // cumulative price increased, as timedelta >0

        ////////////////////////////////
        uint256 latestCumulativePrice0 = Pair(pair).price0CumulativeLast();
        uint256 latestCumulativePrice1 = Pair(pair).price1CumulativeLast();
        console.log("latestCumulativePrice0");
        console.log(latestCumulativePrice0);
        console.log("latestCumulativePrice1");
        console.log(latestCumulativePrice1);
        ////////////////////////////////

        // get price after 1h initial price, and 1h after swap price (50/50)

        (uint256 price0, uint256 price1,) = consumer.getPrice();

        uint256 desiredPrice0 = (latestCumulativePrice0 - lastCumulativePrice0) * 1e18 / 1 hours;
        uint256 desiredPrice1 = (latestCumulativePrice1 - lastCumulativePrice1) * 1e18 / 1 hours;

        assertEq(price0, desiredPrice0);
        assertEq(price1, desiredPrice1);
        console.log("price0 is: ");
        console.log(price0);
        console.log("price1 is: ");
        console.log(price1);
    }

    function testTWAPStale() public {
        // the inital price remained for 1 hour
        vm.warp(startTime + 1 hours);
        vm.roll(startBlock + 300);

        TWAPConsumer consumer = new TWAPConsumer(pair);
        // snapshot price
        consumer.takeSnapshot();

        uint256 lastCumulativePrice0 = consumer.lastCumulativePrice0();
        uint256 lastCumulativePrice1 = consumer.lastCumulativePrice1();
        console.log("----------------------");
        console.log("t+1");
        console.log("lastCumulativePrice0");
        console.log(lastCumulativePrice0);
        console.log("lastCumulativePrice1");
        console.log(lastCumulativePrice1);

        // trade
        vm.startPrank(trader);
        TOKEN_A.approve(pair, MAX);

        Pair(pair).swapIn(trader, address(TOKEN_B), 10e18, 48e18, block.timestamp);

        ////////// temp ///////////////
        lastCumulativePrice0 = Pair(pair).price0CumulativeLast();
        lastCumulativePrice1 = Pair(pair).price1CumulativeLast();
        console.log("lastCumulativePrice0");
        console.log(lastCumulativePrice0);
        console.log("lastCumulativePrice1");
        console.log(lastCumulativePrice1);
        ////////////////////////////////

        // note: reserves are true (checked)

        // the new price after swap remained for 1 hour
        vm.warp(startTime + 2 hours);
        vm.roll(startBlock + 600);
        console.log("----------------------");
        console.log("t+2");
        Pair(pair).sync(); // cumulative price increased, as timedelta >0

        ////////// temp ///////////////
        lastCumulativePrice0 = Pair(pair).price0CumulativeLast();
        lastCumulativePrice1 = Pair(pair).price1CumulativeLast();
        console.log("lastCumulativePrice0");
        console.log(lastCumulativePrice0);
        console.log("lastCumulativePrice1");
        console.log(lastCumulativePrice1);
        ////////////////////////////////

        // get price after 1h initial price, and 1h after swap price (50/50)
        vm.warp(startTime + 3 hours + 1 minutes);
        vm.expectRevert(); // more than 1 hour the price did not change
        (uint256 price0, uint256 price1,) = consumer.getPrice();
    }

    function testTWAPTooMuchPriceDeviation() public {
        // the inital price remained for 1 hour
        vm.warp(startTime + 1 hours);
        vm.roll(startBlock + 300);

        TWAPConsumer consumer = new TWAPConsumer(pair);
        // snapshot price
        consumer.takeSnapshot();

        uint256 lastCumulativePrice0 = consumer.lastCumulativePrice0();
        uint256 lastCumulativePrice1 = consumer.lastCumulativePrice1();
        console.log("----------------------");
        console.log("t+1");
        console.log("lastCumulativePrice0");
        console.log(lastCumulativePrice0);
        console.log("lastCumulativePrice1");
        console.log(lastCumulativePrice1);

        // trade
        vm.startPrank(trader);
        TOKEN_A.approve(pair, MAX);

        Pair(pair).swapIn(trader, address(TOKEN_B), 10e18, 48e18, block.timestamp);

        ////////// temp ///////////////
        lastCumulativePrice0 = Pair(pair).price0CumulativeLast();
        lastCumulativePrice1 = Pair(pair).price1CumulativeLast();
        console.log("lastCumulativePrice0");
        console.log(lastCumulativePrice0);
        console.log("lastCumulativePrice1");
        console.log(lastCumulativePrice1);
        ////////////////////////////////

        // note: reserves are true (checked)

        // the new price after swap remained for 1 hour
        vm.warp(startTime + 2 hours);
        vm.roll(startBlock + 600);
        console.log("----------------------");
        console.log("t+2");
        Pair(pair).sync(); // cumulative price increased, as timedelta >0

        ////////// temp ///////////////
        lastCumulativePrice0 = Pair(pair).price0CumulativeLast();
        lastCumulativePrice1 = Pair(pair).price1CumulativeLast();
        console.log("lastCumulativePrice0");
        console.log(lastCumulativePrice0);
        console.log("lastCumulativePrice1");
        console.log(lastCumulativePrice1);
        ////////////////////////////////

        // get price after 1h initial price, and 1h after swap price (50/50)
        (uint256 price0, uint256 price1,) = consumer.getPrice();
        console.log("price0 is: ");
        console.log(price0);
        console.log("price1 is: ");
        console.log(price1);

        vm.warp(startTime + 3 hours);
        vm.roll(startBlock + 900);
        Pair(pair).swapIn(trader, address(TOKEN_B), 50e18, 176e18, block.timestamp);

        (price0, price1,) = consumer.getPrice();
        console.log("price0 is: ");
        console.log(price0);
        console.log("price1 is: ");
        console.log(price1);
    }
}
