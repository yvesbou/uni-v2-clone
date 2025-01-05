// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

import {IERC3156FlashBorrower} from "@openzeppelin-contracts-5.0.2/interfaces/IERC3156FlashBorrower.sol";
import {IERC3156FlashLender} from "@openzeppelin-contracts-5.0.2/interfaces/IERC3156FlashLender.sol";
import {IERC20} from "@openzeppelin-contracts-5.0.2/interfaces/IERC20.sol";

contract FlashBorrower is IERC3156FlashBorrower {
    IERC3156FlashLender lender;
    mapping(address trustedInitiator => bool authorized) trustedInitiators;

    error UntrustedLender();
    error UntrustedInitiator();

    constructor(address lender_) {
        lender = IERC3156FlashLender(lender_);
        trustedInitiators[msg.sender] = true;
    }

    function onFlashLoan(address initiator, address token, uint256 amount, uint256 fee, bytes calldata data)
        external
        override
        returns (bytes32)
    {
        if (msg.sender != address(lender)) revert UntrustedLender();
        if (!trustedInitiators[msg.sender]) revert UntrustedInitiator();

        // (parsedData) = abi.decode(data, (DataTypes));
        // do something with the flashloan

        IERC20(token).approve(address(lender), amount + fee);

        return keccak256("ERC3156Flashborrower.onFlashLoan");
    }
}
