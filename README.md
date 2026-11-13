# TRC20 Approved Sender

A small TRON smart contract for sending TRC20 tokens (USDT or any other TRC20) between wallet addresses, where:

- only **approved wallets** can send tokens;
- approved wallets can **approve or remove** other wallets;
- nobody, approved or not, can move tokens out of anyone else's wallet.

MIT licensed. Written and tested by Nightshift Labs (an AI-agent-run engineering shop; the engineering is done by an AI agent). Not audited by a third party.

## Functions

| Function | Who can call | What it does |
|---|---|---|
| `constructor(address[] initialWallets)` | deployer | Sets the first approved wallets (at least one, no duplicates, not the zero address or the contract itself). |
| `approveWallet(address wallet)` | approved wallet | Adds a wallet to the approved list. |
| `removeWallet(address wallet)` | approved wallet | Removes a wallet (also yourself). The **last** approved wallet cannot be removed, so at least one address always stays approved. Make sure you control the wallets you keep. |
| `send(address token, address to, uint256 amount)` | approved wallet | Sends tokens **held by this contract** to `to`. |
| `sendBatch(address token, address[] to, uint256[] amounts)` | approved wallet | Several sends in one transaction, all-or-nothing, at most `MAX_BATCH` = 100 recipients (keeps a batch well under TRON's per-transaction CPU limit). |
| `sendFromSelf(address token, address to, uint256 amount)` | approved wallet | Sends the **caller's own** tokens (after `approve(contract, amount)` on the token). It can never touch another wallet's allowance. |
| `sendTRX(address to, uint256 amountSun)` | approved wallet | Sends TRX that ended up in the contract (TRX can arrive with a plain transfer even though the contract has no payable function). |
| `isApproved(address)`, `approvedCount()`, `approvedWallets()`, `tokenBalance(address token)` | anyone | Read-only views (`approvedWallets()` returns the full list). |

To fund the contract, send TRC20 tokens to its address with a normal transfer.

Events: `WalletApproved`, `WalletRemoved`, `Sent`, `SentFromSelf` (indexed for Tronscan / your backend). The `amount` in `Sent`/`SentFromSelf` is what the sender was debited.

## Why the balance check instead of the return value

TRON mainnet USDT (`TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t`) returns `false` from `transfer()` even when the transfer succeeds: in its verified source on Tronscan, `transfer()` in `StandardTokenWithFees` has no `return` statement (`transferFrom()` does return `true`). The LI.FI team describes the same problem in lifinance/contracts PR #1715. This is different from Ethereum USDT, which returns nothing. Contracts that require `true` (for example OpenZeppelin's `SafeERC20.safeTransfer`) reject every USDT `transfer` on TRON. This contract ignores the return value and checks that its own (or the caller's) balance went down by exactly `amount`. A token that reverts, or that reports success without moving funds, makes the call revert.

Tests cover a USDT-style token that returns `false` (on `transfer` and on `transferFrom`), a token with no return value, a token that reports success without moving funds, one that takes more than asked, one whose sender balance goes up, and a token that tries to re-enter `send`, `sendBatch` and `sendFromSelf`.

**Supported tokens:** standard TRC20 and USDT-style tokens. **Not supported** (the call reverts, no funds move): rebasing, reflection and sender-pays-fee tokens, because the sender's balance does not drop by exactly `amount`.

## Tests

Needs [Foundry](https://getfoundry.sh).

```
git clone --recursive https://github.com/nightshift-labs-ai/trc20-approved-sender
cd trc20-approved-sender
forge test
bash script/mutants.sh   # optional: breaks the contract 17 ways, each must fail a test
```

37 tests: access control, wallet-list edge cases, sends, batches, own-token sends, odd tokens, re-entrancy, fuzz tests (2,000 runs each), and an invariant test: 256 runs × 200 random approve/remove calls by random wallets, with no pre-checks in the test handler, so only the contract's own rules keep the list valid. After every call, the count, the list and `isApproved` must agree and at least one wallet must remain.

Every check was also tested by breaking it on purpose: `bash script/mutants.sh` makes 17 changes one at a time and confirms at least one test fails for each. The changes remove each re-entrancy lock, each event, the access check, the last-wallet rule, the self-approval rule, the batch cap, both parts of the balance check and the list bookkeeping.

Compiled without errors or warnings with TRON's own compiler (tronprotocol/solidity `tv_0.8.20`, `tv_0.8.25`, `tv_0.8.31`, optimizer on, 200 runs). The tests run on Foundry's EVM, not on TRON's TVM. Not yet deployed to a TRON network.

## Security notes (read before mainnet)

- **Any single approved wallet can remove all the others** (that is how the job spec defines approved wallets). If one key leaks, the attacker can lock out the rest and empty the contract. For larger balances, ask for an M-of-N version (for example 2 of 3 approvals to add/remove a wallet or to send above a limit).
- TRX sent to the contract by mistake can be sent out again with `sendTRX`. TRC10 tokens sent to it are stuck (TRC10 handling can be added on request).
- The re-entrancy lock costs about 10,000 energy (~1 TRX) per call on TRON, because the TVM has no storage refund. We kept it on purpose.
- Tokens with fees on transfer: the sender is debited `amount`; the recipient gets whatever the token passes on.

## Error codes

TronWeb and Tronscan often show a failed call only as "REVERT opcode executed" or as raw bytes. The first 4 bytes of the revert data tell you which check failed:

| Selector | Error |
|---|---|
| `0x0ca968d8` | `NotApproved(address)` |
| `0x628d229a` | `InvalidWallet(address)` |
| `0xc1034b2c` | `AlreadyApproved(address)` |
| `0xeeec54e3` | `NotInList(address)` |
| `0xcfc69d83` | `LastApprovedWallet()` |
| `0x1f2a2005` | `ZeroAmount()` |
| `0xf66e9048` | `BadRecipient(address)` |
| `0xff633a38` | `LengthMismatch()` |
| `0x615fd3c0` | `EmptyList()` |
| `0x39f1c8d9` | `TransferFailed(address)` |
| `0x8a8b41ec` | `NotAContract(address)` |
| `0xab143c06` | `Reentrancy()` |
| `0xa67b9f9e` | `BatchTooLarge(uint256)` |

Token errors (for example USDT's own checks) are passed through unchanged.

## Deploying on TRON

See [DEPLOY.md](DEPLOY.md). You deploy from your own TronLink wallet; nobody else needs your keys.
