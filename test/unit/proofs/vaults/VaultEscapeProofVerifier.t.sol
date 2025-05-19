// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "@src/proofs/vaults/IVaultEscapeProofVerifier.sol";
import "@src/proofs/vaults/IVaultEscapeProofVerifier.sol";
import "@src/proofs/vaults/IVaultEscapeProofVerifier.sol";
import "@src/proofs/vaults/VaultEscapeProofVerifier.sol";
import "@src/withdrawals/IVaultEscapeProcessor.sol";
import "forge-std/Test.sol";
import {FixVaultEscapes} from "../../common/FixVaultEscapes.sol";
import {FixtureLookupTables} from "../../common/FixtureLookupTables.sol";

contract VaultEscapeProofVerifierTest is Test, FixVaultEscapes, FixtureLookupTables {
    VaultEscapeProofVerifier public verifier;

    uint256[] private invalidProofBadKey;
    uint256[] private invalidProofBadPath;
    uint256 private forkId;

    function setUp() public {
        string memory L1_RPC_URL = vm.envString("ETH_RPC_URL");
        forkId = vm.createSelectFork(L1_RPC_URL);

        verifier = new VaultEscapeProofVerifier(ETH_LOOKUP_TABLES);

        uint256[] memory validEscapeProof = fixVaultEscapes[0].proof;

        invalidProofBadKey = new uint256[](68);
        invalidProofBadPath = new uint256[](68);
        // Copy valid proof to invalid proofs
        for (uint256 i = 0; i < validEscapeProof.length; i++) {
            invalidProofBadKey[i] = validEscapeProof[i];
            invalidProofBadPath[i] = validEscapeProof[i];
        }
        invalidProofBadKey[0] = invalidProofBadKey[0] << 4; // Invalid starkKey
        invalidProofBadPath[10] = 0xffff << 4; // Invalid path element
    }

    function test_Constructor() public view {
        for (uint256 i = 0; i < 63; i++) {
            assertEq(verifier.lookupTables(i), ETH_LOOKUP_TABLES[i]);
        }
    }

    function test_VerifyValidEscapeProof() public view {
        uint256[] memory validEscapeProof = fixVaultEscapes[0].proof;
        bool result = verifier.verifyEscapeProof(validEscapeProof);
        assertTrue(result);
    }

    function test_RevertIf_VerifyProof_WithInvalidKey() public {
        vm.expectRevert("Bad starkKey or assetId.");
        verifier.verifyEscapeProof(invalidProofBadKey);
    }

    function test_RevertIf_VerifyProof_WithInvalidPath() public {
        vm.expectRevert("Bad Merkle path.");
        verifier.verifyEscapeProof(invalidProofBadPath);
    }

    function test_RevertIf_VerifyProof_WithInvalidLength_Short() public {
        vm.expectRevert(
            abi.encodeWithSelector(IVaultEscapeProofVerifier.InvalidVaultProof.selector, "Proof too short.")
        );
        verifier.verifyEscapeProof(new uint256[](67));
    }

    function test_RevertIf_VerifyProof_WithInvalidLength_Long() public {
        vm.expectRevert(abi.encodeWithSelector(IVaultEscapeProofVerifier.InvalidVaultProof.selector, "Proof too long."));
        verifier.verifyEscapeProof(new uint256[](200));
    }

    function test_RevertIf_VerifyProof_WithInvalidLength_Odd() public {
        vm.expectRevert(
            abi.encodeWithSelector(IVaultEscapeProofVerifier.InvalidVaultProof.selector, "Proof length must be even.")
        );
        verifier.verifyEscapeProof(new uint256[](69));
    }

    function test_ExtractLeafFromProof() public view {
        IVaultEscapeProofVerifier.Vault memory vault = verifier.extractLeafFromProof(fixVaultEscapes[0].proof);
        IVaultEscapeProofVerifier.Vault memory expectedVault = fixVaultEscapes[0].vault;
        assertEq(vault.starkKey, expectedVault.starkKey);
        assertEq(vault.assetId, expectedVault.assetId);
        assertEq(vault.quantizedAmount, expectedVault.quantizedAmount);
    }

    function test_ExtractRootFromProof() public view {
        uint256 root = verifier.extractRootFromProof(fixVaultEscapes[0].proof);
        assertEq(root, fixVaultEscapes[0].root);
    }

    function test_ExtractLeafAndRootFromProof() public view {
        (IVaultEscapeProofVerifier.Vault memory vault, uint256 root) =
            verifier.extractLeafAndRootFromProof(fixVaultEscapes[0].proof);

        IVaultEscapeProofVerifier.Vault memory expectedVault = fixVaultEscapes[0].vault;
        uint256 expectedRoot = fixVaultEscapes[0].root;

        assertEq(vault.starkKey, expectedVault.starkKey);
        assertEq(vault.assetId, expectedVault.assetId);
        assertEq(vault.quantizedAmount, expectedVault.quantizedAmount);
        assertEq(root, expectedRoot);
    }

    function test_RevertIf_ExtractLeafFromInvalidProof() public {
        vm.expectRevert(
            abi.encodeWithSelector(IVaultEscapeProofVerifier.InvalidVaultProof.selector, "Proof too short.")
        );
        verifier.extractLeafFromProof(new uint256[](67));
    }

    function test_RevertIf_ExtractRootFromInvalidProof() public {
        vm.expectRevert(
            abi.encodeWithSelector(IVaultEscapeProofVerifier.InvalidVaultProof.selector, "Proof too short.")
        );
        verifier.extractRootFromProof(new uint256[](67));
    }

    function test_RevertIf_ExtractLeafAndRootFromInvalidProof() public {
        vm.expectRevert(
            abi.encodeWithSelector(IVaultEscapeProofVerifier.InvalidVaultProof.selector, "Proof too short.")
        );
        verifier.extractLeafAndRootFromProof(new uint256[](67));
    }
}
