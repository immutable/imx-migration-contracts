/**
 * End-to-end flow against the deployed Immutable X bridge on a mainnet fork:
 * derive → register → withdraw, using the same library calls as the web page.
 *
 * Pending withdrawals for test wallets are written directly into the bridge's
 * `pendingWithdrawals` mapping; everything else is the live mainnet state.
 */
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from "vitest";
import { Contract, JsonRpcProvider, Wallet, keccak256, parseEther, toUtf8Bytes, zeroPadValue } from "ethers";
import {
  BRIDGE_ADDRESS,
  TOKENS,
  checkDeployment,
  classify,
  getAccountState,
  registerStarkKey,
  withdrawAsset,
} from "../../src/lib/bridge.js";
import { deriveAccounts } from "../../src/lib/session.js";
import {
  LEGACY_KEY_MESSAGE,
  deriveStarkKeyCandidates,
} from "../../src/lib/derivation.js";
import { signRegistration } from "../../src/lib/registration.js";
import {
  IMPLEMENTATION_SLOT,
  forkRpcUrl,
  fundedWallet,
  revert,
  setPendingWithdrawal,
  snapshot,
  startAnvil,
  type Anvil,
} from "./anvil.js";

const ETH = TOKENS.find((t) => t.symbol === "ETH")!;
const USDC = TOKENS.find((t) => t.symbol === "USDC")!;
/** Quanta from config/operate/mainnet/imx_tokens.json. */
const ETH_QUANTUM = 10n ** 8n;
const USDC_QUANTUM = 1n;

/** Account from the support ticket that prompted this tool: 0.45 ETH pending, key unregistered. */
const TICKET_STARK_KEY = 280792449106583330515328341059174390612693624277076071221407349784231745237n;
const TICKET_ETH_ADDRESS = "0x429e8C0B0E92b80d84E3cc017f4e6D2D01B91dEa";

const ERC20 = ["function balanceOf(address) view returns (uint256)"];

function privateKeyFor(label: string, i: number): string {
  return keccak256(toUtf8Bytes(`${label}-${i}`));
}

/** First deterministic wallet whose derivation yields `count` distinct candidates. */
async function walletWithCandidates(count: number): Promise<string> {
  for (let i = 0; i < 5000; i++) {
    const key = privateKeyFor("fork-wallet", i);
    const wallet = new Wallet(key);
    const sig = await wallet.signMessage(LEGACY_KEY_MESSAGE);
    if (deriveStarkKeyCandidates(wallet.address, sig).length === count) return key;
  }
  throw new Error(`No wallet with ${count} candidates found`);
}

