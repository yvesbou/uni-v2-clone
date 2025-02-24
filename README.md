# Uni V2 Clone (Educational Purpose)

# Price Impact of a Swap

Uniswap revolutionised trading by introducing the AMM (automated market maker) with the following equation:

$$
x \cdot y = k
$$

This equation allows to trade $x$ against $y$ and vice versa while including the dynamic of supply and demand. In each trade, $k$ is only allowed to increase (fees), but never decrease. ($k$ decreases in fact if LPs withdraw their position as they withdraw $x$ and $y$.)

If plotted one can see that the price impact is stronger the more the $x$ , $y$ pair is pushed out of balance.

This innovation allowed to spin up liquid markets for thousands of tokens with one requirement: attention.

# Swap

Swapping needs slippage protection because transactions are public to sophisticated actors which can extract value from the un-finalised transactions by buying before them and sell them with a worse price. This is why users can specify the exact amount in (which they pay) or the exact amount out (which they receive). In Uniswap V2 this computation is part of the Router, in this code repository it's part of the pool implementation itself.

## Amount In (`swapIn`)

In `function swapIn(...)` users specify the amount they want to spend and a minimal amount which they require to receive at least, otherwise their transaction should fail.

The formula for `amountOutMin` ($\Delta x$) based on `amountIn` ($\Delta y$) is given without fees

$$
Δx=\frac{x \cdot Δy}{y+Δy}
$$

When we add fees = $f/F$, e.g `1%` = $99/100$ the formula results in:

$$
Δx=\frac{x \cdot f \cdot Δy}{y \cdot F+Δy \cdot f}
$$

Let's look at an example from the test file `Swaps.t.sol` with test case `test_simple_swap_in_tokenB()` where the trader wants to trade 100 of `token A` for `token B`,
given that the reserves are 2000 for `token A` and 400 for `token B` and a fee for LPs of 1% (99/100):

$$
396.79 = \frac{99 \cdot 100 \cdot 2000}{400 \cdot 100 + 99 \cdot 100}
$$

### Derivation of the above formula

Let's assume $x$ gets taken out of the pool and $y$ gets deposited into it.

1. Start with the constant product formula after a swap:

$$
(x - \Delta x) \cdot (y + \Delta y) \ge x \cdot y
$$

2. Isolate $\Delta x$:

$$
(x - \Delta x) \ge \frac{x \cdot y}{(y + \Delta y)}
$$

$$
x - \frac{x \cdot y}{(y + \Delta y)} \ge \Delta x
$$

3. Merge both fractions on left hand side:

$$
\frac{ x \cdot (y + \Delta y) }{{(y + \Delta y)}} - \frac{x \cdot y} {(y + \Delta y)} \ge \Delta x
$$

$$
\frac{ x \cdot y + x \cdot \Delta y - x \cdot y}{{y + \Delta y}} \ge \Delta x
$$

4. $x \cdot y$ cancels out and we end up with the formula we wanted:

$$
\frac{ x \cdot \Delta y}{{y + \Delta y}} \ge \Delta x
$$

5. Let us introduce fees as $f/F$, where fees are only applied to the incoming tokens ($\Delta y$) as if less tokens have been transfered to swap.

$$
\frac{ x \cdot \Delta y \cdot \frac{f}{F}}{{y + \Delta y \cdot \frac{f}{F}}} \ge \Delta x
$$

$$
\frac{ x \cdot \Delta y \cdot f}{{F \cdot (y + \Delta y \cdot \frac{f}{F})}} \ge \Delta x
$$

6. Multiply by $F$, and we get our expression with fees

$$
\frac{ x \cdot \Delta y \cdot f}{{F \cdot y + \Delta y \cdot f}} \ge \Delta x
$$

## Amount Out (`swapOut`)

In `function swapOut(...)` users specify the fixed amount they want to receive `amountOut` and a maximal amount which they feel they want to spend `amountInMax`.

The mathematical expressions are very similar to the from above. For the derivation we start with the same equation, but we solve for $\Delta y$ as $\Delta x$ is given by `amountOut`:

