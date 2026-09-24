/**
 * Wallet-facing entry point. Stark private keys exist only inside
 * `deriveAccounts`: they are used to sign the registration payload and then go
 * out of scope. Callers receive public keys and registration signatures only.
 */
import { getAddress, type Signer } from "ethers";
import { deriveStarkKeyCandidates, LEGACY_KEY_MESSAGE, type DerivationVariant } from "./derivation.js";
import { signRegistration } from "./registration.js";

export interface DerivedAccount {
  /** Stark public key (x-coordinate). */
  starkKey: bigint;
  variants: DerivationVariant[];
  /** Wallet address the registration signature is bound to. */
  ethAddress: string;
  /** `abi.encode(r, s, starkKeyY)` for `registerSender`; valid only when sent from `ethAddress`. */
  registrationSignature: string;
}

export async function deriveAccounts(signer: Signer): Promise<DerivedAccount[]> {
  const ethAddress = getAddress(await signer.getAddress());
  const walletSignature = await signer.signMessage(LEGACY_KEY_MESSAGE);
  return deriveStarkKeyCandidates(ethAddress, walletSignature).map(({ privateKey, variants }) => {
    const { starkKey, signature } = signRegistration(privateKey, ethAddress);
    return { starkKey, variants, ethAddress, registrationSignature: signature };
  });
}
