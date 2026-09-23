/**
 * Equivalence of src/lib/derivation.ts with `generateLegacyStarkPrivateKey`
 * from @imtbl/core-sdk 3.6.1, the code that generated users' Stark keys.
 *
 * For ambiguous accounts the SDK asks the (now retired) Immutable X API which
 * key the account registered. nock stands in for that API so each of the SDK's
 * three fallback branches can be driven and compared.
 */
import { afterEach, beforeAll, describe, expect, it } from "vitest";
import nock from "nock";
import { Wallet, keccak256, toUtf8Bytes } from "ethers";
import { createStarkSigner, generateLegacyStarkPrivateKey } from "@imtbl/core-sdk";
import {
  LEGACY_KEY_MESSAGE,
  deriveHdPrivateKey,
  deriveStarkKeyCandidates,
  isAmbiguousDerivation,
} from "../../src/lib/derivation.js";
import { starkPublicKey } from "../../src/lib/registration.js";

const IMX_API = "https://api.x.immutable.com";

/** The SDK is typed against ethers v5 but only calls getAddress() and signMessage(), which a v6 Wallet provides. */
const sdkDerive = (wallet: Wallet) => generateLegacyStarkPrivateKey(wallet as never);

function testWallet(i: number): Wallet {
  return new Wallet(keccak256(toUtf8Bytes(`stark-key-registration-test-${i}`)));
}

function hex64(n: bigint): string {
  return n.toString(16).padStart(64, "0");
}

async function candidatesFor(wallet: Wallet) {
  return deriveStarkKeyCandidates(wallet.address, await wallet.signMessage(LEGACY_KEY_MESSAGE));
}

/**
 * Wallets found by scanning the deterministic test wallets: about 1 in 30 is
 * ambiguous, and about 1 in 300 has three distinct candidates.
 */
const ambiguous: Wallet[] = [];
const unambiguous: Wallet[] = [];

beforeAll(async () => {
  let threeWay = 0;
  for (let i = 0; ambiguous.length < 6 || unambiguous.length < 25 || threeWay < 1; i++) {
    if (i > 5000) throw new Error("Scan did not find the required wallets");
    const wallet = testWallet(i);
    const sig = await wallet.signMessage(LEGACY_KEY_MESSAGE);
    if (isAmbiguousDerivation(deriveHdPrivateKey(wallet.address, sig))) {
      const isThreeWay = deriveStarkKeyCandidates(wallet.address, sig).length === 3;
      if (ambiguous.length < 6 || (isThreeWay && threeWay < 1)) ambiguous.push(wallet);
      if (isThreeWay) threeWay++;
    } else if (unambiguous.length < 25) {
      unambiguous.push(wallet);
    }
  }
}, 120_000);

afterEach(() => {
  nock.cleanAll();
  nock.enableNetConnect();
});

describe("unambiguous accounts", () => {
  it("produce a single candidate equal to the SDK's key, without any API call", async () => {
    nock.disableNetConnect();
    for (const wallet of unambiguous) {
      const candidates = await candidatesFor(wallet);
      expect(candidates).toHaveLength(1);
      expect(candidates[0].variants).toEqual(["primary", "index-restart", "secp-bound"]);
      expect(hex64(candidates[0].privateKey)).toBe(await sdkDerive(wallet));
    }
  });
});

describe("ambiguous accounts", () => {
  it("include the key the SDK returns for each API answer", async () => {
    nock.disableNetConnect();
    for (const wallet of ambiguous) {
      const candidates = await candidatesFor(wallet);
      expect(candidates.length).toBeGreaterThan(1);
      for (const candidate of candidates) {
        const starkKey = "0x" + starkPublicKey(candidate.privateKey).x.toString(16);
        nock(IMX_API)
          .get(`/v1/users/${wallet.address.toLowerCase()}`)
          .reply(200, { accounts: [starkKey] });
        expect(await sdkDerive(wallet)).toBe(hex64(candidate.privateKey));
      }
    }
  });

  it("list the SDK's result for an unregistered account first", async () => {
    nock.disableNetConnect();
    for (const wallet of ambiguous) {
      const candidates = await candidatesFor(wallet);
      nock(IMX_API)
        .get(`/v1/users/${wallet.address.toLowerCase()}`)
        .reply(404, { code: "account_not_found", message: "Account not found" });
      expect(await sdkDerive(wallet)).toBe(hex64(candidates[0].privateKey));
      expect(candidates[0].variants).toContain("primary");
    }
  });

  it("cannot be derived by the SDK once the Immutable X API is unreachable", async () => {
    nock.disableNetConnect();
    await expect(sdkDerive(ambiguous[0])).rejects.toThrow();
  });
});

describe("public keys", () => {
  it("match the SDK's Stark signer for every candidate", async () => {
    for (const wallet of [...unambiguous.slice(0, 5), ...ambiguous]) {
      for (const { privateKey } of await candidatesFor(wallet)) {
        const sdkSigner = createStarkSigner(hex64(privateKey));
        const { x, y } = starkPublicKey(privateKey);
        expect(x).toBe(BigInt(await sdkSigner.getAddress()));
        expect(y).toBe(BigInt("0x" + sdkSigner.getYCoordinate()));
      }
    }
  });
});

describe("input handling", () => {
  it("is independent of address checksum casing", async () => {
    const wallet = unambiguous[0];
    const sig = await wallet.signMessage(LEGACY_KEY_MESSAGE);
    expect(deriveStarkKeyCandidates(wallet.address.toLowerCase(), sig)).toEqual(
      deriveStarkKeyCandidates(wallet.address, sig),
    );
  });

  it("rejects signatures that are not 65 bytes", () => {
    expect(() => deriveStarkKeyCandidates(testWallet(0).address, "0x" + "11".repeat(64))).toThrow(/65-byte/);
  });
});