$$
(x - \Delta x) \cdot (y + \Delta y) \ge x \cdot y
$$

With a few steps we get:

$$
Δy \ge \frac{y \cdot Δx}{x-Δx}
$$

And when we introduce fees (applied to $\Delta y$ (see step 5 in the derivation above)) we get:

$$
Δy \ge \frac{F}{f}\cdot\frac{y \cdot Δx}{x-Δx}
$$

---

# Supply Liquidity

## First deposit

The first deposit determines the starting ratio of the two assets but the total liquidity provided $\sqrt k = \sqrt {x \cdot y}$ needs to be bigger than 1000 wei, since 1000 wei are minted but assigned to the 0-address.

The remaining liquidity $\sqrt {x \cdot y}$ is minted 1:1 to the LP. So if the LP deposits `1000e18` `x` and `1000e18` `y` then the LP receives `1000e18-1000` LP tokens.

### Scenario Inflation Attack

Rules (without dead shares):

1st deposit: LP tokens to mint = $\sqrt k$

2nd deposit:

$$
\frac{x_{in}}{x} \gt \frac{y_{in}}{y} \:\: ? \:\:  \frac{y_{in}}{y} \cdot LP \:\: : \:\:   \frac{x_{in}}{x} \cdot LP
$$

Bob wants to deposit $1000 \: x$ and $1000 \: y$. Alice sees the transaction in the mempool and frontruns the first deposit with a $1 \: x$ and $1 \: y$ deposit, giving her 1 LP token. Then before the transaction of Bob she queues a second transaction which is a donation of $1000 \: x$ and $1000 \: y$ to match Bob's deposit.

When Bob gets to deposit the reserves have $1001 \: x$ and $1001 \: y$ with $1$ LP token.

$$
\frac{x_{in}}{x} = \frac{1000}{1001} \cdot 1 \:LP \:\: Token = 0
$$

Since standard devision is rounding down, Bob does not get any LP token while increasing the reserves.

Alice makes a profit of nearly 100%, using $1001$ and receiving $1000$ on top.

### Scenario Inflation Attack mitigated

The rule for the second deposit is the same, but the rule for the first deposit is sightly different.

1st deposit: LP tokens to mint for depositer= $\sqrt k-1000$, mint 1000 for 0-address.

So when Bob wants to deposit $1000 \: x$ and $1000 \: y$ and Alice wants to frontrun the transaction, the deposit needs to be at least $\sqrt k = 1000$. Let's assume Alice deposits $1001 \: x$ and $1001 \: y$. Receiving back 1 LP token, while address-0 has $1000$, ie. LP token supply is $1001$.

Then Bob deposits 1000 each

$$
\frac{x_{in}}{x} = \frac{1000}{1001} \cdot 1001 \:LP \:\: Token = 1000
$$

So while Alice donated as first depositer 1000 Tokens each, Bob receives full equal share of the deposit like the address-0.

She cannot steal Bob's deposit even if Alice also donates, let's say 1000:

$$
\frac{x_{in}}{x} = \frac{1000}{2001} \cdot 1001 \:LP \:\: Token = 500
$$

500 out of 1501 tokens gives Bob the right to reclaim 999 Tokens.

## Subsequent deposits

Subsequent deposits always need to match the current ratio of `x` and `y` tokens otherwise the under-supplied token is considered for computing the ratio, thus a smaller amount of LP tokens is emitted.

Let's say the pool has 80 `x` and 20 `y` (`1y` token costs `4x`). Total Liquidity is 40 ($\sqrt{1600}$). Let's there was just one deposit, thus 40 LP tokens.

If a subsequent LP gives in 40 `x` and 5 `y` (`1y` token costs `8x`), the resulting LP tokens for the subsequent minter is just $\frac {5}{20} \cdot 40 = 10$ - so the LP receives only 10 LP tokens, instead of e.g if we took the `x` token for taking the ratio, the subsequent LP would have received 20 LP tokens. This is to prevent dilution of already deposited LPs, since if the last was true, subsequent LPs could dump less valued tokens to receive more LP share.

# Withdraw Liquidity

