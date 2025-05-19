// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "../../../src/assets/AssetsRegistry.sol";
import "../common/FixVaultEscapes.sol";
import "@src/assets/AssetsRegistry.sol";
import "@src/assets/AssetsRegistry.sol";
import "@src/assets/AssetsRegistry.sol";
import "@src/proofs/accounts/IAccountProofVerifier.sol";
import "@src/proofs/vaults/VaultEscapeProofVerifier.sol";
import "@src/withdrawals/IVaultEscapeProcessor.sol";
import "@src/withdrawals/VaultEscapeProcessor.sol";
import "forge-std/Test.sol";
import {FixVaultEscapes} from "../common/FixVaultEscapes.sol";
import {FixtureAssets} from "../common/FixtureAssets.sol";
import {FixtureLookupTables} from "../common/FixtureLookupTables.sol";

contract MockAccountVerifier is IAccountProofVerifier {
    bool public shouldVerify;

    function setShouldVerify(bool _shouldVerify) external {
        shouldVerify = _shouldVerify;
    }

    function verify(uint256, address, bytes32[] calldata) external view override returns (bool) {
        return shouldVerify;
    }
}

contract MockVaultVerifier is VaultEscapeProofVerifier {
    bool public shouldVerify;

    constructor(address[63] memory lookupTables) VaultEscapeProofVerifier(lookupTables) {}

    function setShouldVerify(bool _shouldVerify) external {
        shouldVerify = _shouldVerify;
    }

    function verifyEscapeProof(uint256[] calldata) external view override returns (bool) {
        return shouldVerify;
    }
}

