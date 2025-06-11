// SPDX-License-Identifier: Apache-2.0.
pragma solidity ^0.8.18;

import "../../../common/ProofUtils.sol";
import {AccountProofVerifier} from "@src/verifiers/accounts/AccountProofVerifier.sol";
import {IAccountProofVerifier} from "@src/verifiers/accounts/IAccountProofVerifier.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";

contract AccountProofVerifierTest is Test, ProofUtils {
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

        // Create merkle tree
        merkleRoot = _computeMerkleRoot(leaves);

        // Deploy verifier
        verifier = new AccountProofVerifier(address(this));
        verifier.setAccountRoot(merkleRoot);
        // Get proof
        testProof = _getMerkleProof(leaves, 0);
    }

    function test_VerifyValidProof() public view {
        bool isValid = verifier.verifyAccountProof(starkKey, ethAddress, testProof);
        assertTrue(isValid, "Merkle proof verification failed");
    }

    function test_RevertIf_InvalidStarkKey() public {
        uint256 invalidStarkKey = 0x800000000000011000000000000000000000000000000000000000000000002;
        vm.expectRevert("Invalid stark key");
        verifier.verifyAccountProof(invalidStarkKey, ethAddress, testProof);
    }

    function test_RevertIf_ZeroStarkKey() public {
        vm.expectRevert("Invalid stark key");
        verifier.verifyAccountProof(0, ethAddress, testProof);
    }

    function test_RevertIf_ZeroAddress() public {
        vm.expectRevert("Invalid Ethereum address");
        verifier.verifyAccountProof(starkKey, address(0), testProof);
    }

    function test_RevertIf_EmptyProof() public {
        bytes32[] memory emptyProof = new bytes32[](0);

        vm.expectRevert("Proof must not be empty");
        verifier.verifyAccountProof(starkKey, ethAddress, emptyProof);
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
        verifier.verifyAccountProof(starkKey, ethAddress, invalidProof);
    }

    function test_RejectNonExistentLeaf() public {
        uint256 nonExistentStarkKey = 0xabcdef;
        address nonExistentEthAddress = address(0xabCDEF1234567890ABcDEF1234567890aBCDeF12);

        vm.expectRevert(
            abi.encodeWithSelector(IAccountProofVerifier.InvalidAccountProof.selector, "Invalid merkle proof")
        );
        verifier.verifyAccountProof(nonExistentStarkKey, nonExistentEthAddress, testProof);
    }
}
