/**
 * Offline re-implementation of the Immutable X legacy Stark key derivation
 * (`generateLegacyStarkPrivateKey` in @imtbl/core-sdk 3.6.1).
 *
 * The SDK derives a BIP32 key from the `s` value of a wallet signature over
 * `LEGACY_KEY_MESSAGE`, then grinds it into a Stark private key. For about 1 in
 * 32 accounts the first grinding round is rejected, and three historical
 * grinding variants disagree. The SDK resolves that case by asking the
 * Immutable X API which Stark key the account registered; that API has been
 * retired, so this module returns every candidate and the caller picks the one
 * that holds funds on-chain.
 *
 * Every candidate is derived from the wallet's own signature, so every
 * candidate belongs to the wallet owner. A mistake in this module can only
 * produce a key with no funds; it cannot produce another user's key.
 *
 * `test/derivation.test.ts` checks this module against the SDK itself.
 */
import { HDKey } from "@scure/bip32";
import { sha256 } from "@noble/hashes/sha2.js";
import { getAccountPath } from "@scure/starknet";
import { getAddress, getBytes } from "ethers";

/** Message the Immutable X SDK asks the wallet to sign when deriving the Stark key. */
export const LEGACY_KEY_MESSAGE = "Only sign this request if you’ve initiated an action with Immutable X.";

/** Order of the Stark curve subgroup. */
export const STARK_EC_ORDER = 0x0800000000000010ffffffffffffffffb781126dcae7b2321e66a241adc64d2fn;

/** secp256k1 order, used as the grinding bound by one of the SDK's variants. */
const SECP256K1_ORDER = 0xfffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364141n;

const TWO_256 = 1n << 256n;
const BOUND_2_256 = TWO_256 - (TWO_256 % STARK_EC_ORDER);
const BOUND_SECP = SECP256K1_ORDER - (SECP256K1_ORDER % STARK_EC_ORDER);

/** Guards against an unbounded loop; each round passes with probability > 31/32. */
const MAX_GRIND_ROUNDS = 10_000;

export type DerivationVariant =
  /** SDK's primary result; the only result for accounts whose first round is accepted. */
  | "primary"
  /** SDK's first fallback: grinding index restarts at 0 after the first round. */
  | "index-restart"
  /** SDK's second fallback: grinding index stays at 0 and the bound is derived from the secp256k1 order. */
  | "secp-bound";

export interface StarkKeyCandidate {
  privateKey: bigint;
  variants: DerivationVariant[];
}

/**
 * `Buffer.from(hex, "hex")` semantics: parse whole byte pairs and drop a
 * trailing odd nibble. The SDK feeds unpadded `BN.toString(16)` output through
 * this path during re-grinding, so the dropped nibble is part of the derivation.
 */
function bufferFromHex(hex: string): Uint8Array {
  const clean = hex.replace(/^0x/, "");
  const out = new Uint8Array(clean.length >> 1);
  for (let i = 0; i < out.length; i++) {
    const byte = Number.parseInt(clean.slice(i * 2, i * 2 + 2), 16);
    if (Number.isNaN(byte)) throw new Error("Invalid hex input");
    out[i] = byte;
  }
  return out;
}

/** enc-utils `numberToHex`: minimal big-endian bytes, at least one byte. */
function indexToHex(index: number): string {
  const hex = index.toString(16);
  return hex.length % 2 === 0 ? hex : `0${hex}`;
}

function toBigInt(bytes: Uint8Array): bigint {
  let n = 0n;
  for (const b of bytes) n = (n << 8n) | BigInt(b);
  return n;
}

/** sha256(hex ‖ index) as used by every SDK grinding variant. */
function grindHash(hex: string, index: number): bigint {
  return toBigInt(sha256(bufferFromHex(hex + indexToHex(index))));
}

function pad64(n: bigint): string {
  return n.toString(16).padStart(64, "0");
}

function grind(hdKey: bigint, bound: bigint, nextIndex: (round: number) => number): bigint {
  let h = grindHash(pad64(hdKey), 0);
  for (let round = 0; h >= bound; round++) {
    if (round >= MAX_GRIND_ROUNDS) throw new Error("Stark key grinding did not terminate");
    h = grindHash(h.toString(16), nextIndex(round));
  }
  return h % STARK_EC_ORDER;
}

/** BIP32 private key at the Immutable X account path, seeded by the signature's `s` value. */
export function deriveHdPrivateKey(ethAddress: string, walletSignature: string): bigint {
  // ethers v5 `splitSignature(sig).s` for a 65-byte r ‖ s ‖ v signature, taken without canonical-s checks.
  const sigBytes = getBytes(walletSignature);
  if (sigBytes.length !== 65) throw new Error(`Expected a 65-byte wallet signature, got ${sigBytes.length} bytes`);
  const sBytes = sigBytes.slice(32, 64);
  const path = getAccountPath("starkex", "immutablex", getAddress(ethAddress).toLowerCase(), 1);
  const child = HDKey.fromMasterSeed(sBytes).derive(path);
  const key = child.privateKey;
  if (!key) throw new Error("BIP32 derivation produced no private key");
  const value = toBigInt(key);
  child.wipePrivateData();
  return value;
}

/** True when the first grinding round is rejected, which is when the SDK's variants can disagree. */
export function isAmbiguousDerivation(hdKey: bigint): boolean {
  return grindHash(pad64(hdKey), 0) >= BOUND_2_256;
}

/**
 * All Stark private keys the SDK could have produced for this wallet signature,
 * deduplicated. The first entry is the SDK's primary result.
 */
export function deriveStarkKeyCandidates(ethAddress: string, walletSignature: string): StarkKeyCandidate[] {
  const hdKey = deriveHdPrivateKey(ethAddress, walletSignature);
  const results: [DerivationVariant, bigint][] = [
    ["primary", grind(hdKey, BOUND_2_256, (round) => round + 1)],
    ["index-restart", grind(hdKey, BOUND_2_256, (round) => round)],
    ["secp-bound", grind(hdKey, BOUND_SECP, () => 0)],
  ];
  const candidates: StarkKeyCandidate[] = [];
  for (const [variant, privateKey] of results) {
    const existing = candidates.find((c) => c.privateKey === privateKey);
    if (existing) existing.variants.push(variant);
    else candidates.push({ privateKey, variants: [variant] });
  }
  return candidates;
}
