# Why do the `price0CumulativeLast` and `price1CumulativeLast` never decrement?

Simply put because prices are never negative and a cumulative function can not decrease if items/units are not negative.

But the more interesting question is how is the TWAP stored in the smart contract? Storing prices for each timestamp is not feasible with the evm.

This is why a cumulative sum approach is used. Each time a new price is registered, the time weighted sum of the last/previous price is stored by adding it to the cumulative sum. An oracle consumer that wants to use the on-chain source then could snapshot the `price0CumulativeLast` and `price1CumulativeLast` once with timestamp, and at a later point a second time which yields a TWAP price, since the difference between both cumulatives is a time weighted price which can be divided by the total duration of this period which is the time difference of both timestamps.

As written in the main readme

$p_x$ is timestamp at time `x` and we have two snapshots $t_2$ and $t_4$

$$
p_0 \cdot T_0 + p_1 \cdot T_1 + p_2 \cdot T_2 + p_3 \cdot T_3 + p_4 \cdot T_4 - (p_0 \cdot T_0 + p_1 \cdot T_1 + p_2 \cdot T_2) = p_3 \cdot T_3 + p_4 \cdot T_4
$$

let's introduce the time difference as

$$
t_4-t_2 = T_4+T_3+T_2+T_1 - (T_2+T_1) = T_4+T_3
$$

Which gives us the full expression as

$$
TWAP = \frac {p_3 \cdot T_3 + p_4 \cdot T_4}{T_4+T_3}
$$

# How do you write a contract that uses the oracle?

see [TWAPConsumer.sol](../src/TWAPConsumer.sol)

|                      | snapshot too recent | snapshot ok                     | no previous snapshot  |
| -------------------- | ------------------- | ------------------------------- | --------------------- |
| oracle price too old | revert              | revert                          | revert                |
| oracle price ok      | revert              | compute price + update snapshot | take snapshot         |

# Why are `price0CumulativeLast` and `price1CumulativeLast` stored separately? Why not just calculate ``price1CumulativeLast = 1/price0CumulativeLast`?

$$
\frac {1}{p_1}+\frac {1}{p_2} \ne p_1+p_2
$$
