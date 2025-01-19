# Mutations

The following mutations I handled

## TWAP

I wrote a test that checks that the TWAP returns the desired price

```
Mutation:
    File: /rareskills_week_03/uni-v2-clone/src/TWAPConsumer.sol
    Line nr: 62
    Result: Lived

    Original line:
        uint256 twap0 = weightedPrices0 \* 1e18 / timeDelta;

    Mutated line:
        uint256 twap0 = weightedPrices0 / 1e18 / timeDelta;
```

## Re-entrancy

I added a testcase that checks for re-entrancy.

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
