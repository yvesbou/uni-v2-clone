// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

import {IERC3156FlashBorrower} from "@openzeppelin-contracts-5.0.2/interfaces/IERC3156FlashBorrower.sol";
import {IERC3156FlashLender} from "@openzeppelin-contracts-5.0.2/interfaces/IERC3156FlashLender.sol";
import {IERC20} from "@openzeppelin-contracts-5.0.2/interfaces/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin-contracts-5.0.2/utils/ReentrancyGuard.sol";

import {Pair} from "./Pair.sol";

contract ReEnterer is IERC3156FlashBorrower, ReentrancyGuard {
    IERC3156FlashLender immutable lender;
    address token0;
    address token1;

    mapping(address trustedInitiator => bool authorized) public trustedInitiators;

    error UntrustedLender();
    error UntrustedInitiator();

    constructor(address lender_) {
        lender = IERC3156FlashLender(lender_);
        trustedInitiators[msg.sender] = true;
    }

    /// @notice This implementation tries to re-enter
    /// @dev This function does not achieve the flashloan nor the re-enter, but it proves the nonReentrant efficacy
    function onFlashLoan(address initiator, address token, uint256 amount, uint256 fee, bytes calldata data)
        external
        override
        nonReentrant
        returns (bytes32)
    {
        if (msg.sender != address(lender)) revert UntrustedLender();
        // anyone can call flashloan() with an arbitrary borrower as the target and pass arbitrary data.
        // To ensure the data is not malicious, a flash loan receiver contract should only allow a restricted
        // set of initiators
        if (!trustedInitiators[initiator]) revert UntrustedInitiator();

        address otherAsset;
        if (token == token0) otherAsset = token1;
        else otherAsset = token0;

        // amountIn = 0, as the swap should revert already
        Pair(address(lender)).swapIn(address(this), otherAsset, amount, 0, block.timestamp + 1 hours);

        // no need to implement as it will fail
        // Pair(address(lender)).provideLiquidity();

        // (parsedData) = abi.decode(data, (DataTypes));
        // do something with the flashloan

        IERC20(token).approve(address(lender), amount + fee);

        return keccak256("ERC3156Flashborrower.onFlashLoan");
    }
}
