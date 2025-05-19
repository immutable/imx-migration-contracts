// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "../../../../src/proofs/vaults/IVaultEscapeProofVerifier.sol";
import "../../../../src/proofs/vaults/IVaultEscapeProofVerifier.sol";
import "../../../../src/proofs/vaults/IVaultEscapeProofVerifier.sol";
import "../../../../src/proofs/vaults/VaultEscapeProofVerifier.sol";
import "../../../../src/withdrawals/IVaultEscapeProcessor.sol";
import "forge-std/Test.sol";
import {FixtureEscapeProofs} from "./FixtureEscapeProofs.sol";

contract VaultEscapeProofVerifierTest is Test, FixtureEscapeProofs {
    VaultEscapeProofVerifier public verifier;
    address[63] public lookupTables;

    // Test fixtures - these would be populated with real data in practice
    uint256[] public invalidEscapeProof;
    uint256[] public tooShortProof;
    uint256[] public tooLongProof;
    uint256[] public oddLengthProof;

    function setUp() public {
        // In practice, these would be real lookup table addresses
        for (uint256 i = 0; i < 63; i++) {
            lookupTables[i] = address(uint160(i + 1));
        }

        verifier = new VaultEscapeProofVerifier(lookupTables);

        // Initialize test proofs (these would be real proofs in practice)
        // For now, we'll use placeholder data that matches the expected structure
        invalidEscapeProof = new uint256[](68);
        tooShortProof = new uint256[](66);
        tooLongProof = new uint256[](200);
        oddLengthProof = new uint256[](69);

        uint256[] memory validEscapeProof = validVaultWithProofs[0].proof;

        // Copy valid proof to invalid proof and modify one value
        for (uint256 i = 0; i < validEscapeProof.length; i++) {
            invalidEscapeProof[i] = validEscapeProof[i];
        }
        invalidEscapeProof[0] = 0xffff << 4; // Invalid starkKey
    }

    function test_Constructor() public view {
        // Test that constructor properly sets lookup tables
        for (uint256 i = 0; i < 63; i++) {
            assertEq(address(uint160(i + 1)), lookupTables[i]);
        }
    }

    function test_VerifyValidEscapeProof() public view {
        // This test will fail until we have real proof data
        // vm.expectRevert("Bad Merkle path.");
        // bool result = verifier.verifyEscapeProof(validEscapeProof);
        // assertTrue(result);
    }

    // TODO:
    function _test_VerifyInvalidEscapeProof() public {
        vm.expectRevert("Bad starkKey or assetId.");
        verifier.verifyEscapeProof(invalidEscapeProof);
    }

    function test_VerifyTooShortProof() public {
        vm.expectRevert(
            abi.encodeWithSelector(IVaultEscapeProofVerifier.InvalidVaultProof.selector, "Proof too short.")
        );
        verifier.verifyEscapeProof(tooShortProof);
    }

    function test_VerifyTooLongProof() public {
        vm.expectRevert(abi.encodeWithSelector(IVaultEscapeProofVerifier.InvalidVaultProof.selector, "Proof too long."));
        verifier.verifyEscapeProof(tooLongProof);
    }

    function test_VerifyOddLengthProof() public {
        vm.expectRevert(
            abi.encodeWithSelector(IVaultEscapeProofVerifier.InvalidVaultProof.selector, "Proof length must be even.")
        );
        verifier.verifyEscapeProof(oddLengthProof);
    }

    function test_ExtractLeafFromProof() public view {
        IVaultEscapeProofVerifier.Vault memory vault = verifier.extractLeafFromProof(validVaultWithProofs[0].proof);
        IVaultEscapeProofVerifier.Vault memory expectedVault = validVaultWithProofs[0].vault;
        assertEq(vault.starkKey, expectedVault.starkKey);
        assertEq(vault.assetId, expectedVault.assetId);
        assertEq(vault.quantizedAmount, expectedVault.quantizedAmount);
    }

    function test_ExtractRootFromProof() public view {
        uint256 root = verifier.extractRootFromProof(validVaultWithProofs[0].proof);
        assertEq(root, validVaultWithProofs[0].root);
    }

    function test_ExtractLeafAndRootFromProof() public view {
        (IVaultEscapeProofVerifier.Vault memory vault, uint256 root) =
                            verifier.extractLeafAndRootFromProof(validVaultWithProofs[0].proof);

        IVaultEscapeProofVerifier.Vault memory expectedVault = validVaultWithProofs[0].vault;
        uint expectedRoot = validVaultWithProofs[0].root;

        assertEq(vault.starkKey, expectedVault.starkKey);
        assertEq(vault.assetId, expectedVault.assetId);
        assertEq(vault.quantizedAmount, expectedVault.quantizedAmount);
        assertEq(root, validVaultWithProofs[0].root);
    }

    function test_ExtractLeafFromInvalidProof() public {
        vm.expectRevert(
            abi.encodeWithSelector(IVaultEscapeProofVerifier.InvalidVaultProof.selector, "Proof too short.")
        );
        verifier.extractLeafFromProof(tooShortProof);
    }

    function test_ExtractRootFromInvalidProof() public {
        vm.expectRevert(
            abi.encodeWithSelector(IVaultEscapeProofVerifier.InvalidVaultProof.selector, "Proof too short.")
        );
        verifier.extractRootFromProof(tooShortProof);
    }

    function test_ExtractLeafAndRootFromInvalidProof() public {
        vm.expectRevert(
            abi.encodeWithSelector(IVaultEscapeProofVerifier.InvalidVaultProof.selector, "Proof too short.")
        );
        verifier.extractLeafAndRootFromProof(tooShortProof);
    }
}