describe.skipIf(!forkRpcUrl)("mainnet fork", () => {
  let anvil: Anvil;
  let provider: JsonRpcProvider;
  let snap: string;

  beforeAll(async () => {
    anvil = await startAnvil(forkRpcUrl);
    provider = anvil.provider;
  }, 60_000);

  afterAll(() => anvil?.stop());

  beforeEach(async () => {
    snap = await snapshot(provider);
  });

  afterEach(async () => {
    await revert(provider, snap);
  });

  it("recognises the deployed bridge", async () => {
    expect(await checkDeployment(provider)).toEqual([]);
  });

  it("rejects a bridge whose implementation has changed", async () => {
    await provider.send("anvil_setStorageAt", [
      BRIDGE_ADDRESS,
      IMPLEMENTATION_SLOT,
      zeroPadValue("0x000000000000000000000000000000000000dEaD", 32),
    ]);
    const problems = await checkDeployment(provider);
    expect(problems).toHaveLength(1);
    expect(problems[0]).toMatch(/implementation/);
  });

  it("reports the support-ticket account as funded and unregistered", async () => {
    const state = await getAccountState(provider, TICKET_STARK_KEY);
    expect(state.registeredTo).toBeNull();
    expect(state.balances).toEqual([{ token: ETH, amount: parseEther("0.45"), decimals: 18 }]);
    expect(classify(state, TICKET_ETH_ADDRESS)).toEqual({ kind: "needs-registration" });
  });

  it("registers and withdraws ETH and an ERC-20 for a typical account", async () => {
    const wallet = await fundedWallet(provider, await walletWithCandidates(1));
    const [account] = await deriveAccounts(wallet);

    const ethAmount = parseEther("0.3");
    const usdcAmount = 12_500_000n; // 12.5 USDC
    await setPendingWithdrawal(provider, account.starkKey, ETH.assetType, ethAmount / ETH_QUANTUM);
    await setPendingWithdrawal(provider, account.starkKey, USDC.assetType, usdcAmount / USDC_QUANTUM);

    const before = await getAccountState(provider, account.starkKey);
    expect(classify(before, wallet.address)).toEqual({ kind: "needs-registration" });
    expect(before.balances.map((b) => [b.token.symbol, b.amount])).toEqual([
      ["ETH", ethAmount],
      ["USDC", usdcAmount],
    ]);

    await registerStarkKey(wallet, account.starkKey, account.registrationSignature);
    const registered = await getAccountState(provider, account.starkKey);
    expect(registered.registeredTo).toBe(wallet.address);
    expect(classify(registered, wallet.address)).toEqual({ kind: "ready-to-withdraw" });

    const usdc = new Contract(USDC.address!, ERC20, provider);
    const usdcBefore: bigint = await usdc.balanceOf(wallet.address);
    const ethBefore = await provider.getBalance(wallet.address);

    const ethTx = await withdrawAsset(wallet, account.starkKey, ETH);
    const receipt = (await provider.getTransactionReceipt(ethTx))!;
    const gas = receipt.gasUsed * receipt.gasPrice;
    expect(await provider.getBalance(wallet.address)).toBe(ethBefore + ethAmount - gas);

    await withdrawAsset(wallet, account.starkKey, USDC);
    expect(await usdc.balanceOf(wallet.address)).toBe(usdcBefore + usdcAmount);

    const after = await getAccountState(provider, account.starkKey);
    expect(after.balances).toEqual([]);
    expect(classify(after, wallet.address)).toEqual({ kind: "no-funds" });
  }, 60_000);

  it("finds and recovers funds held by a non-primary candidate key", async () => {
    const wallet = await fundedWallet(provider, await walletWithCandidates(3));
    const accounts = await deriveAccounts(wallet);
    expect(accounts).toHaveLength(3);

    const funded = accounts.find((a) => a.variants.includes("secp-bound"))!;
    expect(funded.variants).not.toContain("primary");
    await setPendingWithdrawal(provider, funded.starkKey, ETH.assetType, parseEther("0.01") / ETH_QUANTUM);

    const states = await Promise.all(accounts.map((a) => getAccountState(provider, a.starkKey)));
    const statuses = states.map((s) => classify(s, wallet.address).kind);
    expect(statuses.filter((k) => k === "needs-registration")).toHaveLength(1);
    expect(states[statuses.indexOf("needs-registration")].starkKey).toBe(funded.starkKey);

    await registerStarkKey(wallet, funded.starkKey, funded.registrationSignature);
    await withdrawAsset(wallet, funded.starkKey, ETH);
    expect((await getAccountState(provider, funded.starkKey)).balances).toEqual([]);
  }, 60_000);

  it("rejects a registration signature submitted from a different wallet", async () => {
    const owner = await fundedWallet(provider, await walletWithCandidates(1));
    const attacker = await fundedWallet(provider, privateKeyFor("attacker", 0));
    const [account] = await deriveAccounts(owner);

    await expect(registerStarkKey(attacker, account.starkKey, account.registrationSignature)).rejects.toThrow(
      /INVALID_STARK_SIGNATURE/,
    );
    expect((await getAccountState(provider, account.starkKey)).registeredTo).toBeNull();
  }, 60_000);

  it("refuses to register or withdraw for a key registered to another address", async () => {
    const ownerKey = await walletWithCandidates(1);
    const owner = await fundedWallet(provider, ownerKey);
    const other = await fundedWallet(provider, privateKeyFor("other", 0));
    const sig = await owner.signMessage(LEGACY_KEY_MESSAGE);
    const [candidate] = deriveStarkKeyCandidates(owner.address, sig);

    // Register the owner's Stark key to `other` directly, as an earlier registration would have.
    const toOther = signRegistration(candidate.privateKey, other.address);
    await registerStarkKey(other, toOther.starkKey, toOther.signature);
    await setPendingWithdrawal(provider, toOther.starkKey, ETH.assetType, 1n);

    const [account] = await deriveAccounts(owner);
    const state = await getAccountState(provider, account.starkKey);
    expect(classify(state, owner.address)).toEqual({ kind: "registered-elsewhere", registeredTo: other.address });

    await expect(registerStarkKey(owner, account.starkKey, account.registrationSignature)).rejects.toThrow(
      /STARK_KEY_UNAVAILABLE/,
    );
    await expect(withdrawAsset(owner, account.starkKey, ETH)).rejects.toThrow(/not the connected wallet/);
  }, 60_000);

  it("refuses to withdraw before registration", async () => {
    const wallet = await fundedWallet(provider, await walletWithCandidates(1));
    const [account] = await deriveAccounts(wallet);
    await setPendingWithdrawal(provider, account.starkKey, ETH.assetType, 1n);
    await expect(withdrawAsset(wallet, account.starkKey, ETH)).rejects.toThrow(/not the connected wallet/);
  }, 60_000);
});

describe("non-mainnet chain", () => {
  let anvil: Anvil;
  beforeAll(async () => {
    anvil = await startAnvil();
  }, 60_000);
  afterAll(() => anvil?.stop());

  it("is rejected before any bridge call", async () => {
    const problems = await checkDeployment(anvil.provider);
    expect(problems).toEqual([expect.stringMatching(/chain 31337/)]);
  });
});
