/**
 * Records the outputs of `generateLegacyStarkPrivateKey` and `createStarkSigner`
 * from @imtbl/core-sdk 3.6.1 into sdk-3.6.1.json, the reference that
 * test/unit/derivation.test.ts checks src/lib/derivation.ts against.
 *
 * The SDK and nock are not dependencies of this package: the SDK pins axios
 * 0.26.1, which has open advisories. Install them without saving, run this
 * script, then remove them:
 *
 *   npm i --no-save @imtbl/core-sdk@3.6.1 nock@14.0.17
 *   npx tsx test/vectors/generate-sdk-vectors.ts
 *   npm ci
 *
 * For ambiguous wallets the SDK asks the (retired) Immutable X API which Stark
 * key the account registered. nock answers with each candidate's public key in
 * turn, and the key the SDK returns for that answer is recorded. The SDK checks
 * the API's answer against its own candidates and throws when none match, so
 * every recorded entry is a key the SDK itself produced.
 */
import { writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { Wallet } from "ethers";
import {
  LEGACY_KEY_MESSAGE,
  deriveHdPrivateKey,
  deriveStarkKeyCandidates,
  isAmbiguousDerivation,
} from "../../src/lib/derivation.js";
import { starkPublicKey } from "../../src/lib/registration.js";
import { testWalletKey, type SdkVectors } from "./wallets.js";

const SDK_VERSION = "3.6.1";
const IMX_API = "https://api.x.immutable.com";
const UNAMBIGUOUS_WALLETS = 25;
const AMBIGUOUS_WALLETS = 6;

// Resolved at run time so type-checking does not require the SDK to be installed.
const sdk = (await import("@imtbl/core-sdk" as string)) as {
  generateLegacyStarkPrivateKey(signer: unknown): Promise<string>;
  createStarkSigner(privateKey: string): { getAddress(): Promise<string> | string; getYCoordinate(): string };
};
const nock = ((await import("nock" as string)) as { default: NockLike }).default;

interface NockLike {
  (base: string): { get(path: string): { reply(status: number, body: unknown): unknown } };
  disableNetConnect(): void;
  cleanAll(): void;
  isDone(): boolean;
}

async function selectWallets(): Promise<{ ambiguous: number[]; unambiguous: number[] }> {
  const ambiguous: number[] = [];
  const unambiguous: number[] = [];
  let threeWay = 0;
  for (let i = 0; ambiguous.length < AMBIGUOUS_WALLETS || unambiguous.length < UNAMBIGUOUS_WALLETS || threeWay < 1; i++) {
    if (i > 5000) throw new Error("Scan did not find the required wallets");
    const wallet = new Wallet(testWalletKey(i));
    const sig = await wallet.signMessage(LEGACY_KEY_MESSAGE);
    if (isAmbiguousDerivation(deriveHdPrivateKey(wallet.address, sig))) {
      const isThreeWay = deriveStarkKeyCandidates(wallet.address, sig).length === 3;
      if (ambiguous.length < AMBIGUOUS_WALLETS || (isThreeWay && threeWay < 1)) ambiguous.push(i);
      if (isThreeWay) threeWay++;
    } else if (unambiguous.length < UNAMBIGUOUS_WALLETS) {
      unambiguous.push(i);
    }
  }
  return { ambiguous, unambiguous };
}

async function sdkPublicKey(privateKeyHex: string): Promise<{ x: string; y: string }> {
  const signer = sdk.createStarkSigner(privateKeyHex);
  return { x: BigInt(await signer.getAddress()).toString(16), y: BigInt("0x" + signer.getYCoordinate()).toString(16) };
}

async function record(walletIndex: number, ambiguous: boolean): Promise<SdkVectors["wallets"][number]> {
  const wallet = new Wallet(testWalletKey(walletIndex));
  const userPath = `/v1/users/${wallet.address.toLowerCase()}`;
  const sdkResultByApiAnswer: Record<string, string> = {};

  if (ambiguous) {
    const sig = await wallet.signMessage(LEGACY_KEY_MESSAGE);
    for (const { privateKey } of deriveStarkKeyCandidates(wallet.address, sig)) {
      const starkKey = starkPublicKey(privateKey).x.toString(16);
      nock(IMX_API).get(userPath).reply(200, { accounts: ["0x" + starkKey] });
      sdkResultByApiAnswer[starkKey] = await sdk.generateLegacyStarkPrivateKey(wallet);
      if (!nock.isDone()) throw new Error("SDK did not query the API for an ambiguous wallet");
    }
    nock(IMX_API).get(userPath).reply(404, { code: "account_not_found", message: "Account not found" });
  }
  // With net connect disabled, an unexpected API call from an unambiguous wallet throws.
  const sdkResult = await sdk.generateLegacyStarkPrivateKey(wallet);
  nock.cleanAll();

  const sdkPublicKeys: Record<string, { x: string; y: string }> = {};
  for (const key of new Set([sdkResult, ...Object.values(sdkResultByApiAnswer)])) {
    sdkPublicKeys[key] = await sdkPublicKey(key);
  }
  return { walletIndex, address: wallet.address, sdkResult, sdkResultByApiAnswer, sdkPublicKeys };
}

nock.disableNetConnect();
const { ambiguous, unambiguous } = await selectWallets();
const vectors: SdkVectors = { sdkVersion: SDK_VERSION, message: LEGACY_KEY_MESSAGE, wallets: [] };
for (const i of unambiguous) vectors.wallets.push(await record(i, false));
for (const i of ambiguous) vectors.wallets.push(await record(i, true));

const out = fileURLToPath(new URL(`./sdk-${SDK_VERSION}.json`, import.meta.url));
writeFileSync(out, JSON.stringify(vectors, null, 2) + "\n");
console.log(`Wrote ${vectors.wallets.length} wallets to ${out}`);
