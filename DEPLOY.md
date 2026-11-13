# Deploying ApprovedSender on TRON

You deploy from your own wallet. Nobody else needs your private key or seed phrase. Try everything on the **Nile testnet** first.

## 1. Wallet

1. Install the TronLink browser extension and create or import the wallet that will pay for the deployment. The deployer does **not** become an approved wallet unless you list it.
2. Testnet: in TronLink switch the network to **Nile Testnet** and get free test TRX and test USDT from the Nile faucet: https://nileex.io/join/getJoinPage (linked from TRON's docs). Nile's test USDT (`TXYZopYRdj2D9XRtbG411XZZ3kM5VkAeBf`) is the same `TetherToken` code as mainnet USDT, so it also returns `false` from `transfer()`. Testing on Nile exercises the real path.

## 2. Compile and deploy (TRON IDE, no install needed)

1. Open https://www.tronide.io, create `ApprovedSender.sol` and paste the contents of `src/ApprovedSender.sol`.
2. Compiler: 0.8.20 or newer 0.8.x (we compiled with TRON's `tv_0.8.20`, `tv_0.8.25` and `tv_0.8.31`, no errors or warnings), optimization on, 200 runs. Before you pick, check that Tronscan's "Verify and Publish" page offers the same version. Compile.
3. Deploy with TronLink as the environment, contract `ApprovedSender`.
   Constructor argument `initialWallets`: a JSON array, e.g. `["TXXXX...","TYYYY..."]`. If the IDE rejects base58 addresses, use the hex form: in TronWeb `tronWeb.address.toHex("T...")` gives `41` + 40 hex characters; drop the `41` and write `0x` + the 40 characters.
4. Set a fee limit of 150 TRX (TronWeb's default) and keep at least 150 TRX on the deployer. Simulated deployments of this contract used about 0.8-0.9 million energy. At today's energy price that is roughly 80-90 TRX burned if you have no staked or rented energy, plus a few TRX of bandwidth. Leave "consume user resource percent" at 100 so each caller pays for their own calls. Confirm in TronLink.
5. Copy the contract address from the deployment result or from Tronscan.

## 3. Use it

- **Fund the contract:** send USDT (or another standard TRC20) to the contract address with a normal transfer.
- **Amounts are in the token's smallest unit.** USDT has 6 decimals: 1 USDT = `1000000`, 25.5 USDT = `25500000`.
- `send(token, to, amount)`: token = the TRC20 contract address (mainnet USDT is `TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t`).
- `sendFromSelf(token, to, amount)`: first call `approve(<ApprovedSender address>, amount)` on the token contract from the same wallet.
- `approveWallet(address)` / `removeWallet(address)`: from any approved wallet.
- Every call costs energy; keep some TRX (or staked energy) on each approved wallet.

## 4. Mainnet

Repeat step 2 with TronLink on **Mainnet**. Then verify the source on Tronscan (contract page → Contract → Verify and Publish) with the same compiler version, optimizer settings (on, 200 runs) and EVM version you deployed with, so anyone can read the code.

## Energy costs (approximate, from simulations on TRON, Nov 2026)

USDT has TRON's maximum dynamic-energy surcharge, so every call into USDT costs about 4.4× its base energy.

| Call | Energy | About, if burned as TRX |
|---|---|---|
| Direct USDT transfer (for comparison), recipient already holds USDT | ~64,000 | 6.4 TRX |
| Direct USDT transfer to a new address | ~130,000 | 13 TRX |
| `send` of USDT, recipient already holds USDT | ~87,000 | 8.7 TRX |
| `send` of USDT to a new address | ~153,000 | 15.3 TRX |

A fee limit of 30 TRX is safe for one `send` of USDT. For `sendBatch`, budget about 16 TRX per recipient (at most 100 per batch). Staking or renting energy makes all of this much cheaper. The overhead compared with a direct transfer comes from the re-entrancy lock (~10k energy) and the two balance checks (~9k).

These numbers come from `triggerconstantcontract` simulations, not from a live deployment. Check them on Nile first.
