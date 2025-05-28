// SPDX-License-Identifier: Apache-2.0.
pragma solidity ^0.8.27;

// @title IVaultProofVerifier
// @notice This interface defines the functions for verifying Immutable X vault escape proofs.
// @dev The escape proof is used to prove the balance of an Immutable X vault against a specific Merkle Root.
//      The prover does not need to know the Merkle Root, but only the vault information and the proof.
abstract contract IVaultProofVerifier {
    // @notice The Vault struct represents the information of a vault.
    // @param starkKey The Stark key of the user
    // @param assetId The identifier of the asset in the vault.
    // @param quantizedAmount The amount of the asset in the vault, quantized.
    struct Vault {
        uint256 starkKey;
        uint256 assetId;
        uint256 quantizedAmount;
    }

    // @notice InvalidVaultProof is a general error thrown when the vault proof validation fails. Specific reasons for the failure are included in the message.
    // TODO: Consider adding specific error messages for common failure scenarios
    error InvalidVaultProof(string message);

    /*
     * @notice verifyProof verifies the escape proof for a vault.
     * @param proof The proof to be verified, which includes the vault information, the root and the Merkle proof. Specific structure depends on the implementation.
     * @return bool Returns true if the proof is valid. The function might return false or revert with an `InvalidVaultProof` error if the proof is invalid.
     */
    function verifyProof(uint256[] calldata proof) external view virtual returns (bool);
    /*
     * @notice extractLeafFromProof extracts the leaf (vault information) from the proof.
     * @param proof The proof to be processed, which includes the vault information. Specific structure depends on the implementation.
     * @return Vault Returns the vault information extracted from the proof. Throws `InvalidVaultProof` if the proof is invalid.
     */
    function extractLeafFromProof(uint256[] calldata proof) external pure virtual returns (Vault memory);
    /*
     * @notice extractRootFromProof extracts the Merkle root hash from the proof.
     * @param proof The proof to be processed, which includes the root. Specific structure depends on the implementation.
     * @return uint256 Returns the root extracted from the proof. Throws `InvalidVaultProof` if the proof is invalid.
     */
    function extractRootFromProof(uint256[] calldata proof) external pure virtual returns (uint256);

    /*
     * @notice extractLeafAndRootFromProof extracts both the leaf (vault information) and the Merkle root hash from the proof.
     * @param proof The proof to be processed, which includes the vault information and the root. Specific structure depends on the implementation.
     * @return Vault Returns the vault information extracted from the proof. Throws `InvalidVaultProof` if the proof is invalid.
     * @return uint256 Returns the root extracted from the proof. Throws `InvalidVaultProof` if the proof is invalid.
     * @see extractLeafFromProof
     * @see extractRootFromProof
     */
    function extractLeafAndRootFromProof(uint256[] calldata proof)
        external
        pure
        virtual
        returns (Vault memory, uint256);
}
