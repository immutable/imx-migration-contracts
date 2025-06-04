// SPDX-License-Identifier: Apache-2.0.
pragma solidity ^0.8.18;

import {IAccountProofVerifier} from "./IAccountProofVerifier.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

contract AccountProofVerifier is IAccountProofVerifier {
    uint256 internal constant K_MODULUS = 0x800000000000011000000000000000000000000000000000000000000000001;
    bytes32 public immutable merkleRoot;

    constructor(bytes32 _merkleRoot) {
        merkleRoot = _merkleRoot;
    }

    function verify(uint256 starkKey, address ethAddress, bytes32[] calldata proof) external view returns (bool) {
        require(starkKey != 0 && starkKey >> 252 == 0 && starkKey < K_MODULUS, "Invalid stark key");
        require(ethAddress != address(0), "Invalid Ethereum address");
        require(proof.length > 0, "Proof must not be empty");
        bytes32 leaf = keccak256(abi.encode(starkKey, ethAddress));

        bool isValid = MerkleProof.verify(proof, merkleRoot, leaf);

        if (!isValid) {
            revert InvalidAccountProof("Invalid merkle proof");
        }

        return true;
    }
}
