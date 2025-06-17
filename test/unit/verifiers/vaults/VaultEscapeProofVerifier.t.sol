// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "@openzeppelin/contracts/utils/Strings.sol";
import "@src/verifiers/vaults/IVaultProofVerifier.sol";
import "@src/verifiers/vaults/IVaultProofVerifier.sol";
import "@src/verifiers/vaults/IVaultProofVerifier.sol";
import "@src/verifiers/vaults/VaultEscapeProofVerifier.sol";
import "@src/withdrawals/IVaultWithdrawalProcessor.sol";
import "forge-std/Test.sol";
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
        invalidProofBadKey[0] = invalidProofBadKey[0] << 5; // Invalid starkKey
        invalidProofBadPath[10] = 0xffff << 4; // Invalid path element
    }

    function test_Constructor() public view {
        for (uint256 i = 0; i < 63; i++) {
            assertEq(verifier.lookupTables(i), ZKEVM_MAINNET_LOOKUP_TABLES[i]);
        }
    }

    function test_VerifyValidEscapeProof() public view {
        uint256[] memory validEscapeProof = fixVaultEscapes[0].proof;
        bool result = verifier.verifyVaultProof(validEscapeProof);
        assertTrue(result);
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

    function test_ExtractLeafFromProof() public view {
        IVaultProofVerifier.Vault memory vault = verifier.extractLeafFromProof(fixVaultEscapes[0].proof);
        IVaultProofVerifier.Vault memory expectedVault = fixVaultEscapes[0].vault;
        assertEq(vault.starkKey, expectedVault.starkKey);
        assertEq(vault.assetId, expectedVault.assetId);
        assertEq(vault.quantizedAmount, expectedVault.quantizedAmount);
    }

    function test_ExtractRootFromProof() public view {
        uint256 root = verifier.extractRootFromProof(fixVaultEscapes[0].proof);
        assertEq(root, fixVaultEscapes[0].root);
    }

    function test_ExtractLeafAndRootFromProof() public view {
        (IVaultProofVerifier.Vault memory vault, uint256 root) =
            verifier.extractLeafAndRootFromProof(fixVaultEscapes[0].proof);

        IVaultProofVerifier.Vault memory expectedVault = fixVaultEscapes[0].vault;
        uint256 expectedRoot = fixVaultEscapes[0].root;

        assertEq(vault.starkKey, expectedVault.starkKey);
        assertEq(vault.assetId, expectedVault.assetId);
        assertEq(vault.quantizedAmount, expectedVault.quantizedAmount);
        assertEq(root, expectedRoot);
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
        verifier.extractLeafAndRootFromProof(new uint256[](67));
    }
}
