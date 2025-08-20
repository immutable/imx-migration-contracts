// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import "@src/verifiers/accounts/AccountProofVerifier.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts/utils/cryptography/Hashes.sol";

/**
 * @title TestAccountProofVerifier
 * @notice Concrete implementation of AccountProofVerifier for testing purposes
 */
contract TestAccountProofVerifier is AccountProofVerifier {
    /**
     * @notice Public wrapper for _verifyAccountProof to enable testing
     */
    function verifyAccountProof(uint256 starkKey, address ethAddress, bytes32 accountRoot, bytes32[] calldata proof)
        external
        pure
        returns (bool)
    {
        _verifyAccountProof(starkKey, ethAddress, accountRoot, proof);
        return true;
    }

    /**
     * @notice Helper function to compute the expected leaf hash
     */
    function computeLeafHash(uint256 starkKey, address ethAddress) external pure returns (bytes32) {
        return Hashes.commutativeKeccak256(bytes32(starkKey), bytes32(uint256(uint160(ethAddress))));
    }
}

contract AccountProofVerifierTest is Test {
    TestAccountProofVerifier public verifier;

    // Test data
    uint256 constant STARK_KEY = 0x1234567890123456789012345678901234567890123456789012345678901234;
    address constant ETH_ADDRESS = 0x742d35Cc6634C0532925A3B8D4C9dB96C4B4d8B6;

    function setUp() public {
        verifier = new TestAccountProofVerifier();
    }

    function test_VerifyValidAccountProof() public view {
        // Create a simple Merkle tree with our test data
        bytes32 leaf = verifier.computeLeafHash(STARK_KEY, ETH_ADDRESS);

        // For a single leaf, the proof is empty and the root is the leaf itself
        bytes32[] memory proof = new bytes32[](0);
        bytes32 singleLeafRoot = leaf;

        bool result = verifier.verifyAccountProof(STARK_KEY, ETH_ADDRESS, singleLeafRoot, proof);
        assertTrue(result, "Valid account proof should verify successfully");
    }

    function test_VerifyValidAccountProof_WithMerklePath() public view {
        // Create a more complex Merkle tree structure
        bytes32 leaf = verifier.computeLeafHash(STARK_KEY, ETH_ADDRESS);

        // Create a simple 2-leaf tree for testing
        bytes32 leaf2 = keccak256(abi.encodePacked("another leaf"));
        bytes32[] memory proof = new bytes32[](1);
        proof[0] = leaf2;

        // Root = hash(leaf, leaf2) for a 2-leaf tree
        bytes32 root = keccak256(abi.encodePacked(leaf, leaf2));

        bool result = verifier.verifyAccountProof(STARK_KEY, ETH_ADDRESS, root, proof);
        assertTrue(result, "Valid account proof with Merkle path should verify successfully");
    }

    function test_RevertIf_InvalidMerkleProof() public {
        // Create an invalid proof
        bytes32[] memory invalidProof = new bytes32[](1);
        invalidProof[0] = keccak256(abi.encodePacked("invalid sibling"));

        // Use a different root that doesn't match the proof
        bytes32 invalidRoot = keccak256(abi.encodePacked("invalid root"));

        vm.expectRevert(
            abi.encodeWithSelector(AccountProofVerifier.InvalidAccountProof.selector, "Invalid merkle proof")
        );
        verifier.verifyAccountProof(STARK_KEY, ETH_ADDRESS, invalidRoot, invalidProof);
    }

    function test_RevertIf_InvalidStarkKey() public {
        // Use a different Stark key than what the root was computed with
        uint256 wrongStarkKey = 0x9999999999999999999999999999999999999999999999999999999999999999;

        bytes32 leaf = verifier.computeLeafHash(STARK_KEY, ETH_ADDRESS);
        bytes32[] memory proof = new bytes32[](0);
        bytes32 singleLeafRoot = leaf;

        vm.expectRevert(
            abi.encodeWithSelector(AccountProofVerifier.InvalidAccountProof.selector, "Invalid merkle proof")
        );
        verifier.verifyAccountProof(wrongStarkKey, ETH_ADDRESS, singleLeafRoot, proof);
    }

    function test_RevertIf_InvalidEthAddress() public {
        // Use a different Ethereum address than what the root was computed with
        address wrongEthAddress = 0x9999999999999999999999999999999999999999;

        bytes32 leaf = verifier.computeLeafHash(STARK_KEY, ETH_ADDRESS);
        bytes32[] memory proof = new bytes32[](0);
        bytes32 singleLeafRoot = leaf;

        vm.expectRevert(
            abi.encodeWithSelector(AccountProofVerifier.InvalidAccountProof.selector, "Invalid merkle proof")
        );
        verifier.verifyAccountProof(STARK_KEY, wrongEthAddress, singleLeafRoot, proof);
    }

    function test_RevertIf_InvalidAccountRoot() public {
        bytes32[] memory proof = new bytes32[](0);

        // Use a completely different root
        bytes32 invalidRoot = keccak256(abi.encodePacked("completely different root"));

        vm.expectRevert(
            abi.encodeWithSelector(AccountProofVerifier.InvalidAccountProof.selector, "Invalid merkle proof")
        );
        verifier.verifyAccountProof(STARK_KEY, ETH_ADDRESS, invalidRoot, proof);
    }

    function test_VerifyAccountProof_EdgeCases() public view {
        // Test with zero Stark key
        uint256 zeroStarkKey = 0;
        bytes32 leaf = verifier.computeLeafHash(zeroStarkKey, ETH_ADDRESS);
        bytes32[] memory proof = new bytes32[](0);
        bytes32 singleLeafRoot = leaf;

        bool result = verifier.verifyAccountProof(zeroStarkKey, ETH_ADDRESS, singleLeafRoot, proof);
        assertTrue(result, "Zero Stark key should be valid");

        // Test with zero address
        address zeroAddress = address(0);
        leaf = verifier.computeLeafHash(STARK_KEY, zeroAddress);
        singleLeafRoot = leaf;

        result = verifier.verifyAccountProof(STARK_KEY, zeroAddress, singleLeafRoot, proof);
        assertTrue(result, "Zero address should be valid");
    }

    function test_VerifyAccountProof_MultipleProofs() public view {
        // Test with different Stark keys and addresses
        uint256[] memory starkKeys = new uint256[](3);
        address[] memory ethAddresses = new address[](3);

        starkKeys[0] = 0x1111111111111111111111111111111111111111111111111111111111111111;
        starkKeys[1] = 0x2222222222222222222222222222222222222222222222222222222222222222;
        starkKeys[2] = 0x3333333333333333333333333333333333333333333333333333333333333333;

        ethAddresses[0] = 0x1111111111111111111111111111111111111111;
        ethAddresses[1] = 0x2222222222222222222222222222222222222222;
        ethAddresses[2] = 0x3333333333333333333333333333333333333333;

        for (uint256 i = 0; i < 3; i++) {
            bytes32 leaf = verifier.computeLeafHash(starkKeys[i], ethAddresses[i]);
            bytes32[] memory proof = new bytes32[](0);
            bytes32 singleLeafRoot = leaf;

            bool result = verifier.verifyAccountProof(starkKeys[i], ethAddresses[i], singleLeafRoot, proof);
            assertTrue(result, string(abi.encodePacked("Proof ", vm.toString(i), " should be valid")));
        }
    }

    function test_ComputeLeafHash_Consistency() public view {
        // Test that the leaf hash computation is consistent
        bytes32 leaf1 = verifier.computeLeafHash(STARK_KEY, ETH_ADDRESS);
        bytes32 leaf2 = verifier.computeLeafHash(STARK_KEY, ETH_ADDRESS);

        assertEq(leaf1, leaf2, "Leaf hash computation should be consistent");

        // Test that different inputs produce different hashes
        bytes32 leaf3 = verifier.computeLeafHash(STARK_KEY + 1, ETH_ADDRESS);
        assertTrue(leaf1 != leaf3, "Different Stark keys should produce different hashes");

        bytes32 leaf4 = verifier.computeLeafHash(STARK_KEY, address(uint160(ETH_ADDRESS) + 1));
        assertTrue(leaf1 != leaf4, "Different ETH addresses should produce different hashes");
    }

    function test_VerifyAccountProof_WithLongProof() public view {
        // Test with a longer Merkle proof (simulating deeper tree)
        bytes32 leaf = verifier.computeLeafHash(STARK_KEY, ETH_ADDRESS);

        // Create a 2-level proof (simpler to construct correctly)
        bytes32[] memory proof = new bytes32[](2);
        proof[0] = keccak256(abi.encodePacked("sibling1"));
        proof[1] = keccak256(abi.encodePacked("sibling2"));

        // Compute the expected root by building the tree correctly
        // For a 2-level proof, we need to hash the leaf with the first sibling
        bytes32 level1Hash = keccak256(abi.encodePacked(leaf, proof[0]));
        // Then hash that result with the second sibling
        bytes32 root = keccak256(abi.encodePacked(level1Hash, proof[1]));

        bool result = verifier.verifyAccountProof(STARK_KEY, ETH_ADDRESS, root, proof);
        assertTrue(result, "Long proof should verify successfully");
    }

    function test_ErrorSelector() public pure {
        // Test that the error selector can be encoded
        bytes memory encodedError =
            abi.encodeWithSelector(AccountProofVerifier.InvalidAccountProof.selector, "Test error");
        assertTrue(encodedError.length > 0, "Error should be encodable");

        bytes4 expectedSelector = AccountProofVerifier.InvalidAccountProof.selector;
        assertEq(bytes4(encodedError), expectedSelector, "Error selector should match");
    }
}
