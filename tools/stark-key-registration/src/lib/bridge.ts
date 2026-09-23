/**
 * Reads and writes against the Immutable X bridge proxy on Ethereum mainnet.
 * Every write is simulated with eth_call first and only sent if the
 * simulation succeeds.
 */
import { Contract, getAddress, ZeroAddress, type ContractRunner, type Provider, type Signer } from "ethers";
import tokenConfig from "../../../../config/operate/mainnet/imx_tokens.json";

export const MAINNET_CHAIN_ID = 1n;
export const BRIDGE_ADDRESS = "0x5FDCCA53617f4d2b9134B29090C87D01058e27e9";
/** StarkExchangeMigrationV2, the first implementation with `registerSender` (config/deploy/mainnet/eth_deployed.json). */
export const EXPECTED_IMPLEMENTATION = "0x273b65a7231321D4ee47a4c47408Ef43517455Ec";

const BRIDGE_ABI = [
  "function implementation() view returns (address)",
  "function getEthKey(uint256 ownerKey) view returns (address)",
  "function getWithdrawalBalance(uint256 ownerKey, uint256 assetId) view returns (uint256)",
  "function registerSender(uint256 starkKey, bytes starkSignature)",
  "function withdraw(uint256 ownerKey, uint256 assetType)",
];
const ERC20_ABI = ["function decimals() view returns (uint8)"];

export interface Token {
  symbol: string;
  /** StarkEx asset type (`token_int` in the config), taken from `token_hex` to avoid JSON number precision loss. */
  assetType: bigint;
  /** ERC-20 address, or null for ETH. */
  address: string | null;
}

export const TOKENS: Token[] = tokenConfig.map((t) => ({
  symbol: t.ticker_symbol,
  assetType: BigInt(t.token_hex),
  address: t.token_address === "eth" ? null : getAddress(t.token_address),
}));

export interface Balance {
  token: Token;
  /** Non-quantized amount in the token's base units. */
  amount: bigint;
  decimals: number;
}

export interface AccountState {
  starkKey: bigint;
  /** Address funds are sent to on withdraw, or null when the Stark key is unregistered. */
  registeredTo: string | null;
  balances: Balance[];
}

export type AccountStatus =
  | { kind: "no-funds" }
  | { kind: "needs-registration" }
  | { kind: "ready-to-withdraw" }
  | { kind: "registered-elsewhere"; registeredTo: string };

function bridge(runner: ContractRunner): Contract {
  return new Contract(BRIDGE_ADDRESS, BRIDGE_ABI, runner);
}

/** Returns a list of problems; an empty list means the connected network and bridge are the expected ones. */
export async function checkDeployment(provider: Provider): Promise<string[]> {
  const problems: string[] = [];
  const { chainId } = await provider.getNetwork();
  if (chainId !== MAINNET_CHAIN_ID) {
    problems.push(`Wallet is connected to chain ${chainId}; switch it to Ethereum Mainnet (chain 1).`);
    return problems;
  }
  const implementation = getAddress(await bridge(provider).implementation());
  if (implementation !== getAddress(EXPECTED_IMPLEMENTATION)) {
    problems.push(
      `Bridge implementation is ${implementation}, expected ${EXPECTED_IMPLEMENTATION}. ` +
        "The bridge has been upgraded since this tool was released; do not continue.",
    );
  }
  return problems;
}

const decimalsCache = new Map<string, number>();

async function tokenDecimals(provider: Provider, token: Token): Promise<number> {
  if (token.address === null) return 18;
  const cached = decimalsCache.get(token.address);
  if (cached !== undefined) return cached;
  const decimals = Number(await new Contract(token.address, ERC20_ABI, provider).decimals());
  decimalsCache.set(token.address, decimals);
  return decimals;
}

export async function getAccountState(provider: Provider, starkKey: bigint): Promise<AccountState> {
  const contract = bridge(provider);
  // getEthKey falls back to the key itself for keys below 2^160; derived Stark keys are far above that.
  const ethKey = getAddress(await contract.getEthKey(starkKey));
  const amounts = await Promise.all(
    TOKENS.map(async (token) => (await contract.getWithdrawalBalance(starkKey, token.assetType)) as bigint),
  );
  const balances: Balance[] = [];
  for (const [i, amount] of amounts.entries()) {
    if (amount > 0n) balances.push({ token: TOKENS[i], amount, decimals: await tokenDecimals(provider, TOKENS[i]) });
  }
  return { starkKey, registeredTo: ethKey === ZeroAddress ? null : ethKey, balances };
}

export function classify(state: AccountState, walletAddress: string): AccountStatus {
  if (state.balances.length === 0) return { kind: "no-funds" };
  if (state.registeredTo === null) return { kind: "needs-registration" };
  if (state.registeredTo === getAddress(walletAddress)) return { kind: "ready-to-withdraw" };
  return { kind: "registered-elsewhere", registeredTo: state.registeredTo };
}

/** Surfaces the revert reason from a failed simulation. */
function describeRevert(err: unknown): string {
  const e = err as { reason?: string; shortMessage?: string; message?: string };
  return e.reason ?? e.shortMessage ?? e.message ?? String(err);
}

/**
 * Registers `signer`'s address as the owner of `starkKey`. `registerSender` uses
 * msg.sender as the owner, so the funds destination is always the signing wallet.
 */
export async function registerStarkKey(signer: Signer, starkKey: bigint, registrationSignature: string): Promise<string> {
  const contract = bridge(signer);
  try {
    await contract.registerSender.staticCall(starkKey, registrationSignature);
  } catch (err) {
    throw new Error(`Registration simulation failed: ${describeRevert(err)}`);
  }
  const tx = await contract.registerSender(starkKey, registrationSignature);
  const receipt = await tx.wait();
  if (!receipt || receipt.status !== 1) throw new Error(`Registration transaction ${tx.hash} failed`);

  const owner = getAddress(await bridge(signer.provider!).getEthKey(starkKey));
  const wallet = getAddress(await signer.getAddress());
  if (owner !== wallet) throw new Error(`Stark key is registered to ${owner}, expected ${wallet}`);
  return tx.hash;
}

/**
 * Finalises one pending withdrawal. Refuses unless the Stark key is registered
 * to `signer`, so this tool never sends funds to an address other than the
 * connected wallet.
 */
export async function withdrawAsset(signer: Signer, starkKey: bigint, token: Token): Promise<string> {
  const provider = signer.provider!;
  const wallet = getAddress(await signer.getAddress());
  const owner = getAddress(await bridge(provider).getEthKey(starkKey));
  if (owner !== wallet) throw new Error(`Stark key is registered to ${owner}, not the connected wallet ${wallet}`);

  const contract = bridge(signer);
  try {
    await contract.withdraw.staticCall(starkKey, token.assetType);
  } catch (err) {
    throw new Error(`Withdrawal simulation failed: ${describeRevert(err)}`);
  }
  const tx = await contract.withdraw(starkKey, token.assetType);
  const receipt = await tx.wait();
  if (!receipt || receipt.status !== 1) throw new Error(`Withdrawal transaction ${tx.hash} failed`);
  return tx.hash;
}
