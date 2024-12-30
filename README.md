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

## TWAP (Time-weighted-average-price)

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
