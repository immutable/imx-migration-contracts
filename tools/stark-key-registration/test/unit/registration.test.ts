import { describe, expect, it } from "vitest";
import { AbiCoder, Wallet, concat, getBytes, keccak256, toBeHex, toUtf8Bytes } from "ethers";
import elliptic from "elliptic";
import hash from "hash.js";
import { STARK_EC_ORDER } from "../../src/lib/derivation.js";
import { registrationMessageHash, signRegistration, starkPublicKey } from "../../src/lib/registration.js";

const MAX_ELEMENT = 1n << 251n;

/** Stark curve as configured in @imtbl/core-sdk, using the same elliptic library. */
const starkEc = new elliptic.ec(
  new elliptic.curves.PresetCurve({
    type: "short",
    prime: null,
    p: "08000000 00000011 00000000 00000000 00000000 00000000 00000000 00000001",
    a: "00000000 00000000 00000000 00000000 00000000 00000000 00000000 00000001",
    b: "06f21413 efbe40de 150e596d 72f7a8c5 609ad26c 15c915c1 f4cdfcb9 9cee9e89",
    n: "08000000 00000010 ffffffff ffffffff b781126d cae7b232 1e66a241 adc64d2f",
    hash: hash.sha256,
    gRed: false,
    g: [
      "1ef15c18599971b7beced415a40f0c7deacfd9b0d1819e03d723d8bc943cfca",
      "5668060aa49730b7be4801df46ec62de53ecd11abe43a32873000c36e8dc1f",
    ],
  } as never),
);

function decode(signature: string): [bigint, bigint, bigint] {
  const [r, s, y] = AbiCoder.defaultAbiCoder().decode(["uint256", "uint256", "uint256"], signature);
  return [r, s, y];
}

/**
 * elliptic truncates 32-byte message inputs by 4 bits for the 252-bit Stark
 * order; the SDK signer appends a nibble to 63-digit hashes to cancel that
 * (`fixMsgHashLen`), and the same adjustment applies to verification.
 */
function ellipticMsg(msgHash: bigint): string {
  const hex = msgHash.toString(16);
  return hex.length === 63 ? hex + "0" : hex;
}

function modInverse(a: bigint, m: bigint): bigint {
  let [oldR, r] = [a % m, m];
  let [oldS, s] = [1n, 0n];
  while (r !== 0n) {
    const q = oldR / r;
    [oldR, r] = [r, oldR - q * r];
    [oldS, s] = [s, oldS - q * s];
  }
  return ((oldS % m) + m) % m;
}

describe("registrationMessageHash", () => {
  it("equals keccak256(abi.encodePacked(\"UserRegistration:\", ethKey, starkKey)) mod EC_ORDER", () => {
    const ethKey = "0x429e8C0B0E92b80d84E3cc017f4e6D2D01B91dEa";
    const starkKey = 280792449106583330515328341059174390612693624277076071221407349784231745237n;
    const packed = concat([toUtf8Bytes("UserRegistration:"), getBytes(ethKey), toBeHex(starkKey, 32)]);
    expect(registrationMessageHash(ethKey, starkKey)).toBe(BigInt(keccak256(packed)) % STARK_EC_ORDER);
    expect(registrationMessageHash(ethKey.toLowerCase(), starkKey)).toBe(registrationMessageHash(ethKey, starkKey));
  });
});

describe("signRegistration", () => {
  const cases = Array.from({ length: 40 }, (_, i) => ({
    privateKey: BigInt(keccak256(toUtf8Bytes(`stark-private-${i}`))) % STARK_EC_ORDER,
    ethAddress: Wallet.createRandom().address,
  }));

  it("produces signatures the SDK's elliptic curve accepts, within the contract's bounds", () => {
    for (const { privateKey, ethAddress } of cases) {
      const { starkKey, signature } = signRegistration(privateKey, ethAddress);
      const [r, s, y] = decode(signature);
      const pub = starkPublicKey(privateKey);
      expect(starkKey).toBe(pub.x);
      expect(y).toBe(pub.y);
      expect(getBytes(signature)).toHaveLength(96);

      expect(r >= 1n && r < MAX_ELEMENT).toBe(true);
      const w = modInverse(s, STARK_EC_ORDER);
      expect(w >= 1n && w < MAX_ELEMENT).toBe(true);

      const key = starkEc.keyFromPublic({ x: pub.x.toString(16), y: pub.y.toString(16) });
      const msgHash = registrationMessageHash(ethAddress, starkKey);
      expect(key.verify(ellipticMsg(msgHash), { r: r.toString(16), s: s.toString(16) })).toBe(true);
    }
  });

  it("binds the signature to the given address", () => {
    const { privateKey, ethAddress } = cases[0];
    const other = Wallet.createRandom().address;
    const { starkKey, signature } = signRegistration(privateKey, ethAddress);
    const [r, s] = decode(signature);
    const pub = starkPublicKey(privateKey);
    const key = starkEc.keyFromPublic({ x: pub.x.toString(16), y: pub.y.toString(16) });
    const otherHash = registrationMessageHash(other, starkKey);
    expect(key.verify(ellipticMsg(otherHash), { r: r.toString(16), s: s.toString(16) })).toBe(false);
  });

  it("is deterministic for the same key and address", () => {
    const { privateKey, ethAddress } = cases[1];
    expect(signRegistration(privateKey, ethAddress)).toEqual(signRegistration(privateKey, ethAddress));
  });
});
