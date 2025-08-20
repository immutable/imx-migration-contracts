// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import "@src/verifiers/vaults/IVaultProofVerifier.sol";
import "@src/verifiers/vaults/VaultEscapeProofVerifier.sol";
import {FixtureVaultEscapes} from "../../../common/FixtureVaultEscapes.sol";
import {FixtureLookupTables} from "../../../common/FixtureLookupTables.sol";

contract VaultEscapeProofVerifierTest is Test, FixtureVaultEscapes, FixtureLookupTables {
    VaultEscapeProofVerifier public verifier;

    uint256[] private invalidProofBadKey;
    uint256[] private invalidProofBadPath;

    function setUp() public {
        string memory ZKEVM_RPC_URL = vm.envString("ZKEVM_RPC_URL");
        vm.createSelectFork(ZKEVM_RPC_URL);

        verifier = new VaultEscapeProofVerifier(ZKEVM_MAINNET_LOOKUP_TABLES);

        uint256[] memory validEscapeProof = fixVaultEscapes[0].proof;

        invalidProofBadKey = new uint256[](68);
        invalidProofBadPath = new uint256[](68);
        // Copy valid proof to invalid proofs
        for (uint256 i = 0; i < validEscapeProof.length; i++) {
            invalidProofBadKey[i] = validEscapeProof[i];
            invalidProofBadPath[i] = validEscapeProof[i];
        }

        invalidProofBadKey[0] = invalidProofBadKey[0] >> 9; // Invalid starkKey
        invalidProofBadPath[10] = 0x1; // Invalid path element
    }

    function test_Constructor() public view {
        for (uint256 i = 0; i < 63; i++) {
            assertEq(verifier.lookupTables(i), ZKEVM_MAINNET_LOOKUP_TABLES[i]);
        }
    }

    function test_Constants() public view {
        assertEq(verifier.VAULT_PROOF_LENGTH(), 68, "VAULT_PROOF_LENGTH should be 68");
    }

    function test_VerifyValidEscapeProof() public view {
        uint256[] memory validEscapeProof = fixVaultEscapes[0].proof;
        bool result = verifier.verifyVaultProof(validEscapeProof);
        assertTrue(result);
    }

    function test_VerifyMultipleValidEscapeProofs() public view {
        // Test with multiple fixture proofs to ensure they all verify correctly
        for (uint256 i = 0; i < fixVaultEscapes.length; i++) {
            uint256[] memory validEscapeProof = fixVaultEscapes[i].proof;
            bool result = verifier.verifyVaultProof(validEscapeProof);
            assertTrue(result, string(abi.encodePacked("Proof ", vm.toString(i), " should be valid")));
        }
    }

    function test_RevertIf_VerifyProof_WithInvalidKey() public {
        vm.expectRevert("Bad starkKey or assetId.");
        verifier.verifyVaultProof(invalidProofBadKey);
    }

    function test_RevertIf_VerifyProof_WithInvalidPath() public {
        vm.expectRevert("Bad Merkle path.");
        verifier.verifyVaultProof(invalidProofBadPath);
    }

    function test_RevertIf_VerifyProof_WithInvalidLength_Short() public {
        vm.expectRevert(abi.encodeWithSelector(IVaultProofVerifier.InvalidVaultProof.selector, "Proof too short."));
        verifier.verifyVaultProof(new uint256[](67));
    }

    function test_RevertIf_VerifyProof_WithInvalidLength_Long() public {
        vm.expectRevert(abi.encodeWithSelector(IVaultProofVerifier.InvalidVaultProof.selector, "Proof too long."));
        verifier.verifyVaultProof(new uint256[](200));
    }

    function test_RevertIf_VerifyProof_WithInvalidLength_Odd() public {
        vm.expectRevert(
            abi.encodeWithSelector(IVaultProofVerifier.InvalidVaultProof.selector, "Proof length must be even.")
        );
        verifier.verifyVaultProof(new uint256[](69));
    }

    function test_VerifyProof_MinimumValidLength() public view {
        // Create a proof with minimum valid length (68)
        uint256[] memory minProof = new uint256[](68);
        // Copy a valid proof structure
        for (uint256 i = 0; i < 68; i++) {
            minProof[i] = fixVaultEscapes[0].proof[i];
        }
        bool result = verifier.verifyVaultProof(minProof);
        assertTrue(result, "Minimum length proof should be valid");
    }

    function test_RevertIf_VerifyProof_ExactlyAtLongLimit() public {
        vm.expectRevert(abi.encodeWithSelector(IVaultProofVerifier.InvalidVaultProof.selector, "Proof too long."));
        verifier.verifyVaultProof(new uint256[](200));
    }

    function test_ExtractLeafFromProof() public view {
        IVaultProofVerifier.Vault memory vault = verifier.extractLeafFromProof(fixVaultEscapes[0].proof);
        IVaultProofVerifier.Vault memory expectedVault = fixVaultEscapes[0].vault;
        assertEq(vault.starkKey, expectedVault.starkKey);
        assertEq(vault.assetId, expectedVault.assetId);
        assertEq(vault.quantizedBalance, expectedVault.quantizedBalance);
    }

    function test_ExtractRootFromProof() public view {
        uint256 root = verifier.extractRootFromProof(fixVaultEscapes[0].proof);
        assertEq(root, fixVaultEscapes[0].root);
    }

    function test_ExtractLeafAndRootFromProof() public view {
        (IVaultProofVerifier.Vault memory vault, uint256 root) =
            verifier.extractVaultAndRootFromProof(fixVaultEscapes[0].proof);

        IVaultProofVerifier.Vault memory expectedVault = fixVaultEscapes[0].vault;
        uint256 expectedRoot = fixVaultEscapes[0].root;

        assertEq(vault.starkKey, expectedVault.starkKey);
        assertEq(vault.assetId, expectedVault.assetId);
        assertEq(vault.quantizedBalance, expectedVault.quantizedBalance);
        assertEq(root, expectedRoot);
    }

    function test_ExtractDataFromMultipleProofs() public view {
        // Test extraction functions with multiple fixture proofs
        for (uint256 i = 0; i < fixVaultEscapes.length; i++) {
            uint256[] memory proof = fixVaultEscapes[i].proof;
            IVaultProofVerifier.Vault memory expectedVault = fixVaultEscapes[i].vault;
            uint256 expectedRoot = fixVaultEscapes[i].root;

            // Test extractLeafFromProof
            IVaultProofVerifier.Vault memory extractedVault = verifier.extractLeafFromProof(proof);
            assertEq(
                extractedVault.starkKey,
                expectedVault.starkKey,
                string(abi.encodePacked("StarkKey mismatch for proof ", vm.toString(i)))
            );
            assertEq(
                extractedVault.assetId,
                expectedVault.assetId,
                string(abi.encodePacked("AssetId mismatch for proof ", vm.toString(i)))
            );
            assertEq(
                extractedVault.quantizedBalance,
                expectedVault.quantizedBalance,
                string(abi.encodePacked("QuantizedBalance mismatch for proof ", vm.toString(i)))
            );

            // Test extractRootFromProof
            uint256 extractedRoot = verifier.extractRootFromProof(proof);
            assertEq(extractedRoot, expectedRoot, string(abi.encodePacked("Root mismatch for proof ", vm.toString(i))));

            // Test extractVaultAndRootFromProof
            (IVaultProofVerifier.Vault memory combinedVault, uint256 combinedRoot) =
                verifier.extractVaultAndRootFromProof(proof);
            assertEq(
                combinedVault.starkKey,
                expectedVault.starkKey,
                string(abi.encodePacked("Combined StarkKey mismatch for proof ", vm.toString(i)))
            );
            assertEq(
                combinedVault.assetId,
                expectedVault.assetId,
                string(abi.encodePacked("Combined AssetId mismatch for proof ", vm.toString(i)))
            );
            assertEq(
                combinedVault.quantizedBalance,
                expectedVault.quantizedBalance,
                string(abi.encodePacked("Combined QuantizedBalance mismatch for proof ", vm.toString(i)))
            );
            assertEq(
                combinedRoot,
                expectedRoot,
                string(abi.encodePacked("Combined Root mismatch for proof ", vm.toString(i)))
            );
        }
    }

    function test_RevertIf_ExtractLeafFromInvalidProof() public {
        vm.expectRevert(abi.encodeWithSelector(IVaultProofVerifier.InvalidVaultProof.selector, "Proof too short."));
        verifier.extractLeafFromProof(new uint256[](67));
    }

    function test_RevertIf_ExtractRootFromInvalidProof() public {
        vm.expectRevert(abi.encodeWithSelector(IVaultProofVerifier.InvalidVaultProof.selector, "Proof too short."));
        verifier.extractRootFromProof(new uint256[](67));
    }

    function test_RevertIf_ExtractLeafAndRootFromInvalidProof() public {
        vm.expectRevert(abi.encodeWithSelector(IVaultProofVerifier.InvalidVaultProof.selector, "Proof too short."));
        verifier.extractVaultAndRootFromProof(new uint256[](67));
    }

    function test_RevertIf_ExtractFunctions_WithOddLength() public {
        uint256[] memory oddLengthProof = new uint256[](69);

        vm.expectRevert(
            abi.encodeWithSelector(IVaultProofVerifier.InvalidVaultProof.selector, "Proof length must be even.")
        );
        verifier.extractLeafFromProof(oddLengthProof);

        vm.expectRevert(
            abi.encodeWithSelector(IVaultProofVerifier.InvalidVaultProof.selector, "Proof length must be even.")
        );
        verifier.extractRootFromProof(oddLengthProof);

        vm.expectRevert(
            abi.encodeWithSelector(IVaultProofVerifier.InvalidVaultProof.selector, "Proof length must be even.")
        );
        verifier.extractVaultAndRootFromProof(oddLengthProof);
    }

    function test_RevertIf_ExtractFunctions_WithLongProof() public {
        uint256[] memory longProof = new uint256[](200);

        vm.expectRevert(abi.encodeWithSelector(IVaultProofVerifier.InvalidVaultProof.selector, "Proof too long."));
        verifier.extractLeafFromProof(longProof);

        vm.expectRevert(abi.encodeWithSelector(IVaultProofVerifier.InvalidVaultProof.selector, "Proof too long."));
        verifier.extractRootFromProof(longProof);

        vm.expectRevert(abi.encodeWithSelector(IVaultProofVerifier.InvalidVaultProof.selector, "Proof too long."));
        verifier.extractVaultAndRootFromProof(longProof);
    }
}
