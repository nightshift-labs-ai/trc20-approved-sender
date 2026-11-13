// SPDX-License-Identifier: MIT
pragma solidity >=0.8.6 <0.9.0;

import "forge-std/Test.sol";
import "../src/ApprovedSender.sol";

/// Random approve/remove calls by random wallets; the counter must always match the
/// real list and must never reach zero.
contract ListHandler is Test {
    ApprovedSender public s;
    address[] public pool;

    constructor(ApprovedSender _s, address[] memory _pool) {
        s = _s;
        pool = _pool;
    }

    // No pre-checks: every call goes to the contract, so the contract's own rules
    // (not the handler) must keep the list valid. Expected reverts are swallowed.
    function approve(uint256 by, uint256 who) external {
        address caller = pool[by % pool.length];
        address w = pool[who % pool.length];
        vm.prank(caller);
        try s.approveWallet(w) {} catch {}
    }

    function remove(uint256 by, uint256 who) external {
        address caller = pool[by % pool.length];
        address w = pool[who % pool.length];
        vm.prank(caller);
        try s.removeWallet(w) {} catch {}
    }

    function poolLength() external view returns (uint256) { return pool.length; }
}

contract ListInvariantTest is Test {
    ApprovedSender s;
    ListHandler h;

    function setUp() public {
        address[] memory pool = new address[](6);
        for (uint256 i = 0; i < 6; i++) pool[i] = address(uint160(0x1000 + i));
        address[] memory init = new address[](1);
        init[0] = pool[0];
        s = new ApprovedSender(init);
        h = new ListHandler(s, pool);
        targetContract(address(h));
    }

    function invariant_count_matches_list_and_never_zero() public view {
        uint256 n;
        for (uint256 i = 0; i < h.poolLength(); i++) if (s.isApproved(h.pool(i))) n++;
        assertEq(n, s.approvedCount());
        assertGt(n, 0);
        address[] memory w = s.approvedWallets();
        assertEq(w.length, n);
        for (uint256 i = 0; i < w.length; i++) assertTrue(s.isApproved(w[i]));
    }
}
