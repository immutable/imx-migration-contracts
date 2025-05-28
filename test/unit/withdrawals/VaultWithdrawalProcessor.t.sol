// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import "@src/assets/AssetsRegistry.sol";
import "@src/assets/AssetsRegistry.sol";
import "@src/assets/AssetsRegistry.sol";
import "@src/assets/AssetsRegistry.sol";
import "@src/proofs/accounts/IAccountProofVerifier.sol";
import "@src/proofs/vaults/VaultEscapeProofVerifier.sol";
import "@src/withdrawals/IVaultWithdrawalProcessor.sol";
import "@src/withdrawals/VaultWithdrawalProcessor.sol";
import "../common/FixVaultEscapes.sol";
import "../common/FixtureAssets.sol";
import "../common/FixtureLookupTables.sol";

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

// TODO: Add specific tests for existing assets, ETH, IMX and common ERC20s.
contract VaultWithdrawalProcessorTest is Test, FixVaultEscapes, FixtureAssets, FixtureLookupTables {
    VaultWithdrawalProcessor private vaultWithdrawalProcessor;
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

        vaultWithdrawalProcessor =
            new VaultWithdrawalProcessor(accountVerifier, vaultVerifier, address(this), fixAssets);
        vaultWithdrawalProcessor.setVaultRoot(fixVaultEscapes[0].root);
    }

    function test_Constructor() public view {
        assertEq(address(vaultWithdrawalProcessor.accountProofVerifier()), address(accountVerifier));

        assertEq(address(vaultWithdrawalProcessor.vaultProofVerifier()), address(vaultVerifier));

        assertEq(vaultWithdrawalProcessor.vaultRoot(), fixVaultEscapes[0].root);

        for (uint256 i = 0; i < fixAssets.length; i++) {
            assertEq(vaultWithdrawalProcessor.getAssetAddress(fixAssets[i].assetId), fixAssets[i].assetAddress);
            assertEq(vaultWithdrawalProcessor.getAssetQuantum(fixAssets[i].assetId), fixAssets[i].quantum);
        }
    }

    function test_RevertIf_Constructor_ZeroVaultRootProvider() public {
        vm.expectRevert("Invalid vault root provider address");
        new VaultWithdrawalProcessor(accountVerifier, vaultVerifier, address(0), fixAssets);
    }

    function test_RevertIf_Constructor_ZeroAccountVerifier() public {
        vm.expectRevert("Invalid account verifier address");
        new VaultWithdrawalProcessor(IAccountProofVerifier(address(0)), vaultVerifier, address(this), fixAssets);
    }

    function test_RevertIf_Constructor_ZeroVaultVerifier() public {
        vm.expectRevert("Invalid vault verifier address");
        new VaultWithdrawalProcessor(accountVerifier, IVaultEscapeProofVerifier(address(0)), address(this), fixAssets);
    }

    function test_RevertIf_Constructor_EmptyAssets() public {
        vm.expectRevert(abi.encodeWithSelector(AssetsRegistry.InvalidAssetDetails.selector, "No assets to register"));
        new VaultWithdrawalProcessor(
            accountVerifier, vaultVerifier, address(this), new AssetsRegistry.AssetDetails[](0)
        );
    }

    function test_ProcessValidEscapeClaim_IMX() public {
        bytes32[] memory accountProof = new bytes32[](0);
        accountVerifier.setShouldVerify(true);
        vaultVerifier.setShouldVerify(true);

        uint256 expectedTransfer = vaultWithdrawalProcessor.getAssetQuantum(fixVaultEscapes[0].vault.assetId)
            * fixVaultEscapes[0].vault.quantizedAmount;

        vm.deal(address(vaultWithdrawalProcessor), 1 ether);
        assertEq(recipient.balance, 0 ether);
        bool success =
            vaultWithdrawalProcessor.verifyProofAndDisburseFunds(recipient, accountProof, fixVaultEscapes[0].proof);

        assertTrue(success);
        assertTrue(
            vaultWithdrawalProcessor.isClaimProcessed(
                fixVaultEscapes[0].vault.starkKey, fixVaultEscapes[0].vault.assetId
            )
        );
        assertEq(recipient.balance, expectedTransfer);
    }

    function test_ProcessValidEscapeClaim_ERC20() public {
        bytes32[] memory accountProof = new bytes32[](0);
        accountVerifier.setShouldVerify(true);
        vaultVerifier.setShouldVerify(true);

        VaultWithProof memory testVaultWithProof = fixVaultEscapes[2];
        uint256 assetId = testVaultWithProof.vault.assetId;

        IERC20 token = IERC20(vaultWithdrawalProcessor.getAssetAddress(assetId));
        console.log("token address", address(token));

        uint256 expectedTransfer =
            vaultWithdrawalProcessor.getAssetQuantum(assetId) * testVaultWithProof.vault.quantizedAmount;

        deal(address(token), address(vaultWithdrawalProcessor), 1 ether);
        assertEq(token.balanceOf(recipient), 0);
        bool success =
            vaultWithdrawalProcessor.verifyProofAndDisburseFunds(recipient, accountProof, testVaultWithProof.proof);

        assertTrue(success);
        assertTrue(
            vaultWithdrawalProcessor.isClaimProcessed(
                testVaultWithProof.vault.starkKey, testVaultWithProof.vault.assetId
            )
        );
        assertEq(token.balanceOf(recipient), expectedTransfer);
    }

    function test_RevertIf_InvalidAccountProof() public {
        bytes32[] memory accountProof = new bytes32[](0);
        accountVerifier.setShouldVerify(false);
        vaultVerifier.setShouldVerify(true);

        vm.expectRevert(
            abi.encodeWithSelector(
                IVaultWithdrawalProcessor.InvalidAccountProof.selector, fixVaultEscapes[0].vault.starkKey, recipient
            )
        );
        vaultWithdrawalProcessor.verifyProofAndDisburseFunds(recipient, accountProof, fixVaultEscapes[0].proof);
    }

    function test_RevertIf_InvalidVaultProof() public {
        bytes32[] memory accountProof = new bytes32[](0);
        accountVerifier.setShouldVerify(true);
        vaultVerifier.setShouldVerify(false);

        vm.expectRevert(
            abi.encodeWithSelector(IVaultWithdrawalProcessor.InvalidVaultProof.selector, "Invalid vault proof")
        );
        vaultWithdrawalProcessor.verifyProofAndDisburseFunds(recipient, accountProof, fixVaultEscapes[0].proof);
    }

    function test_RevertIf_ClaimAlreadyProcessed() public {
        bytes32[] memory accountProof = new bytes32[](0);
        accountVerifier.setShouldVerify(true);
        vaultVerifier.setShouldVerify(true);

        vm.deal(address(vaultWithdrawalProcessor), 1 ether);

        vaultWithdrawalProcessor.verifyProofAndDisburseFunds(recipient, accountProof, fixVaultEscapes[0].proof);

        vm.expectRevert(
            abi.encodeWithSelector(
                IVaultWithdrawalProcessor.FundAlreadyDisbursedForVault.selector,
                fixVaultEscapes[0].vault.starkKey,
                fixVaultEscapes[0].vault.assetId
            )
        );
        vaultWithdrawalProcessor.verifyProofAndDisburseFunds(recipient, accountProof, fixVaultEscapes[0].proof);
    }

    function test_RevertIf_UnregisteredAsset() public {
        bytes32[] memory accountProof = new bytes32[](0);
        accountVerifier.setShouldVerify(true);
        vaultVerifier.setShouldVerify(true);

        uint256[] memory proofWithUnregisteredAsset = fixVaultEscapes[1].proof;

        vm.expectRevert(
            abi.encodeWithSelector(
                IVaultWithdrawalProcessor.AssetNotRegistered.selector, fixVaultEscapes[1].vault.assetId
            )
        );
        vaultWithdrawalProcessor.verifyProofAndDisburseFunds(recipient, accountProof, proofWithUnregisteredAsset);
    }

    function test_RevertIf_InsufficientBalance() public {
        bytes32[] memory accountProof = new bytes32[](0);
        accountVerifier.setShouldVerify(true);
        vaultVerifier.setShouldVerify(true);

        uint256 expectedAmount = vaultWithdrawalProcessor.getAssetQuantum(fixVaultEscapes[0].vault.assetId)
            * fixVaultEscapes[0].vault.quantizedAmount;

        vm.expectRevert(
            abi.encodeWithSelector(
                IVaultWithdrawalProcessor.InsufficientContractBalance.selector,
                vaultWithdrawalProcessor.NATIVE_IMX_ADDRESS(),
                expectedAmount,
                0
            )
        );
        vaultWithdrawalProcessor.verifyProofAndDisburseFunds(recipient, accountProof, fixVaultEscapes[0].proof);
    }
}
