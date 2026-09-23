import { keccak256, toUtf8Bytes } from "ethers";

/** Ethereum private key of deterministic test wallet i. These wallets are never funded outside local forks. */
export function testWalletKey(i: number): string {
  return keccak256(toUtf8Bytes(`stark-key-registration-test-${i}`));
}

/** Shape of sdk-<version>.json, written by generate-sdk-vectors.ts. */
export interface SdkVectors {
  sdkVersion: string;
  message: string;
  wallets: {
    /** Index for `testWalletKey`. */
    walletIndex: number;
    address: string;
    /** SDK result when the account is unknown to the API (also the result when no API call is made). */
    sdkResult: string;
    /** SDK result for each API answer, keyed by the Stark public key the API returned. Empty for unambiguous wallets. */
    sdkResultByApiAnswer: Record<string, string>;
    /** Public key reported by the SDK's Stark signer for each recorded private key. */
    sdkPublicKeys: Record<string, { x: string; y: string }>;
  }[];
}
