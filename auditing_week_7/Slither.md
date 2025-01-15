# First Iteration

`slither . --print human-summary`

| Name              | # funct | ERCs           | ERC20 info                    | Complex | Features                     |
| ----------------- | ------- | -------------- | ----------------------------- | ------- | ---------------------------- |
| IERC721Errors     | 0       |                |                               | No      |                              |
| IERC1155Errors    | 0       |                |                               | No      |                              |
| FixedPointMathLib | 72      |                |                               | Yes     | Assembly                     |
| SafeTransferLib   | 22      |                |                               | No      | Assembly                     |
| Factory           | 13      |                |                               | No      | Tokens interaction           |
| FlashBorrower     | 7       |                |                               | No      | Tokens interaction           |
| IFactory          | 2       |                |                               | No      |                              |
| IPair             | 6       |                |                               | No      |                              |
| Math              | 1       |                |                               | No      |                              |
| Pair              | 57      | ERC20, ERC2612 | No Minting Approve Race Cond. | Yes     | Tokens interaction, Assembly |
| TWAPConsumer      | 5       |                |                               | No      | Tokens interaction           |
| Token             | 37      | ERC20          | ∞ Minting Approve Race Cond.  | No      |                              |

# Triage Mode

`sliter . --triage-mode`

---

### arbitrary from in transferfrom

```
0: Pair.flashLoan(IERC3156FlashBorrower,address,uint256,bytes) (src/Pair.sol#278-302) uses arbitrary from in transferFrom: SafeTransferLib.safeTransferFrom(token,address(receiver),address(this),amount + fee) (src/Pair.sol#299)
Reference: https://github.com/crytic/slither/wiki/Detector-Documentation#arbitrary-from-in-transferfrom
```

-> I choose to ignore, because it's intended, the same address that takes the flashloan has also to return it.

---

### weak PRNG

```
INFO:Detectors:
0: Pair._update(uint256,uint256) (src/Pair.sol#347-371) uses a weak PRNG: "blockTimestamp = uint32(block.timestamp % 2 ** 32) (src/Pair.sol#348)"
Reference: https://github.com/crytic/slither/wiki/Detector-Documentation#weak-PRNG
```

-> I couldnt find an explanation why the modulo 32 is necessary in casting the block.timestamp, but it's not intended for randomness, so I ignore.

---

### unchecked transfer

```
INFO:Detectors:
0: Pair.provideLiquidity(uint256,uint256,address) (src/Pair.sol#165-226) ignores return value by asset0.transferFrom(msg.sender,address(this),asset0_) (src/Pair.sol#224)
1: Pair.provideLiquidity(uint256,uint256,address) (src/Pair.sol#165-226) ignores return value by asset1.transferFrom(msg.sender,address(this),asset1_) (src/Pair.sol#225)
2: Pair._swap(address,address,uint256,uint256,uint256,uint256) (src/Pair.sol#373-411) ignores return value by asset1.transferFrom(msg.sender,address(this),amountIn) (src/Pair.sol#403)
3: Pair._swap(address,address,uint256,uint256,uint256,uint256) (src/Pair.sol#373-411) ignores return value by asset0.transferFrom(msg.sender,address(this),amountIn) (src/Pair.sol#407)
Reference: https://github.com/crytic/slither/wiki/Detector-Documentation#unchecked-transfer
```

-> The transfers would revert if the msg.sender (LP or trader) did not have enough funds to make the transaction.

---

### divide before multiply

```
34: TWAPConsumer.getPrice() (src/TWAPConsumer.sol#33-94) performs a multiplication on the result of a division:
	- twap0 = weightedPrices0 * 1e18 / timeDelta (src/TWAPConsumer.sol#63)
	- twap0 * 100 > lastTWAP0_ * 110 && twap0 * 100 < lastTWAP0_ * 90 (src/TWAPConsumer.sol#81)
35: TWAPConsumer.getPrice() (src/TWAPConsumer.sol#33-94) performs a multiplication on the result of a division:
	- twap1 = weightedPrices1 * 1e18 / timeDelta (src/TWAPConsumer.sol#64)
	- twap1 * 100 > lastTWAP1_ * 110 && twap1 * 100 < lastTWAP1_ * 90 (src/TWAPConsumer.sol#82)
Reference: https://github.com/crytic/slither/wiki/Detector-Documentation#divide-before-multiply
```

Here is the respective code

```Solidity
    // twap
    uint256 twap0 = weightedPrices0 * 1e18 / timeDelta;
    uint256 twap1 = weightedPrices1 * 1e18 / timeDelta;

    // not initialised yet
    // thus not checking for too big price differences
    if (lastTWAP0_ == 0 && lastTWAP1_ == 0) {
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
```

I have a branch (if) because if the TWAP was never computed before, I cannot check for too big differences, and this is why I chose this implementation.

---

### dangerous strict equalities

```
0: TWAPConsumer.getPrice() (src/TWAPConsumer.sol#33-94) uses a dangerous strict equality:
	- lastSnapshot_ == 0 (src/TWAPConsumer.sol#45)
1: TWAPConsumer.getPrice() (src/TWAPConsumer.sol#33-94) uses a dangerous strict equality:
	- lastTWAP0_ == 0 && lastTWAP1_ == 0 (src/TWAPConsumer.sol#68)
Reference: https://github.com/crytic/slither/wiki/Detector-Documentation#dangerous-strict-equalities
```

