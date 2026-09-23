/**
 * Equivalence of src/lib/derivation.ts with `generateLegacyStarkPrivateKey`
 * from @imtbl/core-sdk 3.6.1, the code that generated users' Stark keys.
 *
 * The reference outputs are recorded in test/vectors/sdk-3.6.1.json by
 * test/vectors/generate-sdk-vectors.ts, which drives the SDK directly
 * (including each of its API-resolved fallback branches for ambiguous wallets).
 */
import { describe, expect, it } from "vitest";
import { Wallet } from "ethers";
import { LEGACY_KEY_MESSAGE, deriveHdPrivateKey, deriveStarkKeyCandidates, isAmbiguousDerivation } from "../../src/lib/derivation.js";
import { starkPublicKey } from "../../src/lib/registration.js";
import { testWalletKey, type SdkVectors } from "../vectors/wallets.js";
import vectorsJson from "../vectors/sdk-3.6.1.json";

const vectors = vectorsJson as unknown as SdkVectors;
const unambiguous = vectors.wallets.filter((w) => Object.keys(w.sdkResultByApiAnswer).length === 0);
const ambiguous = vectors.wallets.filter((w) => Object.keys(w.sdkResultByApiAnswer).length > 0);

function hex64(n: bigint): string {
  return n.toString(16).padStart(64, "0");
}

async function derive(w: SdkVectors["wallets"][number]) {
  const wallet = new Wallet(testWalletKey(w.walletIndex));
  expect(wallet.address).toBe(w.address);
  const sig = await wallet.signMessage(LEGACY_KEY_MESSAGE);
  return { sig, candidates: deriveStarkKeyCandidates(wallet.address, sig) };
}

describe("recorded SDK vectors", () => {
  it("cover typical, ambiguous and three-candidate wallets", () => {
    expect(vectors.sdkVersion).toBe("3.6.1");
    expect(vectors.message).toBe(LEGACY_KEY_MESSAGE);
    expect(unambiguous.length).toBeGreaterThanOrEqual(25);
    expect(ambiguous.length).toBeGreaterThanOrEqual(6);
    expect(ambiguous.some((w) => Object.keys(w.sdkResultByApiAnswer).length === 3)).toBe(true);
  });
});

describe("unambiguous accounts", () => {
  it("produce a single candidate equal to the SDK's key", async () => {
    for (const w of unambiguous) {
      const { sig, candidates } = await derive(w);
      expect(isAmbiguousDerivation(deriveHdPrivateKey(w.address, sig))).toBe(false);
      expect(candidates).toHaveLength(1);
      expect(candidates[0].variants).toEqual(["primary", "index-restart", "secp-bound"]);
      expect(hex64(candidates[0].privateKey)).toBe(w.sdkResult);
    }
  });
});

describe("ambiguous accounts", () => {
  it("produce exactly the keys the SDK returns across its API answers", async () => {
    for (const w of ambiguous) {
      const { sig, candidates } = await derive(w);
      expect(isAmbiguousDerivation(deriveHdPrivateKey(w.address, sig))).toBe(true);
      const byStarkKey = Object.fromEntries(
        candidates.map((c) => [starkPublicKey(c.privateKey).x.toString(16), hex64(c.privateKey)]),
      );
      expect(byStarkKey).toEqual(w.sdkResultByApiAnswer);
    }
  });

  it("list the SDK's result for an account unknown to the API first", async () => {
    for (const w of ambiguous) {
      const { candidates } = await derive(w);
      expect(hex64(candidates[0].privateKey)).toBe(w.sdkResult);
      expect(candidates[0].variants).toContain("primary");
    }
  });
});

describe("public keys", () => {
  it("match the SDK's Stark signer for every recorded key", () => {
    let checked = 0;
    for (const w of vectors.wallets) {
      for (const [privateKey, pub] of Object.entries(w.sdkPublicKeys)) {
        const { x, y } = starkPublicKey(BigInt("0x" + privateKey));
        expect(x.toString(16)).toBe(pub.x);
        expect(y.toString(16)).toBe(pub.y);
        checked++;
      }
    }
    expect(checked).toBeGreaterThan(vectors.wallets.length);
  });
});

describe("input handling", () => {
  it("is independent of address checksum casing", async () => {
    const wallet = new Wallet(testWalletKey(unambiguous[0].walletIndex));
    const sig = await wallet.signMessage(LEGACY_KEY_MESSAGE);
    expect(deriveStarkKeyCandidates(wallet.address.toLowerCase(), sig)).toEqual(
      deriveStarkKeyCandidates(wallet.address, sig),
    );
  });

  it("rejects signatures that are not 65 bytes", () => {
    expect(() => deriveStarkKeyCandidates(unambiguous[0].address, "0x" + "11".repeat(64))).toThrow(/65-byte/);
  });
});