Computation for determining the returning liquidity is

$$
x_{out} = x \cdot \frac {z_{return}}{z_{total}}
$$

where $z$ are the LP tokens, $z_{return}$ the user returning the LP tokens and $z_{total}$ the total supply of LP tokens.

Since Solidity is always rounding down, we can leave it at that since we rounding in favor of the pool (returning less to the redeeming user).

The formula for the other token $y$ is the exact same.

The LP tokens that are returned are burned, so the overall supply decreases.

# Protocol Fee

The protocol wants to earn some fee on the trades but transfering tokens each time for a small fee to a target contract is too gas expensive. Another idea would be to deduct fees sporadicly at $t_x$ and then at $t_{x+\Delta x}$ but with this idea it could be that some LPs don't pay any fees which is not fair.
Therefore the fee is calculated and deducted whenever an LP manages the position.

Requirements:

- the fee should be deducted when LPs manage their positions
- the fee should only be worth $\frac x y$ of the fees collected by the LPs, where $x < y$
- if liquidity grows without additional supply by new LPs from `l1` to `l2`, $\frac {y-x}{y}$ of the difference should be captured by the LPs and $\frac x y$ by the protocol
- if the liquidity only grows by new supply or decreases by withdraws, no protocol fee should be deducted
- the protocol fee should only be in form of dilution with new LP tokens for a protocol managed address to minimize transfers

By this we can state our invariant

$$
\frac {\eta}{s} = \frac {p}{d}
$$

where,

$\eta$, the LP tokens emitted for the protocol (dilution for fees)

$s$, totalSupply of LP tokens

$d$, $\frac {y-x} {y}$ of new liquidity (mined fees) + deposited liquidity

$p$, $\frac {x} {y}$ of new mined liquidity

---

Now that we have our variables and relationship between them, we should solve our invariant for $\eta$ (to get the amount of LP tokens for the protocol which we can put aside (mint) each time an LP manages a position).

We need to formulate how liquidity is exactly measured.

$$
x \cdot y = k
$$

we define liquidity as

$$
\sqrt k
$$

Since we want to measure the growth in liquidity due to fees, we have a older and a recent $\sqrt k$

For better readability we use $l_1$ as the previous liquidity and $l_2$ as the recent liquidity.

Thus $d$ becomes

$$
d = \frac {y-x} {y} \cdot (l_2-l_1) + l_1
$$

$p$ is simply

$$
p = \frac {x} {y} \cdot (l_2-l_1)
$$

when we solve for $\eta$ we get

$$
\eta = \frac {x \cdot (l_2-l_1)}{y \cdot (l_1 + \frac{y-x}{y} \cdot (l_2-l_1))} \cdot s
$$

In Solidity code

`PROTOCOL_FEE_NUMERATOR` = $x$

`PROTOCOL_FEE_DENOMINATOR` = $y$

`kLast_` = $l_1$

`rootK` = $l_2$

```solidity
    function takeProtocolFee(uint256 reserve0_, uint256 reserve1_, uint256 totalSupply_) internal {
        uint256 kLast_ = kLast; // savings
        if (feeSwitchOn && kLast_ != 0) {
            // compute rootk
            uint256 rootK = FixedPointMathLib.sqrt(reserve0_ * reserve1_);
            // compute amount LP Tokens
            if (rootK > kLast_) {
                uint256 nominator = totalSupply_ * PROTOCOL_FEE_NUMERATOR * (rootK - kLast_);
                uint256 denominator = PROTOCOL_FEE_DENOMINATOR
                    * (
                        kLast_
                            + (rootK - kLast_) * (PROTOCOL_FEE_DENOMINATOR - PROTOCOL_FEE_NUMERATOR) / PROTOCOL_FEE_DENOMINATOR
                    );
                // round in favor of the protocol
                uint256 lpTokensForProtocol =
                    nominator % denominator > 0 ? (nominator / denominator) + 1 : nominator / denominator;
                if (lpTokensForProtocol > 0) _mint(factory, lpTokensForProtocol);
            }
        } else {
            kLast = 0;
        }
    }
```

