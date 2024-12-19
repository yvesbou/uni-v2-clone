// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

import {ERC20} from "@openzeppelin-contracts-5.0.2/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin-contracts-5.0.2/access/Ownable.sol";

contract Token is ERC20, Ownable {
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) Ownable(msg.sender) {
        _mint(msg.sender, 100e18);
    }

    function mint(address beneficiary, uint256 amount) public onlyOwner {
        _mint(beneficiary, amount);
    }
}
