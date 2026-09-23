/**
 * Drives the built page in headless Chromium against a mainnet fork. A stub
 * EIP-1193 provider stands in for the wallet extension: it signs with a test
 * key in Node and forwards everything else to anvil.
 */
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { fileURLToPath } from "node:url";
import { build, preview, type PreviewServer } from "vite";
import { chromium, type Browser, type Page } from "playwright";
import { Wallet, getBytes, keccak256, parseEther, toUtf8Bytes } from "ethers";
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

  async function openWithWallet(wallet: Wallet, url: string): Promise<{ page: Page; requests: string[]; cspErrors: string[] }> {
    const page = await browser.newPage();
    const requests: string[] = [];
    const cspErrors: string[] = [];
    page.on("request", (r) => requests.push(r.url()));
    page.on("console", (m) => {
      if (/Content.Security.Policy/i.test(m.text())) cspErrors.push(m.text());
    });

    await page.exposeFunction("__walletRpc", async (method: string, params: unknown[]) => {
      switch (method) {
        case "eth_requestAccounts":
        case "eth_accounts":
          return [wallet.address];
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
      (window as unknown as { ethereum: unknown }).ethereum = {
        request: ({ method, params }: { method: string; params?: unknown[] }) => rpc(method, params ?? []),
        on: () => undefined,
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
    await acceptDisclaimers(page);

    await page.getByRole("button", { name: "Connect wallet" }).click();
    await page.getByText(`Connected: ${wallet.address}`).waitFor();

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
