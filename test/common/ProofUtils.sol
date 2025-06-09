// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/cryptography/Hashes.sol";
import "forge-std/console.sol";

contract ProofUtils {
    function _sortLeaves(bytes32[] memory _leaves) internal pure returns (bytes32[] memory) {
        for (uint256 i = 0; i < _leaves.length; i++) {
            for (uint256 j = i + 1; j < _leaves.length; j++) {
                if (_leaves[i] < _leaves[j]) {
                    bytes32 temp = _leaves[i];
                    _leaves[i] = _leaves[j];
                    _leaves[j] = temp;
                }
            }
        }
        return _leaves;
    }

    function _computeMerkleRoot(bytes32[] memory _leaves) internal pure returns (bytes32) {
        if (_leaves.length == 0) return bytes32(0);
        if (_leaves.length == 1) return _leaves[0];

        bytes32[] memory nodes = new bytes32[]((_leaves.length + 1) / 2);
        for (uint256 i = 0; i < _leaves.length; i += 2) {
            if (i + 1 == _leaves.length) {
                nodes[i / 2] = _leaves[i];
            } else {
                nodes[i / 2] = Hashes.commutativeKeccak256(_leaves[i], _leaves[i + 1]);
            }
        }
        return _computeMerkleRoot(nodes);
    }

    function _getMerkleProof(bytes32[] memory _leaves, uint256 _index) internal pure returns (bytes32[] memory) {
        if (_leaves.length == 0) return new bytes32[](0);
        if (_leaves.length == 1) return new bytes32[](0);

        bytes32[] memory proof = new bytes32[](32); // Maximum depth
        uint256 proofLength = 0;

        bytes32[] memory nodes = _leaves;
        uint256 index = _index;

        while (nodes.length > 1) {
            if (index % 2 == 0) {
                if (index + 1 < nodes.length) {
                    proof[proofLength++] = nodes[index + 1];
                }
            } else {
                proof[proofLength++] = nodes[index - 1];
            }

            bytes32[] memory newNodes = new bytes32[]((nodes.length + 1) / 2);
            for (uint256 i = 0; i < nodes.length; i += 2) {
                if (i + 1 == nodes.length) {
                    newNodes[i / 2] = nodes[i];
                } else {
                    newNodes[i / 2] = Hashes.commutativeKeccak256(nodes[i], nodes[i + 1]);
                }
            }
            nodes = newNodes;
            index = index / 2;
        }
        // Resize proof array to actual length
        bytes32[] memory trimmedProof = new bytes32[](proofLength);
        for (uint256 i = 0; i < proofLength; i++) {
            trimmedProof[i] = proof[i];
        }
        return trimmedProof;
    }
}
