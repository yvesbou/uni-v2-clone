# Uni V2 Clone (Educational Purpose)

## Amount Out

Without fees

$$
Δy=\frac{y \cdot Δx}{x+Δx}
$$

As in test `test_simple_swap()` the trader wants to trade 100 of `token A` for `token B`,
given that the reserves are 2000 for `token A` and 400 for `token B` and a fee for LPs of 1% (99/100):

$$
396.79 = \frac{99 \cdot 100 \cdot 2000}{400 \cdot 100 + 99 \cdot 100}
$$

### Derivation of the above formula

1. Start with the constant product formula after a swap:

$$
(x + \Delta x) \cdot (y - \Delta y) = x \cdot y
$$

2. Expand the left-hand side:

$$
x \cdot y - x \cdot \Delta y + y \cdot \Delta x - \Delta x \cdot \Delta y = x \cdot y
$$

3. Cancel $(x \cdot y)$ on both sides:

$$
-x \cdot \Delta y + y \cdot \Delta x - \Delta x \cdot \Delta y = 0
$$

4. Assume $( \Delta x \cdot \Delta y \approx 0 $) for small swaps:

$$
-x \cdot \Delta y + y \cdot \Delta x = 0
$$

5. Solve for $( \Delta y $):

$$
\Delta y = \frac{y \cdot \Delta x}{x}
$$

6. Account for the updated reserve $(x + \Delta x$):

$$
\Delta y = \frac{y \cdot \Delta x}{x + \Delta x}
$$

---

## TWAP (Time-weighted-average-price)

Each Uniswap Pool as a competitive market serves as an indicator what the true price is. Price is a ratio on how much `y` do I need to pay in order to get `x` and vice versa. In our pool we have this information. So we can serve oracle consumers with on-chain data.

The following variables from the Pool contract are used to compute the TWAP: `price0CumulativeLast`, `price1CumulativeLast` and `blockTimestampLast`.

Time weighted average price is usually computed as follows:

$$
TWAP = \frac {p_0*T_0 + p_1*T_1 + p_2*T_2 + ... + p_n*T_n}{T_0 + T_1 + T_2 + ... + T_n}
$$

where $T_x$ is the duration where price $p_x$ was recorded.

This makes intuitively sense, let imagine us 24h and 12h the price was $1 and 12h the price was $2. Without calculation we would guess that the TWAP is $1.5.

Let us check with the formula:

$$
TWAP = \frac {1*12 + 2*12}{24} = \frac {36}{24} = \frac {3}{2} = 1.5
$$

### Code in Pool contract

When coding smart contracts optimisation is always a requirement. So storing $p_0$ until $p_n$ is not feasible. Instead we could create a work-around, which requires that consumers of the TWAP oracle we're creating snapshot the data we store.

For our work-around we compute the nominator let's call it $weightedPrice_n$ = $p_0*T_0 + p_1*T_1 + p_2*T_2 + ... + p_n*T_n$ to the given time $t_n$ where we update the reserves (ie the ratio).

So in our code

```Solidity
price0CumulativeLast += newReserve1 * timeElapsed / newReserve0;
```

where `price0CumulativeLast` is $weightedPrice_n$

Let's say we want the TWAP for a time period (and we come up with arbitrary time points, where timestamp 4 is strictly greater than timestamp 2) between timestamp 2 and timestamp 4. When we snapshot a previous $weightedPrice_2$ ($p_0*T_0 + p_1*T_1 + p_2*T_2$) and now is timestamp 4, which is $p_0*T_0 + p_1*T_1 + p_2*T_2 + p_3*T_3 + p_4*T_4$, the difference of the two weighted prices is $p_3*T_3 + p_4*T_4$, exactly what we wanted.

This means we can save on storage, by only storing a cumulative price each time the reserves change.

For the denominator we need the total duration of this period $T_3+T_4$, but this is easy as our first snapshot at timestamp 2 is exactly the duration smaller than timestamp 4.

$p_x$ is timestamp at time `x`.

$$
p_0*T_0 + p_1*T_1 + p_2*T_2 + p_3*T_3 + p_4*T_4 - (p_0*T_0 + p_1*T_1 + p_2*T_2) = \\

p_3*T_3 + p_4*T_4
$$

let's introduce the time difference as

$$
t_4-t_2 = T_4+T_3+T_2+T_1 - (T_2+T_1) = T_4+T_3
$$

Which gives us the full expression as,

$$
TWAP = \frac {p_3*T_3 + p_4*T_4}{T_4+T_3}
$$

Regarding this line:

```solidity
uint32 blockTimestamp = uint32(block.timestamp % 2**32);
```

check out this link: https://github.com/Uniswap/v2-core/issues/96

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
