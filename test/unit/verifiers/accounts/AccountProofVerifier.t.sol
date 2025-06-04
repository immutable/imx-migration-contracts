// SPDX-License-Identifier: Apache-2.0.
pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {AccountProofVerifier} from "@src/verifiers/accounts/AccountProofVerifier.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {IAccountProofVerifier} from "@src/verifiers/accounts/IAccountProofVerifier.sol";
import {console} from "forge-std/console.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

contract AccountProofVerifierTest is Test {
    AccountProofVerifier private verifier;
    bytes32 private merkleRoot;
    bytes32[] private leaves;
    bytes32[] private testProof;
    // Create test data
    uint256 private starkKey = 0x12345;
    address private ethAddress = address(0x1234567890123456789012345678901234567890);

    function setUp() public {
        // Create leaf
        bytes32 leaf = keccak256(abi.encode(starkKey, ethAddress));
        leaves = new bytes32[](4);
        leaves[0] = leaf;
        leaves[1] = keccak256(abi.encode(0x67890, address(0x09876)));
        leaves[2] = keccak256(abi.encode(0xabcdef, address(0xabcd)));
        leaves[3] = keccak256(abi.encode(0xbbbbbb, address(0xbbcde)));

        // Sort leaves for consistent tree construction
        _sortLeaves(leaves);

        // Create merkle tree
        merkleRoot = _computeRoot(leaves);

        // Deploy verifier
        verifier = new AccountProofVerifier(merkleRoot);

        // Get proof
        testProof = _getProof(leaves, 0);

        // Debug logs
        console.log("Leaf:", string(abi.encode(leaf)));
        console.log("Merkle Root:", string(abi.encode(merkleRoot)));
        console.log("Proof Length:", testProof.length);
        for (uint256 i = 0; i < testProof.length; i++) {
            console.log("Proof[", i, "]:", string(abi.encode(testProof[i])));
        }
    }

    function test_VerifyValidProof() public view {
        bytes32 leaf = keccak256(abi.encode(starkKey, ethAddress));
        console.log("Leaf in test:", string(abi.encode(leaf)));
        console.log("Merkle Root in test:", string(abi.encode(verifier.merkleRoot())));

        bool isValid = verifier.verify(starkKey, ethAddress, testProof);
        assertTrue(isValid, "Merkle proof verification failed");
    }

    function test_RevertIf_InvalidStarkKey() public {
        uint256 invalidStarkKey = 0x800000000000011000000000000000000000000000000000000000000000002;
        vm.expectRevert("Invalid stark key");
        verifier.verify(invalidStarkKey, ethAddress, testProof);
    }

    function test_RevertIf_ZeroStarkKey() public {
        vm.expectRevert("Invalid stark key");
        verifier.verify(0, ethAddress, testProof);
    }

    function test_RevertIf_ZeroAddress() public {
        vm.expectRevert("Invalid Ethereum address");
        verifier.verify(starkKey, address(0), testProof);
    }

    function test_RevertIf_EmptyProof() public {
        bytes32[] memory emptyProof = new bytes32[](0);

        vm.expectRevert("Proof must not be empty");
        verifier.verify(starkKey, ethAddress, emptyProof);
    }

    function test_RejectInvalidProof() public {
        // Modify first proof element
        bytes32[] memory invalidProof = new bytes32[](testProof.length);
        for (uint256 i = 0; i < testProof.length; i++) {
            invalidProof[i] = testProof[i];
        }
        invalidProof[0] = keccak256("invalid");

        vm.expectRevert(
            abi.encodeWithSelector(IAccountProofVerifier.InvalidAccountProof.selector, "Invalid merkle proof")
        );
        verifier.verify(starkKey, ethAddress, invalidProof);
    }

    function test_RejectNonExistentLeaf() public {
        uint256 nonExistentStarkKey = 0xabcdef;
        address nonExistentEthAddress = address(0xabCDEF1234567890ABcDEF1234567890aBCDeF12);

        vm.expectRevert(
            abi.encodeWithSelector(IAccountProofVerifier.InvalidAccountProof.selector, "Invalid merkle proof")
        );
        verifier.verify(nonExistentStarkKey, nonExistentEthAddress, testProof);
    }

    // Helper functions
    function _sortLeaves(bytes32[] memory _leaves) internal pure {
        for (uint256 i = 0; i < _leaves.length; i++) {
            for (uint256 j = i + 1; j < _leaves.length; j++) {
                if (_leaves[i] < _leaves[j]) {
                    bytes32 temp = _leaves[i];
                    _leaves[i] = _leaves[j];
                    _leaves[j] = temp;
                }
            }
        }
    }

    function _computeRoot(bytes32[] memory _leaves) internal pure returns (bytes32) {
        if (_leaves.length == 0) return bytes32(0);
        if (_leaves.length == 1) return _leaves[0];

        bytes32[] memory nodes = new bytes32[]((_leaves.length + 1) / 2);
        for (uint256 i = 0; i < _leaves.length; i += 2) {
            if (i + 1 == _leaves.length) {
                nodes[i / 2] = _leaves[i];
            } else {
                // Sort the pair before hashing
                bytes32 left = _leaves[i];
                bytes32 right = _leaves[i + 1];
                if (left > right) {
                    bytes32 temp = left;
                    left = right;
                    right = temp;
                }
                nodes[i / 2] = keccak256(abi.encode(left, right));
            }
        }
        return _computeRoot(nodes);
    }

    function _getProof(bytes32[] memory _leaves, uint256 _index) internal pure returns (bytes32[] memory) {
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
                    // Use abi.encode instead of abi.encodePacked for consistency
                    newNodes[i / 2] = keccak256(abi.encode(nodes[i], nodes[i + 1]));
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
