// SPDX-License-Identifier: Apache-2.0.
pragma solidity ^0.8.27;

import {IAccountProofVerifier} from "./IAccountProofVerifier.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import "forge-std/console.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {Hashes} from "@openzeppelin/contracts/utils/cryptography/Hashes.sol";

contract AccountProofVerifier is IAccountProofVerifier, Ownable {
    uint256 internal constant K_MODULUS = 0x800000000000011000000000000000000000000000000000000000000000001;
    bytes32 public accountRoot;
    address public immutable rootProvider;

    constructor(address _rootProvider) Ownable(_rootProvider) {}

    function verifyAccountProof(uint256 starkKey, address ethAddress, bytes32[] calldata proof)
        external
        view
        returns (bool)
    {
        require(starkKey != 0 && starkKey < K_MODULUS, "Invalid stark key");
        require(ethAddress != address(0), "Invalid Ethereum address");
        require(proof.length > 0, "Proof must not be empty");
        bytes32 leaf = Hashes.commutativeKeccak256(bytes32(starkKey), bytes32(uint256(uint160(ethAddress))));

        console.log("Stark key: %s, Leaf: %s", starkKey, Strings.toHexString(uint256(leaf), 32));
        bool isValid = MerkleProof.verify(proof, accountRoot, leaf);

        if (!isValid) {
            revert InvalidAccountProof("Invalid merkle proof");
        }

        return true;
    }

    // TODO: Account root should be set only once
    function setAccountRoot(bytes32 newRoot) external onlyOwner {
        // TODO: Add validation of the account root
        accountRoot = newRoot;
    }
}