In case of Uniswap V2, their equation is much simpler as they use magic numbers. The protocol fee is set fix to $\frac 1 6$ for the total collected fees (but they never turned the fee switch on).

Their equation which can be looked for is (remember $\eta$ the new minted tokens for the protocol)

$$
\eta = \frac {l_2 - l_1}{l_1 + 5 \cdot l_2} \cdot s
$$

## Walkthrough Protocol Fee Logic

It might be counter-intuitive when looking at the code only shallowly that `if the liquidity only grows by new supply or decreases by withdraws, no protocol fee should be deducted` holds true. Let's go through 3 examples to show that it is actually this way.

| Scenario                | Fee [y/n] |
| ----------------------- | --------- |
| Supply-Supply           | No Fees   |
| Withdraw-Withdraw       | No Fees   |
| Withdraw-Trade-Withdraw | Fees      |
| Supply-Trade-Supply     | Fees      |
| Supply-Trade-Withdraw   | Fees      |
| Withdraw-Trade-Supply   | Fees      |

For all scenarios the starting point is $\sqrt k = 1000$, ie. $x=y=1000$

### Supply - Supply

First example is the scenario that two consecutive supplies happen without any trade in between. This should result in no fees deducted by the protocol.

`rootK` is always computed on the reserves before `supply` or `withdraw`.

`supply(1000,1000)`

0. reserves: $x=1000, y=1000$
1. `takeFee()`
2. `rootK` = $1000$
3. `rootK == k_last` -> no fees
4. `k_last` = $\sqrt{2000\cdot2000}=2000$

`supply(1000,1000)`

0. reserves: $x=2000, y=2000$
1. `takeFee()`
2. `rootK` = $2000$
3. `rootK == k_last` -> no fees
4. `k_last` = $\sqrt{2000\cdot2000}=2000$

### Withdraw - Withdraw

`withdraw(100,100)`

0. reserves: $x=1000, y=1000$
1. `takeFee()`
2. `rootK` = $1000$
3. `rootK == k_last` -> no fees
4. `k_last` = $\sqrt{900 \cdot 900}=900$

`withdraw(100,100)`

0. reserves: $x=900, y=900$
1. `takeFee()`
2. `rootK` = $900$
3. `rootK == k_last` -> no fees
4. `k_last` = $\sqrt{800 \cdot 800}=800$

### Withdraw - Trade - Withdraw

`withdraw(100,100)`

0. reserves: $x=1000, y=1000$
1. `takeFee()`
2. `rootK` = $1000$
3. `rootK == k_last` -> no fees
4. `k_last` = $\sqrt{900 \cdot 900}=900$

`swap(...)`, $200$ `in` and $100$ `out`

0. new reserves: $x=1100, y=800$ (paid very high fees, does not matter for this chain of reasoning)

`withdraw(100,100)`

0. reserves: $x=1100, y=800$
1. `takeFee()`
2. `rootK` = $\sqrt{1100 \cdot 800}=938$, `k_last` = $900$
3. `rootK != k_last` -> fees for the protocol!!!
4. `k_last` = $\sqrt{1100 \cdot 800}=938$

There is no need in showing the other scenarios as the logic shall be clear now.

# TWAP (Time-weighted-average-price)

Each Uniswap Pool as a competitive liquid market serves as an indicator what the true price of two assets is. Price is a ratio on how much `y` do I need to pay in order to get `x` and vice versa. In our pool we have this information. So we can serve oracle consumers with on-chain data.

The following variables from the Pool contract are used to compute the TWAP: `price0CumulativeLast`, `price1CumulativeLast` and `blockTimestampLast`.

Time weighted average price is usually computed as follows:

$$
TWAP = \frac{p_0 \cdot T_0 + p_1 \cdot T_1 + p_2 \cdot T_2 + ... + p_n \cdot T_n}{T_0 + T_1 + T_2 + ... + T_n}
$$

where $T_x$ is the _duration_ where price $p_x$ was recorded.

This makes intuitively sense, let's look at an example where we observe a price for 24h. In the first 12h the price was `$1` and in the second 12h the price was `$2`. Our intuition tells us that the TWAP is `$1.5`.

