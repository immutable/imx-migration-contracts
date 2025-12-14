// Copyright Immutable Pty Ltd 2018 - 2025
// SPDX-License-Identifier: Apache-2.0.
pragma solidity ^0.8.27;

import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {Hashes} from "@openzeppelin/contracts/utils/cryptography/Hashes.sol";

/**
 * @title Account Proof Verifier
 * @notice Verifies that a Merkle proof for a Stark key to Ethereum address association is valid, given a Merkle root of an account associations tree.
 * @dev This contract does not maintain an account root itself, but rather provides a function to verify proofs against a provided Merkle root.
 * @dev SECURITY NOTE: This contract uses commutativeKeccak256 for leaf computation, where H(a, b) == H(b, a).
 *      This creates a theoretical collision risk if a user's starkKey < 2^160. However, this risk is mitigated by:
 *      (1) Withdrawals are executed by a trusted DISBURSER_ROLE, not directly by users - attackers cannot exploit directly.
 *      (2) The account Merkle tree is generated off-chain by trusted infrastructure - attackers cannot insert collisions.
 *      (3) The probability of a starkKey being < 2^160 is ~2^-91 (cryptographically negligible).
 */
abstract contract AccountProofVerifier {
    /// @notice Thrown when the provided account proof is invalid or malformed
    /// @param message A message describing the specific reason
    error InvalidAccountProof(string message);

    /**
     * @notice Verifies a Merkle proof of a Stark key to an Ethereum address association, against a provided Merkle root of an account associations tree.
     * @param starkKey The user's Stark key
     * @param ethAddress The Ethereum address associated with the Stark key
     * @param accountRoot The Merkle root of the account associations tree stored off-chain
     * @param proof The Merkle proof array that establishes the relationship
     * @dev Reverts with InvalidAccountProof if the proof is invalid or malformed.
     * @dev NOTE: For efficiency, this function assumes that all basic parameter validations are performed by the caller beforehand.
     */
    function _verifyAccountProof(uint256 starkKey, address ethAddress, bytes32 accountRoot, bytes32[] calldata proof)
        internal
        pure
    {
        // Compute leaf using commutative hash - see contract-level SECURITY NOTE for implications
        bytes32 leaf = Hashes.commutativeKeccak256(bytes32(starkKey), bytes32(uint256(uint160(ethAddress))));
        bool isValid = MerkleProof.verify(proof, accountRoot, leaf);
        require(isValid, InvalidAccountProof("Invalid merkle proof"));
    }
}
