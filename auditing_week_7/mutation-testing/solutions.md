# Mutations

The following mutations I handled

## TWAP

I wrote a test that checks that the TWAP returns the desired price and both mutations would lead to a false price.

```
Mutation:
    File: /rareskills_week_03/uni-v2-clone/src/TWAPConsumer.sol
    Line nr: 62
    Result: Lived

    Original line:
        uint256 twap0 = weightedPrices0 * 1e18 / timeDelta;

    Mutated line:
        uint256 twap0 = weightedPrices0 / 1e18 / timeDelta;
```

```
Mutation:
    File: /Users/yvesboutellier/Coding/rareskills/rareskills_week_03/uni-v2-clone/src/TWAPConsumer.sol
    Line nr: 47
    Result: Lived
    Original line:
                 uint256 timeDelta = latestTimestamp - lastSnapshot_;

    Mutated line:
                 uint256 timeDelta = latestTimestamp + lastSnapshot_;
```

## Re-entrancy

I added a testcase that checks for re-entrancy and expects a revert, mutation would lead to a failed test (since re-entering would not cause revert).

```
Mutation:
    File: /Users/yvesboutellier/Coding/rareskills/rareskills_week_03/uni-v2-clone/src/Pair.sol
    Line nr: 279
    Result: Lived
    Original line:
                 nonReentrant

    Mutated line:
```

## Mutation within a revert statement

I see this as a helpful anecdote to make sure that the computation is as intended.

```
Mutation:
    File: /rareskills_week_03/uni-v2-clone/src/Pair.sol
    Line nr: 393
    Result: Lived

    Original line:
        revert ViolationConstantK(reserve0_ * reserve1_, newReserve0 * newReserve1);

    Mutated line:
        revert ViolationConstantK(reserve0_ * reserve1_, newReserve0 / newReserve1);
```

## Missing Trade in other direction

I fixed this by introducing a test with a swap in the other direction that wrong reserves in both directions are caught by a unit test.

```
Mutation:
    File: /Users/yvesboutellier/Coding/rareskills/rareskills_week_03/uni-v2-clone/src/Pair.sol
    Line nr: 390
    Result: Lived
    Original line:
                 uint256 newReserve1 = buyingAsset == address(asset1) ? reserve1_ - amountOut : reserve1_ + amountIn;

    Mutated line:
                 uint256 newReserve1 = buyingAsset == address(asset1) ? reserve1_ + amountOut : reserve1_ + amountIn;
```

## Un-initialised Pool

I introduced a test, where `sync()` was called on an empty pool (not initialised by first deposit). This mutation would lead to a `panic` since vision by 0 is not allowed.

```
Mutation:
    File: /Users/yvesboutellier/Coding/rareskills/rareskills_week_03/uni-v2-clone/src/Pair.sol
    Line nr: 357
    Result: Lived
    Original line:
                 if (timeElapsed > 0 && reserve0_ != 0 && reserve1_ != 0)

    Mutated line:
                 if (timeElapsed > 0 && reserve0_ != 0 && reserve1_ == 0)
```

# False Positives

```
Mutation:
    File: /Users/yvesboutellier/Coding/rareskills/rareskills_week_03/uni-v2-clone/src/Pair.sol
    Line nr: 15
    Result: Lived
    Original line:
                 return a < b ? a : b;

    Mutated line:
                 return a <= b ? a : b;
```
