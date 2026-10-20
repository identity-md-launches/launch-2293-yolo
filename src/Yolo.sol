// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title Yolo
/// @notice A fixed supply of one billion YOLO, with 18 decimals.
/// @dev The immediate deployer receives the entire supply. During a factory launch,
///      that recipient is the factory. There are no administrative or minting entry points.
contract Yolo is ERC20 {
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18;

    constructor() ERC20("Yolo", "YOLO") {
        _mint(msg.sender, INITIAL_SUPPLY);
    }
}
