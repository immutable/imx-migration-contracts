// Copyright Immutable Pty Ltd 2018 - 2025
// SPDX-License-Identifier: Apache-2.0.
pragma solidity ^0.8.27;

/**
 * @title IVaultProofVerifier
 * @notice This interface defines the functions and types for verifying Immutable X vault proofs.
 * @dev The proof is used to prove the details of an Immutable X vault against a specific Merkle Root.
 * @dev It is assumed that the proof body encodes the vault information, the root, and the Merkle proof.
 */
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
        uint256 quantizedBalance;
    }

    /// @notice Thrown when the vault proof validation fails
    /// @param message A descriptive error message explaining the specific reason for the failure
    error InvalidVaultProof(string message);

    /**
     * @notice Verifies the proof for a vault
     * @dev The proof is assumed to include the vault information, the root, and the Merkle proof
     * @param proof The proof to be verified
     * @return success Returns true if the proof is valid, false or reverts if invalid
     */
    function verifyVaultProof(uint256[] calldata proof) external view returns (bool success);

    /**
     * @notice Extracts the leaf (vault information) encoded in a given proof
     * @dev The specific structure depends on the implementation
     * @param proof The proof containing the vault information
     * @return vault The vault information extracted from the proof
     * @dev Reverts with InvalidVaultProof if the proof is invalid
     */
    function extractLeafFromProof(uint256[] calldata proof) external pure returns (Vault memory vault);

    /**
     * @notice Extracts the Merkle root hash encoded in a given proof
     * @dev The specific structure depends on the implementation
     * @param proof The proof containing the root hash
     * @return root The root hash extracted from the proof
     * @dev Reverts with InvalidVaultProof if the proof is invalid
     */
    function extractRootFromProof(uint256[] calldata proof) external pure returns (uint256 root);

    /**
     * @notice Extracts both the leaf (vault information) and the Merkle root hash from the proof
     * @dev The specific structure depends on the implementation
     * @param proof The proof containing both the root hash and vault information
     * @return vault The vault information extracted from the proof
     * @return root The root hash extracted from the proof
     * @dev Reverts with InvalidVaultProof if the proof is invalid
     */
    function extractVaultAndRootFromProof(uint256[] calldata proof)
        external
        pure
        returns (Vault memory vault, uint256 root);
}