-> not so sure if this can really be a vulnerability

---

### unused return

```
INFO:Detectors:
0: FlashBorrower.onFlashLoan(address,address,uint256,uint256,bytes) (src/FlashloanBorrower.sol#22-40) ignores return value by IERC20(token).approve(address(lender),amount + fee) (src/FlashloanBorrower.sol#37)
Reference: https://github.com/crytic/slither/wiki/Detector-Documentation#unused-return
```

-> If approve fails, the flashloan would not execute (since the whole logic is atomic this is not a problem).

```
0: Pair.constructor(address,address,address).factory_ (src/Pair.sol#95) lacks a zero-check on :
		- factory = factory_ (src/Pair.sol#96)
Reference: https://github.com/crytic/slither/wiki/Detector-Documentation#missing-zero-address-validation
```

-> Fixed

---

### calls inside a loop

```
0: Factory.collectFees() (src/Factory.sol#39-48) has external calls inside a loop: Pair(pool).redeemLiquidity(Pair(pool).balanceOf(address(this)),address(this)) (src/Factory.sol#43)
Reference: https://github.com/crytic/slither/wiki/Detector-Documentation/#calls-inside-a-loop
```

"Calls inside a loop might lead to a denial-of-service attack."
-> No it's permissioned.

---

### Dangerous usage of block.timestamp. block.timestamp can be manipulated by miners

```
0: Pair.swapOut(address,address,uint256,uint256,uint256) (src/Pair.sol#109-128) uses timestamp for comparisons
	Dangerous comparisons:
	- block.timestamp > deadline (src/Pair.sol#115)
1: Pair.swapIn(address,address,uint256,uint256,uint256) (src/Pair.sol#135-158) uses timestamp for comparisons
	Dangerous comparisons:
	- block.timestamp > deadline (src/Pair.sol#145)
2: Pair._update(uint256,uint256) (src/Pair.sol#347-371) uses timestamp for comparisons
	Dangerous comparisons:
	- timeElapsed > 0 && reserve0_ != 0 && reserve1_ != 0 (src/Pair.sol#358)
3: TWAPConsumer.getPrice() (src/TWAPConsumer.sol#33-94) uses timestamp for comparisons
	Dangerous comparisons:
	- lastSnapshot_ == 0 (src/TWAPConsumer.sol#45)
	- timeDelta < 3600 (src/TWAPConsumer.sol#50)
	- lastTWAP0_ == 0 && lastTWAP1_ == 0 (src/TWAPConsumer.sol#68)
	- twap0 * 100 > lastTWAP0_ * 110 && twap0 * 100 < lastTWAP0_ * 90 (src/TWAPConsumer.sol#81)
	- twap1 * 100 > lastTWAP1_ * 110 && twap1 * 100 < lastTWAP1_ * 90 (src/TWAPConsumer.sol#82)
4: TWAPConsumer.checkIfOracleStale() (src/TWAPConsumer.sol#96-100) uses timestamp for comparisons
	Dangerous comparisons:
	- timestampNow - latestTimestamp > 3600 (src/TWAPConsumer.sol#99)
Reference: https://github.com/crytic/slither/wiki/Detector-Documentation#block-timestamp
```

0. `block.timestamp > deadline (src/Pair.sol#116)` -> required
1. `block.timestamp > deadline (src/Pair.sol#146)` -> required
2. `timeElapsed > 0 && reserve0_ != 0 && reserve1_ != 0 (src/Pair.sol#358)` -> required
3. `TWAPConsumer.getPrice()` -> required
4. `TWAPConsumer.checkIfOracleStale()` -> required

---

### Void constructor

```
0: Void constructor called in Pair.constructor(address,address,address) (src/Pair.sol#95-103):
	- ERC20() (src/Pair.sol#95)
Reference: https://github.com/crytic/slither/wiki/Detector-Documentation#void-constructor
```

-> fixed, I assumed it is necessary

---

### unused state variable

```
0: Pair.LP_TOKEN_PRECISION (src/Pair.sol#39) is never used in Pair (src/Pair.sol#35-435)
Reference: https://github.com/crytic/slither/wiki/Detector-Documentation#unused-state-variable
```

-> fixed

---

### state variables that could be declared immutable

```
INFO:Detectors:
0: FlashBorrower.lender (src/FlashloanBorrower.sol#11) should be immutable
1: Pair.asset0 (src/Pair.sol#50) should be immutable
2: Pair.asset1 (src/Pair.sol#51) should be immutable
3: Pair.factory (src/Pair.sol#53) should be immutable
4: Pair.precisionAsset0 (src/Pair.sol#61) should be immutable
5: Pair.precisionAsset1 (src/Pair.sol#62) should be immutable
6: TWAPConsumer.pair (src/TWAPConsumer.sol#8) should be immutable
Reference: https://github.com/crytic/slither/wiki/Detector-Documentation#state-variables-that-could-be-declared-immutable
```

-> fixed
