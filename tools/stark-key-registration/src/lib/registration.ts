/**
 * Stark-key registration payload for `registerSender(starkKey, starkSignature)`
 * on the Immutable X bridge (src/bridge/starkex/LegacyStarkExchangeBridge.sol).
 *
 * The contract verifies a Stark-curve ECDSA signature over
 *   keccak256(abi.encodePacked("UserRegistration:", ethKey, starkKey)) mod EC_ORDER
 * and, for `registerSender`, uses msg.sender as ethKey. The signature therefore
 * only authorises registration to the address it was produced for.
 */
import { AbiCoder, getAddress, solidityPackedKeccak256 } from "ethers";
import { getPublicKey, sign } from "@scure/starknet";
import { STARK_EC_ORDER } from "./derivation.js";

/** Contract bounds on r and s⁻¹ (StarkCurveECDSA.N_ELEMENT_BITS_ECDSA = 251). */
const MAX_ELEMENT = 1n << 251n;

/** Retries with fresh nonces when a deterministic signature falls outside the contract's bounds. */
const MAX_SIGNING_ATTEMPTS = 32;

export interface StarkPublicKey {
  x: bigint;
  y: bigint;
}

export function starkPublicKey(privateKey: bigint): StarkPublicKey {
  const uncompressed = getPublicKey(privateKey.toString(16).padStart(64, "0"), false);
  let x = 0n;
  let y = 0n;
  for (let i = 1; i < 33; i++) x = (x << 8n) | BigInt(uncompressed[i]);
  for (let i = 33; i < 65; i++) y = (y << 8n) | BigInt(uncompressed[i]);
  return { x, y };
}

export function registrationMessageHash(ethAddress: string, starkKey: bigint): bigint {
  const digest = solidityPackedKeccak256(
    ["string", "address", "uint256"],
    ["UserRegistration:", getAddress(ethAddress), starkKey],
  );
  return BigInt(digest) % STARK_EC_ORDER;
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

/**
 * Returns the 96-byte `abi.encode(r, s, starkKeyY)` payload the contract expects.
 */
export function signRegistration(privateKey: bigint, ethAddress: string): { starkKey: bigint; signature: string } {
  const { x: starkKey, y: starkKeyY } = starkPublicKey(privateKey);
  const msgHash = registrationMessageHash(ethAddress, starkKey);
  const privHex = privateKey.toString(16).padStart(64, "0");
  const msgHex = msgHash.toString(16);

  for (let attempt = 0; attempt < MAX_SIGNING_ATTEMPTS; attempt++) {
    let sig;
    try {
      // First attempt is RFC 6979 deterministic; later attempts add fresh entropy to the nonce.
      sig = sign(msgHex, privHex, attempt === 0 ? undefined : { extraEntropy: true });
    } catch (err) {
      if (err instanceof RangeError) continue;
      throw err;
    }
    const w = modInverse(sig.s, STARK_EC_ORDER);
    if (sig.r < 1n || sig.r >= MAX_ELEMENT || w < 1n || w >= MAX_ELEMENT) continue;
    const signature = AbiCoder.defaultAbiCoder().encode(["uint256", "uint256", "uint256"], [sig.r, sig.s, starkKeyY]);
    return { starkKey, signature };
  }
  throw new Error("Could not produce a Stark signature within the contract's bounds");
}
