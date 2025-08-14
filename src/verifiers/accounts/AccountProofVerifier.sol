// Copyright Immutable Pty Ltd 2018 - 2025
// SPDX-License-Identifier: Apache-2.0.
pragma solidity ^0.8.27;

import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {Hashes} from "@openzeppelin/contracts/utils/cryptography/Hashes.sol";

/**
 * @title Account Association Proof Verifier
 * @notice Verifies that a proof of account associations is correct against a stored Merkle root.
 * @dev An account association, refers to a Stark key <> Ethereum address mapping. A Merkle tree of such account associations is stored off-chain.
 * @dev Given an Merkle root of the off-chain tree, and a Merkle proof of an association (Stark key and ETH address), this contract can verify that the association is valid.
 */
abstract contract AccountProofVerifier {
    /// @notice Thrown when the provided account proof is invalid or malformed
    /// @param message A descriptive error message explaining the proof validation failure
    error InvalidAccountProof(string message);

    /**
     * @notice Verifies a cryptographic proof linking a StarkNet stark key to an Ethereum address
     * @param starkKey The StarkNet account's stark key to verify
     * @param ethAddress The Ethereum address that should be linked to the stark key
     * @param accountRoot The Merkle root of the account associations tree
     * @param proof The cryptographic proof array that establishes the relationship
     * @dev The proof should be a valid Merkle proof that demonstrates the stark key and
     *      Ethereum address are correctly linked in the account state tree
     * @dev Reverts with InvalidAccountProof if the proof is invalid
     * @dev This function assumes that all basic parameter validations are performed by the caller.
     */
    function _verifyAccountProof(uint256 starkKey, address ethAddress, bytes32 accountRoot, bytes32[] calldata proof)
        internal
        pure
    {
        bytes32 leaf = Hashes.commutativeKeccak256(bytes32(starkKey), bytes32(uint256(uint160(ethAddress))));
        bool isValid = MerkleProof.verify(proof, accountRoot, leaf);
        require(isValid, InvalidAccountProof("Invalid merkle proof"));
    }
}
