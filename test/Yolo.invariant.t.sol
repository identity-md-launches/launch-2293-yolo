// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Yolo} from "../src/Yolo.sol";

/// @dev Maintains an independent ledger and exercises both successful and rejected operations.
contract YoloHandler is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;
    Yolo public immutable token;
    address[4] public actors;
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor(Yolo token_) {
        token = token_;
        for (uint256 i; i < actors.length; ++i) {
            actors[i] = makeAddr(string.concat("invariant holder ", vm.toString(i)));
        }
        expectedBalance[actors[0]] = SUPPLY;
    }

    function transfer(uint8 fromSeed, uint8 toSeed, uint256 rawAmount) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 amount = rawAmount % (SUPPLY + 1);
        uint256 available = expectedBalance[from];

        vm.prank(from);
        (bool success, bytes memory result) = address(token).call(abi.encodeCall(token.transfer, (to, amount)));
        assertEq(success, amount <= available, "transfer outcome differs from model");
        if (success) {
            assertTrue(abi.decode(result, (bool)));
            expectedBalance[from] -= amount;
            expectedBalance[to] += amount;
        } else {
            assertEq(
                result, abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, available, amount)
            );
        }
    }

    function approve(uint8 ownerSeed, uint8 spenderSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
    }

    function transferFrom(uint8 spenderSeed, uint8 fromSeed, uint8 toSeed, uint256 rawAmount) external {
        address spender = actors[spenderSeed % actors.length];
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 amount = rawAmount % (SUPPLY + 1);
        uint256 allowed = expectedAllowance[from][spender];
        uint256 available = expectedBalance[from];

        vm.prank(spender);
        (bool success, bytes memory result) =
            address(token).call(abi.encodeCall(token.transferFrom, (from, to, amount)));
        assertEq(success, amount <= allowed && amount <= available, "transferFrom outcome differs from model");
        if (success) {
            assertTrue(abi.decode(result, (bool)));
            if (allowed != type(uint256).max) {
                expectedAllowance[from][spender] -= amount;
            }
            expectedBalance[from] -= amount;
            expectedBalance[to] += amount;
        } else if (amount > allowed) {
            assertEq(
                result,
                abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, allowed, amount)
            );
        } else {
            assertEq(
                result, abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, available, amount)
            );
        }
    }
}

contract YoloInvariantTest is StdInvariant, Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;
    Yolo internal token;
    YoloHandler internal handler;

    function setUp() public {
        token = new Yolo();
        handler = new YoloHandler(token);
        assertTrue(token.transfer(handler.actors(0), SUPPLY));

        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = YoloHandler.transfer.selector;
        selectors[1] = YoloHandler.approve.selector;
        selectors[2] = YoloHandler.transferFrom.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_SupplyAndBalancesMatchIndependentLedger() public view {
        uint256 sum;
        for (uint256 i; i < 4; ++i) {
            address actor = handler.actors(i);
            uint256 actual = token.balanceOf(actor);
            assertEq(actual, handler.expectedBalance(actor), "balance differs from model");
            sum += actual;
        }
        assertEq(sum, SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(0)), 0);
    }

    function invariant_AllowancesMatchIndependentLedger() public view {
        for (uint256 i; i < 4; ++i) {
            for (uint256 j; j < 4; ++j) {
                address owner = handler.actors(i);
                address spender = handler.actors(j);
                assertEq(token.allowance(owner, spender), handler.expectedAllowance(owner, spender));
            }
        }
    }
}
