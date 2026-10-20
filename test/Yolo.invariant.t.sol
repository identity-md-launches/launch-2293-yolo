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
        _transfer(from, to, amount);
    }

    /// @dev Exercise full drains, dust, overdrafts and uint256.max in evolving states.
    function transferBoundary(uint8 fromSeed, uint8 toSeed, uint256 rawAmount) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        _transfer(from, to, _boundaryAmount(rawAmount, expectedBalance[from]));
    }

    function _transfer(address from, address to, uint256 amount) private {
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
        _approve(owner, spender, amount);
    }

    /// @dev Make revocation and finite/infinite transitions frequent, not accidental.
    function approveBoundary(uint8 ownerSeed, uint8 spenderSeed, uint8 choice) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256[5] memory amounts = [uint256(0), 1, expectedBalance[owner], type(uint256).max - 1, type(uint256).max];
        _approve(owner, spender, amounts[choice % amounts.length]);
    }

    function _approve(address owner, address spender, uint256 amount) private {
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
    }

    function transferFrom(uint8 spenderSeed, uint8 fromSeed, uint8 toSeed, uint256 rawAmount) external {
        address spender = actors[spenderSeed % actors.length];
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 amount = rawAmount % (SUPPLY + 1);
        _transferFrom(spender, from, to, amount);
    }

    function transferFromBoundary(uint8 spenderSeed, uint8 fromSeed, uint8 toSeed, uint256 rawAmount) external {
        address spender = actors[spenderSeed % actors.length];
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 limit = expectedBalance[from];
        if (expectedAllowance[from][spender] < limit) {
            limit = expectedAllowance[from][spender];
        }
        _transferFrom(spender, from, to, _boundaryAmount(rawAmount, limit));
    }

    function _transferFrom(address spender, address from, address to, uint256 amount) private {
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

    /// @dev Rejected calls must leave the entire balance/allowance model unchanged.
    /// Amounts satisfy balance and allowance constraints, isolating address validation.
    function rejectZeroAddress(uint8 ownerSeed, uint8 spenderSeed, uint256 rawAmount, uint8 operation) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        bytes memory data;
        bytes memory expectedError;
        address caller = owner;
        if (operation % 3 == 0) {
            uint256 amount = bound(rawAmount, 0, expectedBalance[owner]);
            data = abi.encodeCall(token.transfer, (address(0), amount));
            expectedError = abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0));
        } else if (operation % 3 == 1) {
            uint256 limit = expectedBalance[owner];
            if (expectedAllowance[owner][spender] < limit) {
                limit = expectedAllowance[owner][spender];
            }
            uint256 amount = bound(rawAmount, 0, limit);
            caller = spender;
            data = abi.encodeCall(token.transferFrom, (owner, address(0), amount));
            expectedError = abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0));
        } else {
            data = abi.encodeCall(token.approve, (address(0), rawAmount));
            expectedError = abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0));
        }

        vm.prank(caller);
        (bool success, bytes memory result) = address(token).call(data);
        assertFalse(success, "zero address operation succeeded");
        assertEq(result, expectedError, "zero address operation failed for the wrong reason");
    }

    function _boundaryAmount(uint256 seed, uint256 limit) private pure returns (uint256) {
        uint256 choice = seed % 6;
        if (choice == 0) return 0;
        if (choice == 1) return 1;
        if (choice == 2) return limit;
        // The limit is at most SUPPLY, so adding one cannot overflow.
        if (choice == 3) return limit + 1;
        if (choice == 4) return type(uint256).max;
        return bound(seed / 6, 0, limit);
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 128
/// forge-config: default.invariant.fail-on-revert = true
contract YoloInvariantTest is StdInvariant, Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;
    Yolo internal token;
    YoloHandler internal handler;

    function setUp() public {
        token = new Yolo();
        handler = new YoloHandler(token);
        assertTrue(token.transfer(handler.actors(0), SUPPLY));

        bytes4[] memory selectors = new bytes4[](7);
        selectors[0] = YoloHandler.transfer.selector;
        selectors[1] = YoloHandler.approve.selector;
        selectors[2] = YoloHandler.transferFrom.selector;
        selectors[3] = YoloHandler.transferBoundary.selector;
        selectors[4] = YoloHandler.approveBoundary.selector;
        selectors[5] = YoloHandler.transferFromBoundary.selector;
        selectors[6] = YoloHandler.rejectZeroAddress.selector;
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
            assertEq(token.allowance(handler.actors(i), address(0)), 0);
            assertEq(token.allowance(address(0), handler.actors(i)), 0);
            for (uint256 j; j < 4; ++j) {
                address owner = handler.actors(i);
                address spender = handler.actors(j);
                assertEq(token.allowance(owner, spender), handler.expectedAllowance(owner, spender));
            }
        }
    }

    function invariant_MetadataRemainsFixed() public view {
        assertEq(token.name(), "Yolo");
        assertEq(token.symbol(), "YOLO");
        assertEq(token.decimals(), 18);
        assertEq(token.INITIAL_SUPPLY(), SUPPLY);
    }
}
