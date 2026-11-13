// SPDX-License-Identifier: MIT
pragma solidity >=0.8.6 <0.9.0;

import "forge-std/Test.sol";
import "../src/ApprovedSender.sol";
import "./Mocks.sol";

contract ApprovedSenderTest is Test {
    ApprovedSender s;
    StdToken token;
    address alice = address(0xA11CE);
    address bob = address(0xB0B);
    address carol = address(0xCA201);
    address mallory = address(0xBAD);

    event WalletApproved(address indexed wallet, address indexed by);
    event WalletRemoved(address indexed wallet, address indexed by);
    event Sent(address indexed token, address indexed by, address indexed to, uint256 amount);
    event SentFromSelf(address indexed token, address indexed from, address indexed to, uint256 amount);

    function setUp() public {
        address[] memory init = new address[](2);
        init[0] = alice;
        init[1] = bob;
        s = new ApprovedSender(init);
        token = new StdToken();
        token.mint(address(s), 1_000e6);
    }

    // ------------------------------------------------------------ constructor

    function test_constructor_sets_initial_wallets() public view {
        assertTrue(s.isApproved(alice));
        assertTrue(s.isApproved(bob));
        assertFalse(s.isApproved(carol));
        assertEq(s.approvedCount(), 2);
    }

    function test_constructor_rejects_empty_list() public {
        vm.expectRevert(ApprovedSender.EmptyList.selector);
        new ApprovedSender(new address[](0));
    }

    function test_constructor_rejects_duplicates_and_zero() public {
        address[] memory dup = new address[](2);
        dup[0] = alice;
        dup[1] = alice;
        vm.expectRevert(abi.encodeWithSelector(ApprovedSender.AlreadyApproved.selector, alice));
        new ApprovedSender(dup);

        address[] memory zero = new address[](1);
        vm.expectRevert(abi.encodeWithSelector(ApprovedSender.InvalidWallet.selector, address(0)));
        new ApprovedSender(zero);
    }

    // ------------------------------------------------------------ wallet list

    function test_approved_wallet_can_approve_and_remove_others() public {
        vm.expectEmit(true, true, false, false);
        emit WalletApproved(carol, alice);
        vm.prank(alice);
        s.approveWallet(carol);
        assertTrue(s.isApproved(carol));
        assertEq(s.approvedCount(), 3);

        vm.expectEmit(true, true, false, false);
        emit WalletRemoved(alice, carol);
        vm.prank(carol);
        s.removeWallet(alice);
        assertFalse(s.isApproved(alice));
        assertEq(s.approvedCount(), 2);
    }

    function test_unapproved_wallet_cannot_change_list() public {
        vm.startPrank(mallory);
        vm.expectRevert(abi.encodeWithSelector(ApprovedSender.NotApproved.selector, mallory));
        s.approveWallet(mallory);
        vm.expectRevert(abi.encodeWithSelector(ApprovedSender.NotApproved.selector, mallory));
        s.removeWallet(alice);
        vm.stopPrank();
    }

    function test_removed_wallet_loses_all_rights() public {
        vm.prank(alice);
        s.removeWallet(bob);
        vm.startPrank(bob);
        vm.expectRevert(abi.encodeWithSelector(ApprovedSender.NotApproved.selector, bob));
        s.send(address(token), bob, 1);
        vm.expectRevert(abi.encodeWithSelector(ApprovedSender.NotApproved.selector, bob));
        s.approveWallet(bob);
        vm.stopPrank();
    }

    function test_cannot_remove_last_wallet_even_yourself() public {
        vm.prank(alice);
        s.removeWallet(bob);
        vm.prank(alice);
        vm.expectRevert(ApprovedSender.LastApprovedWallet.selector);
        s.removeWallet(alice);
        assertEq(s.approvedCount(), 1);
    }

    function test_can_remove_yourself_when_others_remain() public {
        vm.prank(alice);
        s.removeWallet(alice);
        assertFalse(s.isApproved(alice));
        assertEq(s.approvedCount(), 1);
    }

    function test_list_edge_cases() public {
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(ApprovedSender.InvalidWallet.selector, address(0)));
        s.approveWallet(address(0));
        // approving the contract itself would let the "last wallet" rule be met by an address
        // nobody can sign for, locking the funds
        vm.expectRevert(abi.encodeWithSelector(ApprovedSender.InvalidWallet.selector, address(s)));
        s.approveWallet(address(s));
        vm.expectRevert(abi.encodeWithSelector(ApprovedSender.AlreadyApproved.selector, bob));
        s.approveWallet(bob);
        vm.expectRevert(abi.encodeWithSelector(ApprovedSender.NotInList.selector, carol));
        s.removeWallet(carol);
        vm.stopPrank();
    }

    // ------------------------------------------------------------ send from contract

    function test_approved_wallet_sends_contract_tokens() public {
        vm.expectEmit(true, true, true, true);
        emit Sent(address(token), alice, carol, 250e6);
        vm.prank(alice);
        s.send(address(token), carol, 250e6);
        assertEq(token.balanceOf(carol), 250e6);
        assertEq(s.tokenBalance(address(token)), 750e6);
    }

    function test_unapproved_wallet_cannot_send() public {
        vm.prank(mallory);
        vm.expectRevert(abi.encodeWithSelector(ApprovedSender.NotApproved.selector, mallory));
        s.send(address(token), mallory, 1);
        assertEq(token.balanceOf(mallory), 0);
    }

    function test_send_rejects_bad_arguments() public {
        vm.startPrank(alice);
        vm.expectRevert(ApprovedSender.ZeroAmount.selector);
        s.send(address(token), carol, 0);
        vm.expectRevert(abi.encodeWithSelector(ApprovedSender.BadRecipient.selector, address(0)));
        s.send(address(token), address(0), 1);
        vm.expectRevert(abi.encodeWithSelector(ApprovedSender.BadRecipient.selector, address(s)));
        s.send(address(token), address(s), 1);
        vm.expectRevert(abi.encodeWithSelector(ApprovedSender.BadRecipient.selector, address(token)));
        s.send(address(token), address(token), 1);
        vm.expectRevert(abi.encodeWithSelector(ApprovedSender.NotAContract.selector, carol));
        s.send(carol, bob, 1);
        vm.stopPrank();
    }

    function test_send_more_than_balance_reverts() public {
        vm.prank(alice);
        vm.expectRevert(bytes("balance"));
        s.send(address(token), carol, 1_000e6 + 1);
    }

    function test_tron_usdt_style_false_return_still_works() public {
        TronUsdtLike usdt = new TronUsdtLike();
        usdt.mint(address(s), 100e6);
        vm.prank(alice);
        s.send(address(usdt), carol, 40e6);
        assertEq(usdt.balanceOf(carol), 40e6);
        assertEq(s.tokenBalance(address(usdt)), 60e6);
    }

    function test_no_return_value_token_works() public {
        NoReturnToken t = new NoReturnToken();
        t.mint(address(s), 10);
        vm.prank(bob);
        s.send(address(t), carol, 7);
        assertEq(t.balanceOf(carol), 7);
    }

    function test_token_that_moves_nothing_is_rejected() public {
        LyingToken t = new LyingToken();
        t.mint(address(s), 10);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(ApprovedSender.TransferFailed.selector, address(t)));
        s.send(address(t), carol, 5);
    }

    function _armedToken() internal returns (ReentrantToken t) {
        t = new ReentrantToken();
        t.mint(address(s), 100);
        t.mint(alice, 100);
        vm.prank(alice);
        s.approveWallet(address(t)); // worst case: even an approved token cannot re-enter
    }

    function test_reentrancy_blocked_on_send() public {
        ReentrantToken t = _armedToken();
        t.arm(address(s), abi.encodeCall(ApprovedSender.send, (address(t), carol, 5)));
        vm.prank(alice);
        vm.expectRevert(ApprovedSender.Reentrancy.selector);
        s.send(address(t), carol, 5);
    }

    function test_reentrancy_blocked_on_send_batch() public {
        ReentrantToken t = _armedToken();
        address[] memory to = new address[](1);
        uint256[] memory am = new uint256[](1);
        to[0] = carol; am[0] = 5;
        t.arm(address(s), abi.encodeCall(ApprovedSender.sendBatch, (address(t), to, am)));
        vm.prank(alice);
        vm.expectRevert(ApprovedSender.Reentrancy.selector);
        s.sendBatch(address(t), to, am);
    }

    function test_reentrancy_blocked_on_send_from_self() public {
        ReentrantToken t = _armedToken();
        t.arm(address(s), abi.encodeCall(ApprovedSender.send, (address(t), carol, 5)));
        vm.prank(alice);
        t.approve(address(s), 5);
        vm.prank(alice);
        vm.expectRevert(ApprovedSender.Reentrancy.selector);
        s.sendFromSelf(address(t), carol, 5);
    }

    function test_token_taking_more_than_amount_is_rejected() public {
        OverdebitToken t = new OverdebitToken();
        t.mint(address(s), 10);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(ApprovedSender.TransferFailed.selector, address(t)));
        s.send(address(t), carol, 5);
    }

    function test_balance_increase_gives_transfer_failed_not_panic() public {
        BalanceUpToken t = new BalanceUpToken();
        t.mint(address(s), 10);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(ApprovedSender.TransferFailed.selector, address(t)));
        s.send(address(t), carol, 5);
    }

    function test_approved_wallets_list_tracks_changes() public {
        vm.startPrank(alice);
        s.approveWallet(carol);
        s.removeWallet(alice); // swap-and-pop from the front
        vm.stopPrank();
        address[] memory w = s.approvedWallets();
        assertEq(w.length, 2);
        assertEq(s.approvedCount(), 2);
        assertTrue((w[0] == carol && w[1] == bob) || (w[0] == bob && w[1] == carol));
        vm.prank(bob);
        s.approveWallet(alice); // can be approved again after removal
        assertTrue(s.isApproved(alice));
        assertEq(s.approvedWallets().length, 3);
    }

    // ------------------------------------------------------------ batch

    function test_batch_send() public {
        address[] memory to = new address[](3);
        uint256[] memory am = new uint256[](3);
        to[0] = carol; am[0] = 1e6;
        to[1] = mallory; am[1] = 2e6;
        to[2] = carol; am[2] = 3e6;
        vm.prank(bob);
        s.sendBatch(address(token), to, am);
        assertEq(token.balanceOf(carol), 4e6);
        assertEq(token.balanceOf(mallory), 2e6);
        assertEq(s.tokenBalance(address(token)), 994e6);
    }

    function test_batch_is_all_or_nothing() public {
        address[] memory to = new address[](2);
        uint256[] memory am = new uint256[](2);
        to[0] = carol; am[0] = 1e6;
        to[1] = address(0); am[1] = 1e6;
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(ApprovedSender.BadRecipient.selector, address(0)));
        s.sendBatch(address(token), to, am);
        assertEq(token.balanceOf(carol), 0);
    }

    function test_batch_checks_lengths_and_access() public {
        vm.startPrank(bob);
        vm.expectRevert(ApprovedSender.EmptyList.selector);
        s.sendBatch(address(token), new address[](0), new uint256[](0));
        vm.expectRevert(ApprovedSender.LengthMismatch.selector);
        s.sendBatch(address(token), new address[](2), new uint256[](1));
        vm.stopPrank();
        vm.prank(mallory);
        vm.expectRevert(abi.encodeWithSelector(ApprovedSender.NotApproved.selector, mallory));
        s.sendBatch(address(token), new address[](1), new uint256[](1));
    }

    // ------------------------------------------------------------ send own tokens

    function test_send_from_self_moves_only_callers_tokens() public {
        token.mint(alice, 50e6);
        vm.prank(alice);
        token.approve(address(s), 50e6);
        vm.expectEmit(true, true, true, true);
        emit SentFromSelf(address(token), alice, carol, 20e6);
        vm.prank(alice);
        s.sendFromSelf(address(token), carol, 20e6);
        assertEq(token.balanceOf(alice), 30e6);
        assertEq(token.balanceOf(carol), 20e6);
        assertEq(s.tokenBalance(address(token)), 1_000e6); // contract funds untouched
    }

    function test_send_from_self_needs_allowance_and_approval() public {
        token.mint(alice, 50e6);
        vm.prank(alice);
        vm.expectRevert(bytes("allowance"));
        s.sendFromSelf(address(token), carol, 1);

        // A wallet that gave an allowance but is not approved cannot use the contract.
        token.mint(mallory, 50e6);
        vm.prank(mallory);
        token.approve(address(s), 50e6);
        vm.prank(mallory);
        vm.expectRevert(abi.encodeWithSelector(ApprovedSender.NotApproved.selector, mallory));
        s.sendFromSelf(address(token), carol, 1);
        assertEq(token.balanceOf(mallory), 50e6);

        // An approved wallet cannot use mallory's allowance: sendFromSelf only ever
        // debits the caller, so bob (no allowance of his own) fails and mallory keeps everything.
        vm.prank(bob);
        vm.expectRevert(bytes("allowance"));
        s.sendFromSelf(address(token), carol, 1);
        assertEq(token.balanceOf(mallory), 50e6);
        assertEq(token.allowance(mallory, address(s)), 50e6);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(ApprovedSender.BadRecipient.selector, alice));
        s.sendFromSelf(address(token), alice, 1);
    }

    function test_send_from_self_rejects_token_that_moves_nothing() public {
        LyingToken t = new LyingToken();
        t.mint(alice, 10);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(ApprovedSender.TransferFailed.selector, address(t)));
        s.sendFromSelf(address(t), carol, 5);
    }

    function test_send_from_self_with_false_returning_transfer_from() public {
        FalseFromToken t = new FalseFromToken();
        t.mint(alice, 10);
        vm.prank(alice);
        t.approve(address(s), 10);
        vm.prank(alice);
        s.sendFromSelf(address(t), carol, 4);
        assertEq(t.balanceOf(carol), 4);
        assertEq(t.balanceOf(alice), 6);
    }

    function test_batch_size_is_capped() public {
        uint256 n = s.MAX_BATCH() + 1;
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(ApprovedSender.BatchTooLarge.selector, n));
        s.sendBatch(address(token), new address[](n), new uint256[](n));
    }

    function test_batch_at_cap_works() public {
        uint256 n = s.MAX_BATCH();
        address[] memory to = new address[](n);
        uint256[] memory am = new uint256[](n);
        for (uint256 i = 0; i < n; i++) { to[i] = address(uint160(0x5000 + i)); am[i] = 1e6; }
        vm.prank(bob);
        s.sendBatch(address(token), to, am);
        assertEq(s.tokenBalance(address(token)), 1_000e6 - n * 1e6);
    }

    event SentTRX(address indexed by, address indexed to, uint256 amountSun);

    function test_send_trx_stuck_in_contract() public {
        vm.deal(address(s), 5e6); // TRX can arrive without a payable function on TRON
        vm.expectEmit(true, true, false, true);
        emit SentTRX(alice, carol, 2e6);
        vm.prank(alice);
        s.sendTRX(payable(carol), 2e6);
        assertEq(carol.balance, 2e6);
        assertEq(address(s).balance, 3e6);

        vm.prank(mallory);
        vm.expectRevert(abi.encodeWithSelector(ApprovedSender.NotApproved.selector, mallory));
        s.sendTRX(payable(mallory), 1);
        vm.startPrank(alice);
        vm.expectRevert(ApprovedSender.ZeroAmount.selector);
        s.sendTRX(payable(carol), 0);
        vm.expectRevert(abi.encodeWithSelector(ApprovedSender.BadRecipient.selector, address(0)));
        s.sendTRX(payable(address(0)), 1);
        vm.expectRevert(abi.encodeWithSelector(ApprovedSender.TransferFailed.selector, address(0)));
        s.sendTRX(payable(carol), 10e6); // more than held
        vm.stopPrank();
    }

    function test_reentrancy_blocked_on_send_trx() public {
        ReentrantReceiver r = new ReentrantReceiver();
        r.setTarget(address(s));
        vm.prank(alice);
        s.approveWallet(address(r));
        vm.deal(address(s), 5e6);
        // the inner call hits the lock, so the TRX payment fails and the whole call reverts
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(ApprovedSender.TransferFailed.selector, address(0)));
        s.sendTRX(payable(address(r)), 2e6);
        assertEq(address(s).balance, 5e6);
    }

    function test_contract_rejects_direct_trx_calls() public {
        vm.deal(alice, 1e6);
        vm.prank(alice);
        (bool ok, ) = address(s).call{value: 1}("");
        assertFalse(ok);
    }

    // ------------------------------------------------------------ fuzz

    function testFuzz_send_conserves_tokens(uint256 amount, address to) public {
        vm.assume(to != address(0) && to != address(s) && to != address(token));
        amount = bound(amount, 1, 1_000e6);
        uint256 before = token.balanceOf(to);
        vm.prank(alice);
        s.send(address(token), to, amount);
        assertEq(token.balanceOf(to), before + amount);
        assertEq(s.tokenBalance(address(token)), 1_000e6 - amount);
    }

    function testFuzz_only_approved_can_send(address caller) public {
        vm.assume(caller != alice && caller != bob);
        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(ApprovedSender.NotApproved.selector, caller));
        s.send(address(token), caller, 1);
    }
}