Let us check with the formula:

$$
TWAP = \frac{1 \cdot 12 + 2 \cdot 12}{24} = \frac{36}{24} = \frac {3}{2} = 1.5
$$

The TWAP consists of the numerator which is the `weightedPrice` and the denominator which is the sum of the whole duration for which the TWAP should be computed (a sum of price durations).

### Overflow in TWAP

Let's say our integer only goes until 16 (for simplicity to show integer math and negative modulos)

`blockTimelast = 14`

`block.timestamp = 18` => (casted) = `2`

the time difference should give `4`

so $2-14$ should be $4$

$-12 \mod 16 = 4$

How is $-12$ modulo 16 equal to 4?

The result of this operation says "less than or equal to -12 and divisible by 16, which is -16

difference between -12 and -16 is 4.

$$-12-(-16) = 4$$

> This is why our time variable or twap sum is allowed to overflow since we only do addition/substraction

### Code in Pool contract

When coding smart contracts optimisation is always a requirement.

Storing $p_0$ until $p_n$ is not feasible (looping through an array is insanely costly). Instead we should create a work-around, which requires that consumers snapshot the TWAP data we expose (later to that more).

To re-iterate our goal is that when a consumer contract (who needs an oracle price) asks our contract twice for the price, it can compute the TWAP (ie. `weightedSum` over `total duration`).

For our work-around we compute the nominator $weightedPrice_n = p_0 \cdot T_0 + p_1 \cdot T_1 + p_2 \cdot T_2 + ... + p_n \cdot T_n$ to the given time $t_n$ where we update the reserves (ie the ratio).

So in our code

```Solidity
price0CumulativeLast += newReserve1 * timeElapsed / newReserve0;
```

where `price0CumulativeLast` is $weightedPrice_{t_n}$. Note we always have two prices (also `price1CumulativeLast`), the price of `asset0` denominated in `asset1`, and the price of `asset1` which is denominated in `asset0` (they are ofc each inverses).

Let's say we want the TWAP for a time period between $t_2$ and $t_4$.

We snapshot at $t_2$ $weightedPrice_{t_2}$ ($p_0 \cdot T_0 + p_1 \cdot T_1 + p_2 \cdot T_2$) by storing the value from at $t_2$

```Solidity
price0CumulativeLast += newReserve1 * timeElapsed / newReserve0;
```

and later when it's $t_4$, we snapshot the $weightedPrice_{t_4}$ which is $p_0 \cdot T_0 + p_1 \cdot T_1 + p_2 \cdot T_2 + p_3 \cdot T_3 + p_4 \cdot T_4$

The difference of the two total weighted prices is $p_3 \cdot T_3 + p_4 \cdot T_4$, which is exactly what we wanted.

This means we can save on storage on the Pool contract, by only storing a cumulative price each time the reserves change.

For the denominator we need the total duration of this period $T_3+T_4$, but this is easy as our first snapshot at timestamp 2 is exactly the duration smaller than timestamp 4.

$p_x$ is timestamp at time `x`.

$$
p_0 \cdot T_0 + p_1 \cdot T_1 + p_2 \cdot T_2 + p_3 \cdot T_3 + p_4 \cdot T_4 - (p_0 \cdot T_0 + p_1 \cdot T_1 + p_2 \cdot T_2) = p_3 \cdot T_3 + p_4 \cdot T_4
$$

let's introduce the time difference as

$$
t_4-t_2 = T_4+T_3+T_2+T_1 - (T_2+T_1) = T_4+T_3
$$

Which gives us the full expression as,

$$
TWAP = \frac {p_3 \cdot T_3 + p_4 \cdot T_4}{T_4+T_3}
$$

Regarding this line:

```solidity
uint32 blockTimestamp = uint32(block.timestamp % 2**32);
```

check out this link: https://github.com/Uniswap/v2-core/issues/96

# Rounding in Favor of the protocol

Whenever the code calculates fees, or a price to be received by a user, the calculation should round up. Solidity rounds by default down.

