// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Yolo} from "../../src/Yolo.sol";

/// @dev Local deployment/transfer fixture, not a production application contract.
contract FactoryHarness {
    function deploy() external returns (Yolo) {
        return new Yolo();
    }

    function deployCreate2(bytes32 salt) external returns (Yolo) {
        return new Yolo{salt: salt}();
    }

    function move(Yolo token, address recipient, uint256 amount) external returns (bool) {
        return token.transfer(recipient, amount);
    }
}
