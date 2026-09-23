/**
 * Starts an anvil fork of Ethereum mainnet for tests that exercise the deployed
 * Immutable X bridge. Requires `anvil` (Foundry) on PATH and ETH_RPC_URL.
 */
import { spawn, type ChildProcess } from "node:child_process";
import { createServer } from "node:net";
import { JsonRpcProvider, Wallet, keccak256, toBeHex, zeroPadValue, concat, parseEther } from "ethers";
import { BRIDGE_ADDRESS } from "../../src/lib/bridge.js";

/** Storage slot of `pendingWithdrawals` in MainStorage (`forge inspect StarkExchangeMigrationV2 storage`). */
const PENDING_WITHDRAWALS_SLOT = 8n;
/** StarkWare proxy implementation slot: keccak256("StarkWare2019.implemntation-slot"). */
export const IMPLEMENTATION_SLOT = "0x177667240aeeea7e35eabe3a35e18306f336219e1386f7710a6bf8783f761b24";

export const forkRpcUrl = process.env.ETH_RPC_URL;

async function freePort(): Promise<number> {
  return new Promise((resolve, reject) => {
    const server = createServer();
    server.listen(0, "127.0.0.1", () => {
      const address = server.address();
      server.close(() => (typeof address === "object" && address ? resolve(address.port) : reject(new Error("no port"))));
    });
  });
}

export interface Anvil {
  url: string;
  provider: JsonRpcProvider;
  stop(): void;
}

export async function startAnvil(forkUrl?: string): Promise<Anvil> {
  const port = await freePort();
  const args = ["--port", String(port), "--host", "127.0.0.1", "--silent"];
  if (forkUrl) args.push("--fork-url", forkUrl);
  const child: ChildProcess = spawn("anvil", args, { stdio: "ignore" });
  const url = `http://127.0.0.1:${port}`;
  const provider = new JsonRpcProvider(url, undefined, { staticNetwork: false, polling: true, pollingInterval: 50 });
  for (let i = 0; ; i++) {
    try {
      await provider.getBlockNumber();
      break;
    } catch {
      if (i > 300) throw new Error("anvil did not start");
      await new Promise((r) => setTimeout(r, 100));
    }
  }
  return { url, provider, stop: () => child.kill() };
}

function mappingSlot(key: bigint, slot: bigint | string): string {
  return keccak256(concat([toBeHex(key, 32), zeroPadValue(toBeHex(slot), 32)]));
}

/** Sets `pendingWithdrawals[starkKey][assetType]` to a quantized amount. */
export async function setPendingWithdrawal(
  provider: JsonRpcProvider,
  starkKey: bigint,
  assetType: bigint,
  quantizedAmount: bigint,
): Promise<void> {
  const slot = mappingSlot(assetType, mappingSlot(starkKey, PENDING_WITHDRAWALS_SLOT));
  await provider.send("anvil_setStorageAt", [BRIDGE_ADDRESS, slot, toBeHex(quantizedAmount, 32)]);
}

export async function fundedWallet(provider: JsonRpcProvider, privateKey: string): Promise<Wallet> {
  const wallet = new Wallet(privateKey, provider);
  await provider.send("anvil_setBalance", [wallet.address, toBeHex(parseEther("1"))]);
  return wallet;
}

export async function snapshot(provider: JsonRpcProvider): Promise<string> {
  return provider.send("evm_snapshot", []);
}

export async function revert(provider: JsonRpcProvider, id: string): Promise<void> {
  await provider.send("evm_revert", [id]);
}