```Solidity
// round in favor of the protocol
uint256 lpTokensForProtocol = nominator % denominator > 0 ? (nominator / denominator) + 1 : nominator / denominator;
```

# Theory on Uniswap V2 and Codeblocks

The question is as follows: Why is this line of code `uint balance0Adjusted = balance0.mul(1000).sub(amount0In.mul(3));` mathematically correct?

```Solidity
    {
    ...
    balance0 = IERC20(_token0).balanceOf(address(this));
    balance1 = IERC20(_token1).balanceOf(address(this));
    }
    uint amount0In = balance0 > _reserve0 - amount0Out ? balance0 - (_reserve0 - amount0Out) : 0;
    uint amount1In = balance1 > _reserve1 - amount1Out ? balance1 - (_reserve1 - amount1Out) : 0;
    require(amount0In > 0 || amount1In > 0, 'UniswapV2: INSUFFICIENT_INPUT_AMOUNT');
    { // scope for reserve{0,1}Adjusted, avoids stack too deep errors
    uint balance0Adjusted = balance0.mul(1000).sub(amount0In.mul(3));
    uint balance1Adjusted = balance1.mul(1000).sub(amount1In.mul(3));
    require(balance0Adjusted.mul(balance1Adjusted) >= uint(_reserve0).mul(_reserve1).mul(1000**2), 'UniswapV2: K');
    }
```

It translates in the idea "are the balances after in and out transfer enough high to account for 0.3% fee?"

Here is how,

Let's say we buy $x$ by spending $y$, thus `amount0In` $= 0$, and `amount1In` $\ne 0$

$$
(1000 \cdot (x - \Delta x)) (1000 \cdot (y + \Delta y) - 3 \cdot \Delta y) \ge k \cdot 1000^2
$$

which is equivalent to this statement

```
balance0Adjusted.mul(balance1Adjusted) >= uint(_reserve0).mul(_reserve1).mul(1000**2)
```

next, we reformulate

$$
1000^2 (x-\Delta x)(y + \Delta y - \frac 3 {1000} \cdot \Delta y) \ge k \cdot 1000^2
$$

and we come up with the following result:

$$
(x-\Delta x)(y + \Delta y - \frac 3 {1000} \cdot \Delta y) \ge k
$$

The y-expression (which is about the tokens that get transferred in) shows that 3 parts out of 1000 (0.3% or 99.7% of the total $\Delta y$) are substracted before evaluating if constant $k$ is respected with a certain trade. If the formula is solved for $\Delta x$ one can compute the x tokens that the trader gets out of the pool.

# Week 7 Assignment: Mutation Testing and Static Analysis

## Mutation

The first iteration yielded 55.2% killing rate (21/38). I ran the output with low sample ratio to get a first quick output `--sample-ratio 0.1 --output vertigo-output_001`.
As a consequence of the low killing rate (Smart Contracts should aim towards 100%) I improved the unit tests.

## Static Analysis

Results can be found in this file [auditing_week_7/Slither.md](./auditing_week_7/Slither.md).
A few adaptions have been made due to the result of the static analysis.

# Template

## Foundry with Soldeer Template

```shell
# to install the dependencies listed in foundry.toml
forge soldeer update
# build
forge build
# test
forge test

# remove dependencies
forge soldeer uninstall DEPENDENCY
# install dependencies
forge soldeer install @openzeppelin-contracts~5.0.2
```

https://book.getfoundry.sh/projects/soldeer

Check: https://soldeer.xyz/
Github: https://github.com/mario-eth/soldeer

**Foundry is a blazing fast, portable and modular toolkit for Ethereum application development written in Rust.**

Foundry consists of:

- **Forge**: Ethereum testing framework (like Truffle, Hardhat and DappTools).
- **Cast**: Swiss army knife for interacting with EVM smart contracts, sending transactions and getting chain data.
- **Anvil**: Local Ethereum node, akin to Ganache, Hardhat Network.
- **Chisel**: Fast, utilitarian, and verbose solidity REPL.

## Documentation

https://book.getfoundry.sh/

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy

```shell
$ forge script script/Counter.s.sol:CounterScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```
