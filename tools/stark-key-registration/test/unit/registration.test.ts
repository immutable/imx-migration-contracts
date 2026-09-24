import { describe, expect, it } from "vitest";
import { AbiCoder, Wallet, concat, getBytes, keccak256, toBeHex, toUtf8Bytes } from "ethers";
import { STARK_EC_ORDER } from "../../src/lib/derivation.js";
import { registrationMessageHash, signRegistration, starkPublicKey } from "../../src/lib/registration.js";

/**
 * BigInt port of StarkCurveECDSA.verify (src/bridge/starkex/libraries/StarkCurveECDSA.sol),
 * independent of the signing library, so signatures are checked by the same rule as on-chain.
 */
const FIELD_PRIME = 0x800000000000011000000000000000000000000000000000000000000000001n;
const ALPHA = 1n;
const BETA = 3141592653589793238462643383279502884197169399375105820974944592307816406665n;
const GEN: Point = [
  0x1ef15c18599971b7beced415a40f0c7deacfd9b0d1819e03d723d8bc943cfcan,
  0x5668060aa49730b7be4801df46ec62de53ecd11abe43a32873000c36e8dc1fn,
];
const MAX_ELEMENT = 1n << 251n;

type Point = [bigint, bigint] | null;

const mod = (a: bigint, m: bigint) => ((a % m) + m) % m;

function modInverse(a: bigint, m: bigint): bigint {
  let [oldR, r] = [mod(a, m), m];
  let [oldS, s] = [1n, 0n];
  while (r !== 0n) {
    const q = oldR / r;
    [oldR, r] = [r, oldR - q * r];
    [oldS, s] = [s, oldS - q * s];
  }
  return mod(oldS, m);
}

function ecAdd(p: Point, q: Point): Point {
  if (p === null) return q;
  if (q === null) return p;
  const [x1, y1] = p;
  const [x2, y2] = q;
  if (x1 === x2 && mod(y1 + y2, FIELD_PRIME) === 0n) return null;
  const lambda =
    x1 === x2
      ? mod((3n * x1 * x1 + ALPHA) * modInverse(2n * y1, FIELD_PRIME), FIELD_PRIME)
      : mod((y2 - y1) * modInverse(x2 - x1, FIELD_PRIME), FIELD_PRIME);
  const x3 = mod(lambda * lambda - x1 - x2, FIELD_PRIME);
  return [x3, mod(lambda * (x1 - x3) - y1, FIELD_PRIME)];
}

function ecMul(k: bigint, p: Point): Point {
  let result: Point = null;
  let addend = p;
  for (let n = k; n > 0n; n >>= 1n) {
    if (n & 1n) result = ecAdd(result, addend);
    addend = ecAdd(addend, addend);
  }
  return result;
}

function contractVerify(msgHash: bigint, r: bigint, s: bigint, pubX: bigint, pubY: bigint): boolean {
  if (msgHash >= STARK_EC_ORDER) return false;
  if (s < 1n || s >= STARK_EC_ORDER) return false;
  const w = modInverse(s, STARK_EC_ORDER);
  if (r < 1n || r >= MAX_ELEMENT || w < 1n || w >= MAX_ELEMENT) return false;
  if (mod(pubY * pubY, FIELD_PRIME) !== mod(pubX ** 3n + pubX + BETA, FIELD_PRIME)) return false;
  const b = ecAdd(ecMul(msgHash, GEN), ecMul(r, [pubX, pubY]));
  const res = ecMul(w, b);
  return res !== null && res[0] === r;
}

function decode(signature: string): [bigint, bigint, bigint] {
  const [r, s, y] = AbiCoder.defaultAbiCoder().decode(["uint256", "uint256", "uint256"], signature);
  return [r, s, y];
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

  it("produces signatures the contract's verification accepts, within its bounds", () => {
    for (const { privateKey, ethAddress } of cases) {
      const { starkKey, signature } = signRegistration(privateKey, ethAddress);
      const [r, s, y] = decode(signature);
      const pub = starkPublicKey(privateKey);
      expect(starkKey).toBe(pub.x);
      expect(y).toBe(pub.y);
      expect(getBytes(signature)).toHaveLength(96);
      expect(contractVerify(registrationMessageHash(ethAddress, starkKey), r, s, pub.x, pub.y)).toBe(true);
    }
  });

  it("derives public keys that match an independent scalar multiplication", () => {
    for (const { privateKey } of cases.slice(0, 5)) {
      const pub = starkPublicKey(privateKey);
      expect(ecMul(privateKey, GEN)).toEqual([pub.x, pub.y]);
    }
  });

  it("binds the signature to the given address", () => {
    const { privateKey, ethAddress } = cases[0];
    const other = Wallet.createRandom().address;
    const { starkKey, signature } = signRegistration(privateKey, ethAddress);
    const [r, s] = decode(signature);
    const pub = starkPublicKey(privateKey);
    expect(contractVerify(registrationMessageHash(other, starkKey), r, s, pub.x, pub.y)).toBe(false);
  });

  it("is deterministic for the same key and address", () => {
    const { privateKey, ethAddress } = cases[1];
    expect(signRegistration(privateKey, ethAddress)).toEqual(signRegistration(privateKey, ethAddress));
  });
});
