// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Yolo} from "../src/Yolo.sol";

/// @dev Regression cases complement the constructor, deployment and ERC-20 tests in Yolo.t.sol.
/// forge-config: default.fuzz.runs = 1000
contract YoloBoundaryTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;
    Yolo internal token;
    address internal holder = makeAddr("boundary holder");
    address internal recipient = makeAddr("boundary recipient");
    address internal spender = makeAddr("boundary spender");

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        token = new Yolo();
    }

    function test_OneBaseUnitCanBeTransferredApprovedAndSpentExactly() public {
        assertTrue(token.transfer(holder, 1));
        vm.prank(holder);
        assertTrue(token.approve(spender, 1));

        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(holder, recipient, 1);
        vm.prank(spender);
        assertTrue(token.transferFrom(holder, recipient, 1));

        assertEq(token.balanceOf(holder), 0);
        assertEq(token.balanceOf(recipient), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
        assertEq(token.allowance(holder, spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_MaximumTransferRevertsWithoutChangingBalances() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
            )
        );
        token.transfer(recipient, type(uint256).max);

        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(recipient), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_InfiniteApprovalDoesNotAuthorizeMaximumOverdraft() public {
        assertTrue(token.approve(spender, type(uint256).max));
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
            )
        );
        vm.prank(spender);
        token.transferFrom(address(this), recipient, type(uint256).max);

        assertEq(token.allowance(address(this), spender), type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(recipient), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_LargestFiniteAllowanceIsConsumedRatherThanTreatedAsInfinite() public {
        uint256 allowed = type(uint256).max - 1;
        assertTrue(token.approve(spender, allowed));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), recipient, 1));
        assertEq(token.allowance(address(this), spender), allowed - 1);

        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), recipient, SUPPLY - 1));
        assertEq(token.allowance(address(this), spender), allowed - SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(recipient), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ExhaustedApprovalCannotBeReusedAfterBalanceRefill() public {
        assertTrue(token.transfer(holder, 1));
        vm.prank(holder);
        assertTrue(token.approve(spender, 1));
        vm.prank(spender);
        assertTrue(token.transferFrom(holder, recipient, 1));
        assertTrue(token.transfer(holder, 1));

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(holder, recipient, 1);

        assertEq(token.balanceOf(holder), 1);
        assertEq(token.balanceOf(recipient), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 2);
        assertEq(token.allowance(holder, spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_TransferFromByHolderStillRequiresSelfApproval() public {
        assertTrue(token.transfer(holder, 1));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, holder, 0, 1));
        vm.prank(holder);
        token.transferFrom(holder, recipient, 1);
        assertEq(token.balanceOf(holder), 1);
        assertEq(token.balanceOf(recipient), 0);

        vm.prank(holder);
        assertTrue(token.approve(holder, 1));
        vm.prank(holder);
        assertTrue(token.transferFrom(holder, recipient, 1));
        assertEq(token.allowance(holder, holder), 0);
        assertEq(token.balanceOf(holder), 0);
        assertEq(token.balanceOf(recipient), 1);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_SpenderReceivingTokensStillConsumesAllowance() public {
        assertTrue(token.approve(spender, 1));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), spender, 1));
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(spender), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), spender, 1);
        assertEq(token.balanceOf(spender), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
    }

    function test_ReducingInfiniteApprovalImmediatelyLimitsSpender() public {
        assertTrue(token.approve(spender, type(uint256).max));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), recipient, 1));
        assertTrue(token.approve(spender, 1));

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 1, 2));
        vm.prank(spender);
        token.transferFrom(address(this), recipient, 2);
        assertEq(token.allowance(address(this), spender), 1);
        assertEq(token.balanceOf(recipient), 1);

        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), recipient, 1));
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(recipient), 2);
        assertEq(token.balanceOf(address(this)), SUPPLY - 2);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ReapprovalAfterPartialSpendReplacesRemainingAllowance() public {
        assertTrue(token.approve(spender, 3));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), recipient, 1));
        assertEq(token.allowance(address(this), spender), 2);

        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(address(this), spender, 3);
        assertTrue(token.approve(spender, 3));
        assertEq(token.allowance(address(this), spender), 3);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), recipient, 3));

        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(recipient), 4);
        assertEq(token.balanceOf(address(this)), SUPPLY - 4);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_RepeatedSameApprovalEmitsWithoutAccumulatingAllowance() public {
        assertTrue(token.approve(spender, 1));
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(address(this), spender, 1);
        assertTrue(token.approve(spender, 1));
        assertEq(token.allowance(address(this), spender), 1);

        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), recipient, 1));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), recipient, 1);
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(recipient), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
    }

    function test_InfiniteApprovalCannotBypassZeroRecipientValidation() public {
        assertTrue(token.approve(spender, type(uint256).max));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(this), address(0), 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(this), address(0), 0);

        assertEq(token.allowance(address(this), spender), type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ZeroTransferFromStillRejectsZeroRecipientWithoutAllowance() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(holder, address(0), 0);
        assertEq(token.allowance(holder, spender), 0);
        assertEq(token.balanceOf(holder), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ZeroApprovalStillRejectsZeroSpender() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 0);
        assertEq(token.allowance(address(this), address(0)), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_TransferRoundTripRestoresBalancesAndPreservesApprovals(
        uint256 rawBalance,
        uint256 rawAmount,
        uint256 approval
    ) public {
        uint256 balance = bound(rawBalance, 0, SUPPLY);
        uint256 amount = bound(rawAmount, 0, balance);
        assertTrue(token.transfer(holder, balance));
        vm.prank(holder);
        assertTrue(token.approve(spender, approval));
        vm.prank(recipient);
        assertTrue(token.approve(spender, type(uint256).max - approval));

        vm.prank(holder);
        assertTrue(token.transfer(recipient, amount));
        // Check the intermediate state too: a pair of no-op transfers is not a round trip.
        assertEq(token.balanceOf(holder), balance - amount);
        assertEq(token.balanceOf(recipient), amount);
        vm.prank(recipient);
        assertTrue(token.transfer(holder, amount));

        assertEq(token.balanceOf(holder), balance);
        assertEq(token.balanceOf(recipient), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - balance);
        assertEq(token.allowance(holder, spender), approval);
        assertEq(token.allowance(recipient, spender), type(uint256).max - approval);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_SplitDelegatedTransfersMatchOneTransfer(
        uint256 rawAllowance,
        uint256 rawAmount,
        uint256 rawSplit,
        bool infinite
    ) public {
        Yolo splitToken = new Yolo();
        uint256 allowed = infinite ? type(uint256).max : bound(rawAllowance, 0, type(uint256).max - 1);
        uint256 limit = allowed < SUPPLY ? allowed : SUPPLY;
        uint256 amount = bound(rawAmount, 0, limit);
        uint256 first = bound(rawSplit, 0, amount);
        assertTrue(token.approve(spender, allowed));
        assertTrue(splitToken.approve(spender, allowed));

        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), recipient, amount));
        vm.prank(spender);
        assertTrue(splitToken.transferFrom(address(this), recipient, first));
        vm.prank(spender);
        assertTrue(splitToken.transferFrom(address(this), recipient, amount - first));

        assertEq(token.balanceOf(recipient), amount);
        assertEq(splitToken.balanceOf(recipient), token.balanceOf(recipient));
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(splitToken.balanceOf(address(this)), token.balanceOf(address(this)));
        assertEq(token.allowance(address(this), spender), infinite ? allowed : allowed - amount);
        assertEq(splitToken.allowance(address(this), spender), token.allowance(address(this), spender));
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(splitToken.totalSupply(), SUPPLY);
    }

    function testFuzz_InsufficientBalanceRollsBackAnySufficientAllowance(
        uint256 rawBalance,
        uint256 rawAmount,
        uint256 rawAllowance
    ) public {
        uint256 balance = bound(rawBalance, 0, SUPPLY);
        uint256 allowed = bound(rawAllowance, balance + 1, type(uint256).max);
        uint256 amount = bound(rawAmount, balance + 1, allowed);
        assertTrue(token.transfer(holder, balance));
        vm.prank(holder);
        assertTrue(token.approve(spender, allowed));

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, holder, balance, amount));
        vm.prank(spender);
        token.transferFrom(holder, recipient, amount);

        assertEq(token.allowance(holder, spender), allowed);
        assertEq(token.balanceOf(holder), balance);
        assertEq(token.balanceOf(recipient), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - balance);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_RevocationAfterPartialSpendBlocksUntilReapproved(
        uint256 rawBalance,
        uint256 rawSpent,
        bool infinite
    ) public {
        uint256 balance = bound(rawBalance, 2, SUPPLY);
        uint256 spent = bound(rawSpent, 1, balance - 1);
        assertTrue(token.transfer(holder, balance));
        vm.prank(holder);
        assertTrue(token.approve(spender, infinite ? type(uint256).max : balance));
        vm.prank(spender);
        assertTrue(token.transferFrom(holder, recipient, spent));
        vm.prank(holder);
        assertTrue(token.approve(spender, 0));

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(holder, recipient, 1);
        assertEq(token.balanceOf(holder), balance - spent);
        assertEq(token.balanceOf(recipient), spent);
        assertEq(token.allowance(holder, spender), 0);

        vm.prank(holder);
        assertTrue(token.approve(spender, balance - spent));
        vm.prank(spender);
        assertTrue(token.transferFrom(holder, recipient, balance - spent));
        assertEq(token.allowance(holder, spender), 0);
        assertEq(token.balanceOf(holder), 0);
        assertEq(token.balanceOf(recipient), balance);
        assertEq(token.balanceOf(address(this)), SUPPLY - balance);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_DelegatedSelfTransferPreservesBalanceAndSpendsApproval(
        uint256 rawBalance,
        uint256 rawAmount,
        uint256 rawAllowance
    ) public {
        uint256 balance = bound(rawBalance, 0, SUPPLY);
        uint256 amount = bound(rawAmount, 0, balance);
        uint256 allowed = bound(rawAllowance, amount, type(uint256).max);
        assertTrue(token.transfer(holder, balance));
        vm.prank(holder);
        assertTrue(token.approve(spender, allowed));

        vm.prank(spender);
        assertTrue(token.transferFrom(holder, holder, amount));

        assertEq(token.balanceOf(holder), balance);
        assertEq(token.balanceOf(address(this)), SUPPLY - balance);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.allowance(holder, spender), allowed == type(uint256).max ? allowed : allowed - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
