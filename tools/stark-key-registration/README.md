# Stark Key Registration Tool

A web page that runs on your own computer. It links an Immutable X Stark key to its Ethereum wallet on the Immutable X bridge, then finalises the key's pending withdrawals to that wallet.

It is for users whose `withdraw()` call on the bridge fails with `USER_UNREGISTERED`. See [Finalise Manually Initiated Withdrawals](../../docs/finalise-pending-withdrawals.md) for the full withdrawal guide.

> [!WARNING]
> **This tool has not been independently audited.** It is provided as-is, without warranty of any kind, under the Apache 2.0 licence. You use it at your own risk. Read [Security model](#security-model) before running it.

> [!CAUTION]
> **Only run this tool from source on your own computer.** Immutable does not host this tool on any website. A hosted page that asks you to sign the Immutable X key message is a phishing attempt, whatever domain it is on. Immutable staff will never ask you for a signature, private key, seed phrase or anything this tool displays.

## Contents

- [When you need this tool](#when-you-need-this-tool)
- [Requirements](#requirements)
- [Running the tool](#running-the-tool)
- [What you will be asked to sign](#what-you-will-be-asked-to-sign)
- [Troubleshooting](#troubleshooting)
- [Security model](#security-model)
- [How it works](#how-it-works)
- [Limitations](#limitations)
- [Development](#development)

## When you need this tool

The bridge's `withdraw(ownerKey, assetType)` sends funds to the Ethereum address registered for the Stark key `ownerKey`. Immutable X registered most users off-chain, so for many Stark keys the bridge has no address on record:

- `getEthKey(starkKey)` returns `0x0000000000000000000000000000000000000000`.
- `withdraw` reverts with `USER_UNREGISTERED`.

Registration fixes this, but it needs a signature made with the Stark private key. Immutable X derived that key from a wallet signature, so recovering it needs code. This tool recomputes the key in your browser, signs the registration, and submits it from your wallet.

Stark keys below 2^160 (a Stark key equal to the decimal form of the Ethereum address) need no registration. Such users can follow the [main guide](../../docs/finalise-pending-withdrawals.md) directly.

## Requirements

- [Node.js](https://nodejs.org/) 20 or later, and [git](https://git-scm.com/).
- A browser wallet extension such as MetaMask or Rabby that holds **the Ethereum wallet you used with Immutable X**. A hardware wallet connected through the extension works.
- A small amount of ETH in that wallet for gas: one registration transaction plus one transaction per token withdrawn.

## Running the tool

1. Clone the official repository and open the tool's directory:

   ```bash
   git clone https://github.com/immutable/imx-migration-contracts.git
   cd imx-migration-contracts/tools/stark-key-registration
   ```

2. Install the pinned dependencies exactly as locked. `--omit=dev` skips the test tooling, which running the page does not need:

   ```bash
   npm ci --omit=dev
   ```

3. Build and start the page:

   ```bash
   npm start
   ```

4. Open <http://127.0.0.1:4173> in the browser that has your wallet extension. The address bar must show `127.0.0.1` or `localhost`; the page refuses to run anywhere else.

5. Follow the four steps on the page:
   1. **Before you start.** Read the warnings and tick each acknowledgement.
   2. **Connect your wallet.** The page checks that the wallet is on Ethereum Mainnet and that the bridge is running the expected implementation.
   3. **Derive your Stark key.** Sign the Immutable X key message (no gas). The page shows your Stark key and any pending withdrawals.
   4. **Register and withdraw.** Register the Stark key to your connected wallet (one transaction), then withdraw each token (one transaction each).

6. Stop the server with `Ctrl+C` when you are done.

## What you will be asked to sign

| Step | Wallet prompt | Details to check in your wallet |
| --- | --- | --- |
| Derive | Sign a message | Text is exactly `Only sign this request if you’ve initiated an action with Immutable X.` No gas. |
| Register | Transaction | To `0x5FDCCA53617f4d2b9134B29090C87D01058e27e9` (Immutable X bridge), function `registerSender`, value 0 ETH. |
| Withdraw | Transaction, one per token | To `0x5FDCCA53617f4d2b9134B29090C87D01058e27e9`, function `withdraw`, value 0 ETH. |

Reject any prompt that does not match this table.

## Troubleshooting

| Message on the page | Meaning and next step |
| --- | --- |
| No pending withdrawals found for this wallet | The withdrawals were already finalised, or the connected wallet is not the one used with Immutable X. If support gave you a Stark key, compare it with the key the page shows. If it differs, connect a different wallet. |
| Already registered to `0x…` | The Stark key is linked to that address, and the link cannot be changed. If that address is yours, connect it instead. Otherwise contact Immutable support through the official support site. |
| Wallet is connected to chain … | Switch the wallet to Ethereum Mainnet. The page reloads when the network changes. |
| Bridge implementation is …, expected … | The bridge has been upgraded since this version of the tool. Do not continue. Pull the latest version of the repository or contact Immutable support. |
| Registration simulation failed / Withdrawal simulation failed | The transaction would revert, so it was not sent. The revert reason follows the message. |

## Security model

What the tool does to limit risk, and what it cannot do for you.

**Keys and signatures stay in the browser tab.**

- The Stark private key is computed inside one function, used to sign the registration payload, then discarded.
- The key is never displayed, stored, logged or transmitted.
- The page's Content-Security-Policy blocks all network requests (`connect-src 'none'`). Chain reads and transactions go through your wallet extension.
- The end-to-end test asserts that the page requests nothing but its own files.

**Funds can only go to the connected wallet.**

- The registration signature covers the connected wallet's address, and the page submits it with `registerSender`. The contract then uses the transaction sender as the owner.
- A signature submitted from any other wallet fails verification (`INVALID_STARK_SIGNATURE`). The fork tests cover this case.
- The page offers withdrawals only for Stark keys registered to the connected wallet.

**Every transaction is simulated before it is sent.** A transaction that would revert is not submitted.

**The page checks its environment.** It stops on any chain other than Ethereum Mainnet, and when the bridge proxy points to an implementation other than `0x273b65a7231321D4ee47a4c47408Ef43517455Ec` (StarkExchangeMigrationV2).

**The page refuses to run unless loaded from `127.0.0.1` or `localhost`.** Someone who copies the code can remove this check. The real protection is to run the tool only from the official repository.

**Dependencies are pinned** to exact versions in `package-lock.json`, and `npm ci` installs exactly those. The page bundles four libraries:

- `ethers`: ABI encoding and the wallet connection.
- `@scure/bip32`: BIP32 derivation.
- `@scure/starknet`: Stark curve keys and ECDSA.
- `@noble/hashes`: SHA-256.

`vite` builds and serves the page. `npm ci --omit=dev` installs nothing else. `@imtbl/core-sdk` is a development dependency, used only by the tests as the reference implementation.

The tool does not protect against a compromised computer, browser or wallet extension, or against approving a wallet prompt that does not match [the table above](#what-you-will-be-asked-to-sign).

## How it works

1. **Wallet signature.** The wallet signs `Only sign this request if you’ve initiated an action with Immutable X.`, the message the Immutable X SDK used to create Stark keys.
2. **Key derivation.** The signature's `s` value seeds a BIP32 key at `m/2645'/<starkex>'/<immutablex>'/<address bits>'/<address bits>'/1`. SHA-256 grinding then turns that key into a Stark private key. This is the procedure of `generateLegacyStarkPrivateKey` in `@imtbl/core-sdk` 3.6.1, reimplemented in `src/lib/derivation.ts`.
3. **Candidate keys.** For about 1 in 30 wallets the first grinding round is rejected, and the SDK's three grinding variants then give different keys.
   - The SDK chose between them by asking the Immutable X API, which has been retired.
   - The tool computes every candidate and uses the one that holds pending withdrawals on the bridge.
   - Every candidate comes from the wallet's own signature, so every candidate belongs to the wallet owner.
4. **Registration.** The Stark key signs `keccak256(abi.encodePacked("UserRegistration:", wallet, starkKey)) mod EC_ORDER`. The page submits `registerSender(starkKey, abi.encode(r, s, starkKeyY))` from the wallet. See `registerEthAddress` in `src/bridge/starkex/LegacyStarkExchangeBridge.sol`.
5. **Withdrawal.** The page calls `withdraw(starkKey, assetType)` for each token with a pending balance.

## Limitations

- Ethereum Mainnet only. The Sepolia bridge does not have `registerSender`.
- Covers Stark keys derived from an Ethereum wallet signature, which is how the Immutable X SDK and Link created them. Keys created another way (for example, custodial accounts) are not found.
- Covers the fungible tokens in `config/operate/mainnet/imx_tokens.json`. The bridge's `withdraw` does not support NFTs.
- `window.ethereum` is used as the wallet. With several wallet extensions installed, the page talks to whichever one claims `window.ethereum`. Disable the others if the wrong one responds.

## Development

```bash
npm ci
npm run typecheck
npm test                                        # unit tests
ETH_RPC_URL=<mainnet RPC> npm run test:fork      # anvil fork of mainnet
ETH_RPC_URL=<mainnet RPC> npm run test:e2e       # built page in headless Chromium on a fork
```

`test:fork` and `test:e2e` need [Foundry](https://book.getfoundry.sh/)'s `anvil` on `PATH`. `test:e2e` also needs Playwright's Chromium (`npx playwright install chromium`). Both suites are skipped when `ETH_RPC_URL` is unset.

| Suite | Covers |
| --- | --- |
| `test/unit/derivation.test.ts` | Derived keys equal `@imtbl/core-sdk`'s `generateLegacyStarkPrivateKey`:<ul><li>typical wallets, with no API call;</li><li>each of the SDK's API-resolved branches for ambiguous wallets (API stubbed with nock), including a wallet with three distinct candidates;</li><li>public keys match the SDK's Stark signer.</li></ul> |
| `test/unit/registration.test.ts` | Message hash matches `abi.encodePacked`. Signatures verify under the SDK's `elliptic` curve, stay within the contract's `r` and `s⁻¹` bounds, and fail for a different address. |
| `test/fork/bridge.fork.test.ts` | Against the deployed bridge:<ul><li>register and withdraw ETH and USDC;</li><li>recover funds held by a non-primary candidate key;</li><li>signature replay from another wallet is rejected;</li><li>keys registered to another address are refused;</li><li>no withdrawal before registration;</li><li>detection of a changed implementation and of a non-mainnet chain;</li><li>the account from the originating support ticket reads as 0.45 ETH pending and unregistered.</li></ul> |
| `test/e2e/page.e2e.test.ts` | Clicks through the built page with a stub wallet, from disclaimers to register to withdraw. Also checks the no-funds path and the hosted-copy block, asserts that the page makes no requests beyond its own files, and that no CSP violations occur. |

Pending withdrawals for test wallets are written into the bridge's `pendingWithdrawals` mapping (storage slot 8) on the fork.

Before release, run the page once by hand with MetaMask and Rabby against a fork or with a funded test account. The end-to-end suite uses a stub provider, not a real extension.
