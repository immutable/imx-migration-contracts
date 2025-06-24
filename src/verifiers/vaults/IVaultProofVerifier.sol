// SPDX-License-Identifier: Apache-2.0.
pragma solidity ^0.8.27;

// @title IVaultProofVerifier
// @notice This interface defines the functions and types for verifying Immutable X vault proofs.
// @dev The proof is used to prove the details of an Immutable X vault against a specific Merkle Root.
// @dev It is assumed that the proof body encodes the vault information, the root, and the Merkle proof.
interface IVaultProofVerifier {
    /**
     * @notice The Vault struct represents the information of a vault.
     * @param starkKey The Stark key of the user
     * @param assetId The identifier of the asset in the vault.
     * @param quantizedAmount The amount of the asset in the vault, quantized.
     */
    struct Vault {
        uint256 starkKey;
        uint256 assetId;
        uint256 quantizedAmount;
    }

    // TODO: Consider more specialized error types
    // @notice InvalidVaultProof is a general error thrown when the vault proof validation fails. Specific reasons for the failure are included in the message.
    error InvalidVaultProof(string message);

    /*
     * @notice verifyVaultProof verifies the proof for a vault. It is assumed that the proof contains the vault information, the root, and the proof.
     * @param proof The proof to be verified, which is assumed to include the vault information, the root and the Merkle proof.
     * @return success Returns true if the proof is valid. The function might return false or revert if the proof is invalid.
     */
    function verifyVaultProof(uint256[] calldata proof) external view returns (bool success);
    /*
     * @notice extractLeafFromProof extracts the leaf (vault information) encoded in a given proof.
     * @param proof The proof to be verified, which is assumed to include the vault information. Specific structure depends on the implementation.
     * @return vault Returns the vault information extracted from the proof. Throws `InvalidVaultProof` if the proof is invalid.
     */
    function extractLeafFromProof(uint256[] calldata proof) external pure returns (Vault memory vault);
    /*
     * @notice extractRootFromProof extracts the Merkle root hash encoded in a given proof.
     * @param proof The proof to be processed, which is assumed to include the root. Specific structure depends on the implementation.
     * @return root Returns the root extracted from the proof. Throws `InvalidVaultProof` if the proof is invalid.
     */
    function extractRootFromProof(uint256[] calldata proof) external pure returns (uint256 root);

    /*
     * @notice extractLeafAndRootFromProof extracts both the leaf (vault information) and the Merkle root hash from the proof.
     * @param proof The proof to be processed, which is assumed to include the root hash and vault information. Specific structure depends on the implementation.
     * @return Vault Returns the vault information extracted from the proof. Throws `InvalidVaultProof` if the proof is invalid.
     * @return root Returns the root hash extracted from the proof. Throws `InvalidVaultProof` if the proof is invalid.
     * @see extractLeafFromProof
     * @see extractRootFromProof
     */
    function extractLeafAndRootFromProof(uint256[] calldata proof)
        external
        pure
        returns (Vault memory vault, uint256 root);
}
