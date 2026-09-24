/**
 * Drives the built page in headless Chromium against a mainnet fork. A stub
 * EIP-1193 provider stands in for the wallet extension: it signs with a test
 * key in Node and forwards everything else to anvil.
 */
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { fileURLToPath } from "node:url";
import { build, preview, type PreviewServer } from "vite";
import { chromium, type Browser, type Page } from "playwright";
import { Wallet, getBytes, id, keccak256, parseEther, toUtf8Bytes } from "ethers";
import { TOKENS, getAccountState } from "../../src/lib/bridge.js";
import { LEGACY_KEY_MESSAGE, deriveStarkKeyCandidates } from "../../src/lib/derivation.js";
import { starkPublicKey } from "../../src/lib/registration.js";
import { forkRpcUrl, fundedWallet, setPendingWithdrawal, startAnvil, type Anvil } from "../fork/anvil.js";

const root = fileURLToPath(new URL("../..", import.meta.url));
const ETH = TOKENS.find((t) => t.symbol === "ETH")!;
const ETH_QUANTUM = 10n ** 8n;

describe.skipIf(!forkRpcUrl)("web page on a mainnet fork", () => {
  let anvil: Anvil;
  let server: PreviewServer;
  let browser: Browser;
  let origin: string;
  let port: number;

  beforeAll(async () => {
    anvil = await startAnvil(forkRpcUrl);
    await build({ root, logLevel: "silent" });
    port = 4300 + Math.floor(Math.random() * 500);
    // allowedHosts admits the phishing.example alias so the page's own hostname check is what gets tested;
    // Vite's default host check would otherwise reject the request first.
    server = await preview({
      root,
      logLevel: "silent",
      preview: { port, strictPort: true, host: "127.0.0.1", allowedHosts: ["phishing.example"] },
    });
    origin = `http://127.0.0.1:${port}`;
    browser = await chromium.launch({ args: ["--host-resolver-rules=MAP phishing.example 127.0.0.1"] });
  }, 120_000);

  afterAll(async () => {
    await browser?.close();
    await server?.close();
    anvil?.stop();
  });

  /** Stub wallet state; `chainId` overrides the fork's chain when set. */
  interface StubWallet {
    chainId?: string;
    switchRequests: string[];
    /** Number of getWithdrawalBalance eth_calls to fail the way MetaMask reports a failing RPC endpoint. */
    failBalanceCalls?: number;
  }

  const GET_WITHDRAWAL_BALANCE = id("getWithdrawalBalance(uint256,uint256)").slice(0, 10);

  async function openWithWallet(
    wallet: Wallet,
    url: string,
    stub: StubWallet = { switchRequests: [] },
  ): Promise<{ page: Page; requests: string[]; cspErrors: string[] }> {
    const page = await browser.newPage();
    const requests: string[] = [];
    const cspErrors: string[] = [];
    page.on("request", (r) => requests.push(r.url()));
    page.on("console", (m) => {
      if (/Content.Security.Policy/i.test(m.text())) cspErrors.push(m.text());
    });

    const emit = (event: string, payload: unknown) =>
      page.evaluate(([e, p]) => (window as unknown as { __emitWalletEvent(e: string, p: unknown): void }).__emitWalletEvent(e as string, p), [
        event,
        payload,
      ] as const);

    await page.exposeFunction("__walletRpc", async (method: string, params: unknown[]) => {
      switch (method) {
        case "eth_requestAccounts":
          // MetaMask emits accountsChanged when it is unlocked and the site is approved, both before and
          // after the request resolves depending on timing; emit on both sides.
          await emit("accountsChanged", [wallet.address]);
          setTimeout(() => void emit("accountsChanged", [wallet.address]).catch(() => undefined), 300);
          return [wallet.address];
        case "eth_accounts":
          return [wallet.address];
        case "eth_chainId":
          return stub.chainId ?? anvil.provider.send(method, []);
        case "wallet_switchEthereumChain": {
          const { chainId } = params[0] as { chainId: string };
          stub.switchRequests.push(chainId);
          // MetaMask's validation: 0x-prefixed, unpadded, non-zero hexadecimal.
          if (!/^0x[1-9a-f][0-9a-f]*$/.test(chainId)) {
            throw new Error(`Expected 0x-prefixed, unpadded, non-zero hexadecimal string 'chainId'. Received: ${chainId}`);
          }
          stub.chainId = undefined;
          // MetaMask resolves the request first and emits chainChanged afterwards.
          setTimeout(() => void emit("chainChanged", chainId).catch(() => undefined), 300);
          return null;
        }
        case "eth_call": {
          const call = params[0] as { data?: string };
          if (stub.failBalanceCalls && call.data?.startsWith(GET_WITHDRAWAL_BALANCE)) {
            stub.failBalanceCalls--;
            return {
              __rpcError: {
                code: -32603,
                message: "Internal JSON-RPC error.",
                data: { code: -32603, message: "failed to get storage for 0x5FDCCA… HTTP error 403" },
              },
            };
          }
          return anvil.provider.send(method, params);
        }
        case "personal_sign":
          return wallet.signMessage(getBytes(params[0] as string));
        case "eth_sendTransaction": {
          const tx = params[0] as { to: string; data: string; value?: string };
          const sent = await wallet.sendTransaction({ to: tx.to, data: tx.data, value: tx.value ?? 0 });
          return sent.hash;
        }
        default:
          return anvil.provider.send(method, params ?? []);
      }
    });
    await page.addInitScript(() => {
      const rpc = (window as unknown as { __walletRpc: (m: string, p: unknown[]) => Promise<unknown> }).__walletRpc;
      const listeners: Record<string, ((payload: unknown) => void)[]> = {};
      (window as unknown as { __emitWalletEvent(e: string, p: unknown): void }).__emitWalletEvent = (e, p) =>
        (listeners[e] ?? []).forEach((h) => h(p));
      (window as unknown as { ethereum: unknown }).ethereum = {
        request: async ({ method, params }: { method: string; params?: unknown[] }) => {
          const result = (await rpc(method, params ?? [])) as { __rpcError?: object } | null;
          if (result && typeof result === "object" && "__rpcError" in result) throw result.__rpcError;
          return result;
        },
        on: (event: string, handler: (payload: unknown) => void) => (listeners[event] ??= []).push(handler),
      };
    });
    await page.goto(url);
    return { page, requests, cspErrors };
  }

  async function acceptDisclaimers(page: Page) {
    const boxes = page.locator("section").first().locator('input[type="checkbox"]');
    const continueButton = page.getByRole("button", { name: "Continue" });
    expect(await boxes.count()).toBe(4);
    for (let i = 0; i < 3; i++) await boxes.nth(i).check();
    await expect.poll(() => continueButton.isDisabled()).toBe(true);
    await boxes.nth(3).check();
    await continueButton.click();
  }

  it("registers the Stark key and withdraws to the connected wallet", async () => {
    const wallet = await fundedWallet(anvil.provider, keccak256(toUtf8Bytes("e2e-wallet")));
    const candidates = deriveStarkKeyCandidates(wallet.address, await wallet.signMessage(LEGACY_KEY_MESSAGE));
    expect(candidates).toHaveLength(1);
    const starkKey = starkPublicKey(candidates[0].privateKey).x;
    await setPendingWithdrawal(anvil.provider, starkKey, ETH.assetType, parseEther("0.3") / ETH_QUANTUM);

    const { page, requests, cspErrors } = await openWithWallet(wallet, `${origin}/`);
    const ackBoxes = page.locator("section").first().locator('input[type="checkbox"]');
    await acceptDisclaimers(page);

    await page.getByRole("button", { name: "Connect wallet" }).click();
    await page.getByText(`Connected: ${wallet.address}`).waitFor();
    // The accountsChanged emitted while connecting did not reload the page.
    for (let i = 0; i < 4; i++) expect(await ackBoxes.nth(i).isChecked()).toBe(true);

    await page.getByRole("button", { name: "Sign and derive my Stark key" }).click();
    await page.getByText(starkKey.toString(), { exact: true }).waitFor();
    await page.getByText("0.3 ETH", { exact: true }).waitFor();

    const register = page.getByRole("button", { name: "Register Stark key" });
    expect(await register.isDisabled()).toBe(true);
    await page.getByText("is my wallet and I want these withdrawals sent to it").click();
    await register.click();
    await page.getByText("Stark key registered to").waitFor();

    const before = await anvil.provider.getBalance(wallet.address);
    await page.getByRole("button", { name: "Withdraw 0.3 ETH" }).click();
    await page.getByText(`Withdrew 0.3 ETH to ${wallet.address}.`).waitFor();
    expect(await anvil.provider.getBalance(wallet.address)).toBeGreaterThan(before + parseEther("0.29"));

    const state = await getAccountState(anvil.provider, starkKey);
    expect(state.registeredTo).toBe(wallet.address);
    expect(state.balances).toEqual([]);
    await page.getByText("No pending withdrawals found for this wallet.").waitFor();

    // Every request the page made was for its own files.
    expect(requests.every((u) => u.startsWith(origin))).toBe(true);
    expect(cspErrors).toEqual([]);
    await page.close();
  }, 120_000);

  it("reports no funds for a wallet without pending withdrawals", async () => {
    const wallet = await fundedWallet(anvil.provider, keccak256(toUtf8Bytes("e2e-empty-wallet")));
    const { page } = await openWithWallet(wallet, `${origin}/`);
    await acceptDisclaimers(page);
    await page.getByRole("button", { name: "Connect wallet" }).click();
    await page.getByRole("button", { name: "Sign and derive my Stark key" }).click();
    await page.getByText("No pending withdrawals found for this wallet.").waitFor();
    expect(await page.getByRole("button", { name: "Register Stark key" }).count()).toBe(0);
    expect(await page.getByText("Ethereum Mainnet only", { exact: true }).count()).toBe(1);
    await page.getByText(/^Checked for pending withdrawals of: APE, BR, .*ETH.*WAGMI\./).waitFor();
    await page.close();
  }, 120_000);

  it("switches a wallet on another chain to Ethereum Mainnet", async () => {
    const wallet = await fundedWallet(anvil.provider, keccak256(toUtf8Bytes("e2e-wrong-chain")));
    // 13371 is Immutable zkEVM mainnet.
    const stub: StubWallet = { chainId: "0x343b", switchRequests: [] };
    const { page, cspErrors } = await openWithWallet(wallet, `${origin}/`, stub);
    await acceptDisclaimers(page);

    await page.getByRole("button", { name: "Connect wallet" }).click();
    await page.getByText("Wallet is connected to chain 13371; switch it to Ethereum Mainnet (chain 1).").waitFor();

    await page.getByRole("button", { name: "Switch wallet to Ethereum Mainnet" }).click();
    await expect.poll(() => stub.switchRequests).toEqual(["0x1"]);

    // The switch handler reconnects; the chainChanged that follows neither reloads nor renders the step twice.
    await page.getByText(`Connected: ${wallet.address}`).waitFor();
    await page.waitForTimeout(800);
    expect(await page.getByText("Could not switch network").count()).toBe(0);
    expect(await page.getByRole("heading", { name: "3. Derive your Stark key" }).count()).toBe(1);
    const ackBoxes = page.locator("section").first().locator('input[type="checkbox"]');
    for (let i = 0; i < 4; i++) expect(await ackBoxes.nth(i).isChecked()).toBe(true);
    expect(cspErrors).toEqual([]);
    await page.close();
  }, 60_000);

  it("resets only when the connected account or network changes", async () => {
    const wallet = await fundedWallet(anvil.provider, keccak256(toUtf8Bytes("e2e-account-change")));
    const { page } = await openWithWallet(wallet, `${origin}/`);
    const emitEvent = (e: string, p: unknown) =>
      page.evaluate(([ev, pl]) => (window as unknown as { __emitWalletEvent(e: string, p: unknown): void }).__emitWalletEvent(ev as string, pl), [e, p] as const);
    await acceptDisclaimers(page);
    await page.getByRole("button", { name: "Connect wallet" }).click();
    await page.getByText(`Connected: ${wallet.address}`).waitFor();

    // The same account again (as wallets emit on unlock) keeps the page state.
    await emitEvent("accountsChanged", [wallet.address.toLowerCase()]);
    await page.waitForTimeout(300);
    expect(await page.getByText(`Connected: ${wallet.address}`).count()).toBe(1);

    // A chainChanged to mainnet while connected on mainnet keeps the page state.
    await emitEvent("chainChanged", "0x1");
    await page.waitForTimeout(300);
    expect(await page.getByText(`Connected: ${wallet.address}`).count()).toBe(1);

    // A different account reloads the page back to the acknowledgements.
    await Promise.all([page.waitForEvent("load"), emitEvent("accountsChanged", [Wallet.createRandom().address])]);
    await page.getByRole("button", { name: "Continue" }).waitFor();
    expect(await page.getByRole("button", { name: "Connect wallet" }).count()).toBe(0);
    expect(await page.locator('input[type="checkbox"]').first().isChecked()).toBe(false);

    // Moving off mainnet after connecting also resets.
    await acceptDisclaimers(page);
    await page.getByRole("button", { name: "Connect wallet" }).click();
    await page.getByText(`Connected: ${wallet.address}`).waitFor();
    await Promise.all([page.waitForEvent("load"), emitEvent("chainChanged", "0x343b")]);
    await page.getByRole("button", { name: "Continue" }).waitFor();
    await page.close();
  }, 60_000);

  it("explains a failing wallet RPC and recovers on retry", async () => {
    const wallet = await fundedWallet(anvil.provider, keccak256(toUtf8Bytes("e2e-rpc-failure")));
    const stub: StubWallet = { switchRequests: [], failBalanceCalls: 1 };
    const { page } = await openWithWallet(wallet, `${origin}/`, stub);
    await acceptDisclaimers(page);
    await page.getByRole("button", { name: "Connect wallet" }).click();
    await page.getByRole("button", { name: "Sign and derive my Stark key" }).click();

    await page.getByText("Could not read your pending withdrawals from the bridge.").waitFor();
    await page.getByText("failed to get storage for 0x5FDCCA… HTTP error 403").waitFor();
    expect(await page.getByText("missing revert data").count()).toBe(0);

    await page.getByRole("button", { name: "Try again" }).click();
    await page.getByText("No pending withdrawals found for this wallet.").waitFor();
    await page.close();
  }, 60_000);

  it("offers registration without pending withdrawals only with the testing override", async () => {
    const wallet = await fundedWallet(anvil.provider, keccak256(toUtf8Bytes("e2e-override")));
    const candidates = deriveStarkKeyCandidates(wallet.address, await wallet.signMessage(LEGACY_KEY_MESSAGE));
    expect(candidates).toHaveLength(1);
    const starkKey = starkPublicKey(candidates[0].privateKey).x;

    const { page } = await openWithWallet(wallet, `${origin}/?allow-registration-without-funds`);
    await page.getByText("Testing mode: registration without pending withdrawals.").waitFor();
    await acceptDisclaimers(page);
    await page.getByRole("button", { name: "Connect wallet" }).click();
    await page.getByRole("button", { name: "Sign and derive my Stark key" }).click();
    await page.getByText(starkKey.toString(), { exact: true }).waitFor();
    expect(await page.getByText("No pending withdrawals found for this wallet.").count()).toBe(0);

    await page.getByText("is my wallet and I want these withdrawals sent to it").click();
    await page.getByRole("button", { name: "Register Stark key" }).click();
    await page.getByText("Stark key registered to").waitFor();
    await page.getByText("Registered to your connected wallet. No pending withdrawals for this Stark key.").waitFor();
    expect((await getAccountState(anvil.provider, starkKey)).registeredTo).toBe(wallet.address);
    await page.close();
  }, 120_000);

  it("refuses to run when not served from the local machine", async () => {
    const wallet = new Wallet(keccak256(toUtf8Bytes("e2e-hosted-copy")));
    const { page } = await openWithWallet(wallet, `http://phishing.example:${port}/`);
    await page.getByText("Stop. This page is not running on your own computer.").waitFor();
    expect(await page.getByRole("button").count()).toBe(0);
    await page.close();
  }, 60_000);
});
