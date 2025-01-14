# Uni V2 Clone (Educational Purpose)

# Price Impact of a Swap

Uniswap revolutionised trading by introducing the AMM (automated market maker) with the following equation:

$$
x \cdot y = k
$$

This equation allows to trade $x$ against $y$ and vice versa while including the dynamic of supply and demand. In each trade, $k$ is only allowed to increase (fees), but never decrease. ($k$ decreases in fact if LPs withdraw their position as they withdraw $x$ and $y$.)

If plotted one can see that the price impact is stronger the more the $x$ , $y$ pair is pushed out of balance.

# Swap

Swapping needs slippage protection because transactions are public to sophisticated actors which can extract value from the un-finalised transactions by buying before them and sell them with a worse price. This is why users can specify the exact amount in (which they pay) or the exact amount out (which they receive). In Uniswap V2 this computation is part of the Router, in this version it's part of the pool implementation itself.

## Amount In (`swapIn`)

In `function swapIn(...)` users specify the amount they want to spend and a minimal amount which they require to receive at least, otherwise their transaction should fail.

The formula is given without fees

$$
Δx=\frac{x \cdot Δy}{y+Δy}
$$

where $\Delta y$ is the fix `amountIn` and $\Delta x$ is the amount which is required at least.

When we add fees = $f/F$, e.g `1%` = $99/100$ the formula results in:

$$
Δx=\frac{x \cdot f \cdot Δy}{y \cdot F+Δy \cdot f}
$$

Let's look at an example from the test file `Swaps.t.sol` with test case `test_simple_swap()` where the trader wants to trade 100 of `token A` for `token B`,
given that the reserves are 2000 for `token A` and 400 for `token B` and a fee for LPs of 1% (99/100):

$$
396.79 = \frac{99 \cdot 100 \cdot 2000}{400 \cdot 100 + 99 \cdot 100}
$$

### Derivation of the above formula

Let's assume x gets taken out of the pool and y gets deposited into it.

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
\frac{ x \cdot \Delta y \cdot f}{{F \cdot (y + \Delta y \cdot \frac{f}{F}})} \ge \Delta x
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

# Withdraw Liquidity

# Protocol Fee

The protocol wants to earn some fee on the trades but transfering tokens each time for a small fee to a target contract is too gas expensive. Another idea would be to deduct fees sporadicly at $t_x$ and then at $t_{x+\Delta x}$ but with this idea it could be that some LPs don't pay any fees which is not fair.
Therefore the fee is calculated and deducted whenever an LP manages the position.

Requirements:

- the fee should be deducted when LPs manage their positions
- the fee should only be worth $\frac x y$ of the fees collected by the LPs, where $x < y$
- if liquidity grows without additional supply by new LPs from `l1` to `l2`, $\frac {y-x}{y}$ of the difference should be captured by the LPs and $\frac x y$ by the protocol
- if the liquidity only grows by new supply, no protocol fee should be deducted
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