// TODO: Add tests ETH claims
contract VaultEscapeProcessorTest is Test, FixVaultEscapes, FixtureAssets, FixtureLookupTables {
    VaultEscapeProcessor private vaultEscapeProcessor;
    MockAccountVerifier private accountVerifier;
    MockVaultVerifier private vaultVerifier;

    uint256[] private invalidProofBadKey;
    uint256[] private invalidProofBadPath;
    address private recipient = address(0xA123);

    function setUp() public {
        string memory ETH_RPC_URL = vm.envString("ETH_RPC_URL");
        vm.createSelectFork(ETH_RPC_URL);

        accountVerifier = new MockAccountVerifier();
        vaultVerifier = new MockVaultVerifier(ETH_LOOKUP_TABLES);

        vaultEscapeProcessor = new VaultEscapeProcessor(
            address(accountVerifier), address(vaultVerifier), fixVaultEscapes[0].root, fixAssets
        );
    }

    function test_Constructor() public view {
        assertEq(address(vaultEscapeProcessor.accountVerifier()), address(accountVerifier));

        assertEq(address(vaultEscapeProcessor.vaultVerifier()), address(vaultVerifier));

        assertEq(vaultEscapeProcessor.vaultRoot(), fixVaultEscapes[0].root);

        for (uint256 i = 0; i < fixAssets.length; i++) {
            assertEq(vaultEscapeProcessor.getAssetAddress(fixAssets[i].assetId), fixAssets[i].assetAddress);
            assertEq(vaultEscapeProcessor.getAssetQuantum(fixAssets[i].assetId), fixAssets[i].quantum);
        }
    }

    function test_RevertIf_Constructor_ZeroVaultRoot() public {
        vm.expectRevert("Invalid vault root");
        new VaultEscapeProcessor(address(accountVerifier), address(vaultVerifier), 0, fixAssets);
    }

    function test_RevertIf_Constructor_ZeroAccountVerifier() public {
        vm.expectRevert("Invalid account verifier address");
        new VaultEscapeProcessor(address(0), address(vaultVerifier), fixVaultEscapes[0].root, fixAssets);
    }

    function test_RevertIf_Constructor_ZeroVaultVerifier() public {
        vm.expectRevert("Invalid vault verifier address");
        new VaultEscapeProcessor(address(accountVerifier), address(0), fixVaultEscapes[0].root, fixAssets);
    }

    function test_RevertIf_Constructor_EmptyAssets() public {
        vm.expectRevert(abi.encodeWithSelector(AssetsRegistry.InvalidAssetDetails.selector, "No assets to register"));
        new VaultEscapeProcessor(
            address(accountVerifier),
            address(vaultVerifier),
            fixVaultEscapes[0].root,
            new AssetsRegistry.AssetDetails[](0)
        );
    }

    function test_ProcessValidEscapeClaim_IMX() public {
        bytes32[] memory accountProof = new bytes32[](0);
        accountVerifier.setShouldVerify(true);
        vaultVerifier.setShouldVerify(true);

        uint256 expectedTransfer = vaultEscapeProcessor.getAssetQuantum(fixVaultEscapes[0].vault.assetId)
            * fixVaultEscapes[0].vault.quantizedAmount;

        vm.deal(address(vaultEscapeProcessor), 1 ether);
        assertEq(recipient.balance, 0 ether);
        bool success =
            vaultEscapeProcessor.verifyProofAndDisburseFunds(recipient, accountProof, fixVaultEscapes[0].proof);

        assertTrue(success);
        assertTrue(
            vaultEscapeProcessor.isClaimProcessed(fixVaultEscapes[0].vault.starkKey, fixVaultEscapes[0].vault.assetId)
        );
        assertEq(recipient.balance, expectedTransfer);
    }

    function test_ProcessValidEscapeClaim_ERC20() public {
        bytes32[] memory accountProof = new bytes32[](0);
        accountVerifier.setShouldVerify(true);
        vaultVerifier.setShouldVerify(true);

        VaultWithProof memory testVaultWithProof = fixVaultEscapes[2];
        uint256 assetId = testVaultWithProof.vault.assetId;

        IERC20 token = IERC20(vaultEscapeProcessor.getAssetAddress(assetId));
        console.log("token address", address(token));

        uint256 expectedTransfer =
            vaultEscapeProcessor.getAssetQuantum(assetId) * testVaultWithProof.vault.quantizedAmount;

        deal(address(token), address(vaultEscapeProcessor), 1 ether);
        assertEq(token.balanceOf(recipient), 0);
        bool success =
            vaultEscapeProcessor.verifyProofAndDisburseFunds(recipient, accountProof, testVaultWithProof.proof);

        assertTrue(success);
        assertTrue(
            vaultEscapeProcessor.isClaimProcessed(testVaultWithProof.vault.starkKey, testVaultWithProof.vault.assetId)
        );
        assertEq(token.balanceOf(recipient), expectedTransfer);
    }

    function test_RevertIf_InvalidAccountProof() public {
        bytes32[] memory accountProof = new bytes32[](0);
        accountVerifier.setShouldVerify(false);
        vaultVerifier.setShouldVerify(true);

        vm.expectRevert(
            abi.encodeWithSelector(
                IVaultEscapeProcessor.InvalidAccountProof.selector, fixVaultEscapes[0].vault.starkKey, recipient
            )
        );
        vaultEscapeProcessor.verifyProofAndDisburseFunds(recipient, accountProof, fixVaultEscapes[0].proof);
    }

    function test_RevertIf_InvalidVaultProof() public {
        bytes32[] memory accountProof = new bytes32[](0);
        accountVerifier.setShouldVerify(true);
        vaultVerifier.setShouldVerify(false);

        vm.expectRevert(abi.encodeWithSelector(IVaultEscapeProcessor.InvalidVaultProof.selector, "Invalid vault proof"));
        vaultEscapeProcessor.verifyProofAndDisburseFunds(recipient, accountProof, fixVaultEscapes[0].proof);
    }

    function test_RevertIf_ClaimAlreadyProcessed() public {
        bytes32[] memory accountProof = new bytes32[](0);
        accountVerifier.setShouldVerify(true);
        vaultVerifier.setShouldVerify(true);

        vm.deal(address(vaultEscapeProcessor), 1 ether);

        vaultEscapeProcessor.verifyProofAndDisburseFunds(recipient, accountProof, fixVaultEscapes[0].proof);

        vm.expectRevert(
            abi.encodeWithSelector(
                IVaultEscapeProcessor.FundAlreadyDisbursedForVault.selector,
                fixVaultEscapes[0].vault.starkKey,
                fixVaultEscapes[0].vault.assetId
            )
        );
        vaultEscapeProcessor.verifyProofAndDisburseFunds(recipient, accountProof, fixVaultEscapes[0].proof);
    }

    function test_RevertIf_UnregisteredAsset() public {
        bytes32[] memory accountProof = new bytes32[](0);
        accountVerifier.setShouldVerify(true);
        vaultVerifier.setShouldVerify(true);

        uint256[] memory proofWithUnregisteredAsset = fixVaultEscapes[1].proof;

        vm.expectRevert(
            abi.encodeWithSelector(IVaultEscapeProcessor.AssetNotRegistered.selector, fixVaultEscapes[1].vault.assetId)
        );
        vaultEscapeProcessor.verifyProofAndDisburseFunds(recipient, accountProof, proofWithUnregisteredAsset);
    }

    function test_RevertIf_InsufficientBalance() public {
        bytes32[] memory accountProof = new bytes32[](0);
        accountVerifier.setShouldVerify(true);
        vaultVerifier.setShouldVerify(true);

        uint256 expectedAmount = vaultEscapeProcessor.getAssetQuantum(fixVaultEscapes[0].vault.assetId)
            * fixVaultEscapes[0].vault.quantizedAmount;

        vm.expectRevert(
            abi.encodeWithSelector(
                IVaultEscapeProcessor.InsufficientContractBalance.selector,
                vaultEscapeProcessor.NATIVE_IMX_ADDRESS(),
                expectedAmount,
                0
            )
        );
        vaultEscapeProcessor.verifyProofAndDisburseFunds(recipient, accountProof, fixVaultEscapes[0].proof);
    }
}
