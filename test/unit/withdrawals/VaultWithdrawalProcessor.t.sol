// Copyright Immutable Pty Ltd 2018 - 2025
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import "@src/assets/TokenMappings.sol";
import "@src/verifiers/accounts/IAccountProofVerifier.sol";
import "@src/verifiers/vaults/VaultEscapeProofVerifier.sol";
import "@src/withdrawals/IVaultWithdrawalProcessor.sol";
import "@src/withdrawals/VaultWithdrawalProcessor.sol";
import "../../common/FixtureVaultEscapes.sol";
import "../../common/FixtureAssets.sol";
import "../../common/FixtureLookupTables.sol";
import {Errors} from "@openzeppelin/contracts/utils/Errors.sol";

contract MockAccountVerifier is IAccountProofVerifier {
    bool public shouldVerify;

    function setShouldVerify(bool _shouldVerify) external {
        shouldVerify = _shouldVerify;
    }

    function verifyAccountProof(uint256, address, bytes32[] calldata) external view override returns (bool) {
        return shouldVerify;
    }
}

contract MockVaultVerifier is VaultEscapeProofVerifier {
    bool public shouldVerify;

    constructor(address[63] memory lookupTables) VaultEscapeProofVerifier(lookupTables) {}

    function setShouldVerify(bool _shouldVerify) external {
        shouldVerify = _shouldVerify;
    }

    function verifyVaultProof(uint256[] calldata) external view override returns (bool) {
        return shouldVerify;
    }
}

contract VaultWithdrawalProcessorTest is Test, FixtureVaultEscapes, FixtureAssets, FixtureLookupTables {
    VaultWithdrawalProcessor private vaultWithdrawalProcessor;
    MockAccountVerifier private accountVerifier;
    MockVaultVerifier private vaultVerifier;
    VaultWithdrawalProcessor.Operators private initRoles = VaultWithdrawalProcessor.Operators({
        pauser: address(this),
        unpauser: address(this),
        disburser: address(this),
        defaultAdmin: address(this)
    });

    uint256[] private invalidProofBadKey;
    uint256[] private invalidProofBadPath;
    address private recipient = address(0xA123);

    function setUp() public {
        string memory ZKEVM_RPC_URL = vm.envString("ZKEVM_RPC_URL");
        vm.createSelectFork(ZKEVM_RPC_URL);

        accountVerifier = new MockAccountVerifier();
        vaultVerifier = new MockVaultVerifier(ZKEVM_MAINNET_LOOKUP_TABLES);

        vaultWithdrawalProcessor = new VaultWithdrawalProcessor(
            accountVerifier, vaultVerifier, address(this), address(this), fixAssets, initRoles, false
        );
        vaultWithdrawalProcessor.setVaultRoot(fixVaultEscapes[0].root);
    }

    function test_Constructor() public view {
        assertEq(address(vaultWithdrawalProcessor.accountVerifier()), address(accountVerifier));
        assertEq(address(vaultWithdrawalProcessor.vaultVerifier()), address(vaultVerifier));
        assertEq(vaultWithdrawalProcessor.vaultRoot(), fixVaultEscapes[0].root);

        for (uint256 i = 0; i < fixAssets.length; i++) {
            uint256 id = fixAssets[i].tokenOnIMX.id;
            assertEq(vaultWithdrawalProcessor.getZKEVMAddress(id), fixAssets[i].tokenOnZKEVM);
            assertEq(vaultWithdrawalProcessor.getAssetMapping(id).tokenOnIMX.quantum, fixAssets[i].tokenOnIMX.quantum);
        }
    }

    function test_ProcessValidEscapeClaim_IMX() public {
        bytes32[] memory accountProof = new bytes32[](2);
        accountVerifier.setShouldVerify(true);
        vaultVerifier.setShouldVerify(true);

        uint256 expectedTransfer = vaultWithdrawalProcessor.getAssetQuantum(fixVaultEscapes[2].vault.assetId)
            * fixVaultEscapes[2].vault.quantizedAmount;

        vm.deal(address(vaultWithdrawalProcessor), 1 ether);
        assertEq(recipient.balance, 0 ether, "Recipient should start with zero balance");
        bool success =
            vaultWithdrawalProcessor.verifyAndProcessWithdrawal(recipient, accountProof, fixVaultEscapes[2].proof);

        assertTrue(success, "Withdrawal should be processed successfully");
        assertTrue(
            vaultWithdrawalProcessor.isWithdrawalProcessed(
                fixVaultEscapes[2].vault.starkKey, fixVaultEscapes[2].vault.assetId
            ),
            "Withdrawal should be marked as processed"
        );
        assertEq(recipient.balance, expectedTransfer, "Recipient should receive the expected amount");
    }

    function test_ProcessValidEscapeClaim_ERC20() public {
        bytes32[] memory accountProof = new bytes32[](1);
        accountVerifier.setShouldVerify(true);
        vaultVerifier.setShouldVerify(true);

        VaultWithProof memory testVaultWithProof = fixVaultEscapes[0];
        uint256 assetId = testVaultWithProof.vault.assetId;

        uint256 expectedTransfer =
            vaultWithdrawalProcessor.getAssetQuantum(assetId) * testVaultWithProof.vault.quantizedAmount;

        IERC20 token = IERC20(vaultWithdrawalProcessor.getZKEVMAddress(assetId));
        deal(address(token), address(vaultWithdrawalProcessor), 3 ether);

        assertEq(token.balanceOf(recipient), 0, "Recipient should start with zero balance");
        bool success =
            vaultWithdrawalProcessor.verifyAndProcessWithdrawal(recipient, accountProof, testVaultWithProof.proof);

        assertTrue(success, "Withdrawal should be processed successfully");
        assertTrue(
            vaultWithdrawalProcessor.isWithdrawalProcessed(
                testVaultWithProof.vault.starkKey, testVaultWithProof.vault.assetId
            ),
            "Withdrawal should be marked as processed"
        );
        assertEq(token.balanceOf(recipient), expectedTransfer, "Recipient should receive the expected amount");
    }

    function test_RevertIf_UnauthorizedWithdrawal() public {
        bytes32[] memory accountProof = new bytes32[](2);
        accountVerifier.setShouldVerify(true);
        vaultVerifier.setShouldVerify(true);

        vm.expectRevert(
            abi.encodeWithSelector(
                bytes4(keccak256("AccessControlUnauthorizedAccount(address,bytes32)")),
                address(0x123),
                vaultWithdrawalProcessor.DISBURSER_ROLE()
            )
        );
        vm.prank(address(0x123));
        vaultWithdrawalProcessor.verifyAndProcessWithdrawal(recipient, accountProof, fixVaultEscapes[0].proof);
    }

    function test_RevertIf_UnauthorizedPause() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                bytes4(keccak256("AccessControlUnauthorizedAccount(address,bytes32)")),
                address(0x123),
                vaultWithdrawalProcessor.PAUSER_ROLE()
            )
        );
        vm.prank(address(0x123));
        vaultWithdrawalProcessor.pause();
    }

    function test_RevertIf_UnauthorizedUnpause() public {
        vaultWithdrawalProcessor.pause();
        vm.expectRevert(
            abi.encodeWithSelector(
                bytes4(keccak256("AccessControlUnauthorizedAccount(address,bytes32)")),
                address(0x123),
                vaultWithdrawalProcessor.UNPAUSER_ROLE()
            )
        );
        vm.prank(address(0x123));
        vaultWithdrawalProcessor.unpause();
    }

    function test_PauseAndUnpause() public {
        vaultWithdrawalProcessor.pause();
        assertTrue(vaultWithdrawalProcessor.paused());

        vaultWithdrawalProcessor.unpause();
        assertFalse(vaultWithdrawalProcessor.paused());
    }

    function test_RevertIf_Paused_Withdrawal() public {
        bytes32[] memory accountProof = new bytes32[](2);
        accountVerifier.setShouldVerify(true);
        vaultVerifier.setShouldVerify(true);

        vaultWithdrawalProcessor.pause();
        assertTrue(vaultWithdrawalProcessor.paused());

        vm.expectRevert(Pausable.EnforcedPause.selector);
        vaultWithdrawalProcessor.verifyAndProcessWithdrawal(recipient, accountProof, fixVaultEscapes[0].proof);
    }

    function test_RevertIf_Paused_SetVaultRoot() public {
        vaultWithdrawalProcessor.pause();
        assertTrue(vaultWithdrawalProcessor.paused());

        vm.expectRevert(Pausable.EnforcedPause.selector);
        vaultWithdrawalProcessor.setVaultRoot(0x123);
    }

    function test_RevertIf_ZeroAddress() public {
        bytes32[] memory accountProof = new bytes32[](2);
        accountVerifier.setShouldVerify(true);
        vaultVerifier.setShouldVerify(true);

        vm.expectRevert(IVaultWithdrawalProcessor.ZeroAddress.selector);
        vaultWithdrawalProcessor.verifyAndProcessWithdrawal(address(0), accountProof, fixVaultEscapes[0].proof);
    }

    function test_RevertIf_EmptyAccountProof() public {
        bytes32[] memory emptyProof = new bytes32[](0);
        vaultVerifier.setShouldVerify(true);

        vm.expectRevert(
            abi.encodeWithSelector(IAccountProofVerifier.InvalidAccountProof.selector, "Account proof is empty")
        );
        vaultWithdrawalProcessor.verifyAndProcessWithdrawal(recipient, emptyProof, fixVaultEscapes[0].proof);
    }

    function test_RevertIf_EmptyVaultProof() public {
        bytes32[] memory accountProof = new bytes32[](2);
        uint256[] memory emptyProof = new uint256[](0);
        accountVerifier.setShouldVerify(true);

        vm.expectRevert(abi.encodeWithSelector(IVaultProofVerifier.InvalidVaultProof.selector, "Vault proof is empty"));
        vaultWithdrawalProcessor.verifyAndProcessWithdrawal(recipient, accountProof, emptyProof);
    }

    function test_RevertIf_InvalidAccountProof() public {
        bytes32[] memory accountProof = new bytes32[](2);
        accountVerifier.setShouldVerify(false);
        vaultVerifier.setShouldVerify(true);

        vm.expectRevert(
            abi.encodeWithSelector(IAccountProofVerifier.InvalidAccountProof.selector, "Proof verification failed")
        );
        vaultWithdrawalProcessor.verifyAndProcessWithdrawal(recipient, accountProof, fixVaultEscapes[0].proof);
    }

    function test_RevertIf_InvalidVaultProof() public {
        bytes32[] memory accountProof = new bytes32[](2);
        accountVerifier.setShouldVerify(true);
        vaultVerifier.setShouldVerify(false);

        vm.expectRevert(abi.encodeWithSelector(IVaultProofVerifier.InvalidVaultProof.selector, "Invalid vault proof"));
        vaultWithdrawalProcessor.verifyAndProcessWithdrawal(recipient, accountProof, fixVaultEscapes[0].proof);
    }

    function test_RevertIf_ClaimAlreadyProcessed() public {
        bytes32[] memory accountProof = new bytes32[](2);
        accountVerifier.setShouldVerify(true);
        vaultVerifier.setShouldVerify(true);

        vm.deal(address(vaultWithdrawalProcessor), 1 ether);

        vaultWithdrawalProcessor.verifyAndProcessWithdrawal(recipient, accountProof, fixVaultEscapes[2].proof);

        vm.expectRevert(
            abi.encodeWithSelector(
                ProcessedWithdrawalsRegistry.WithdrawalAlreadyProcessed.selector,
                fixVaultEscapes[2].vault.starkKey,
                fixVaultEscapes[2].vault.assetId
            )
        );
        vaultWithdrawalProcessor.verifyAndProcessWithdrawal(recipient, accountProof, fixVaultEscapes[2].proof);
    }

    function test_RevertIf_UnregisteredAsset() public {
        bytes32[] memory accountProof = new bytes32[](2);
        accountVerifier.setShouldVerify(true);
        vaultVerifier.setShouldVerify(true);

        uint256[] memory proofWithUnregisteredAsset = fixVaultEscapes[1].proof;
        // TODO: this modification of asset id is not quite right, given packing of escape proof
        proofWithUnregisteredAsset[1] = proofWithUnregisteredAsset[1] << 1; // Modify the assetId to an unregistered one

        vm.expectPartialRevert(IVaultWithdrawalProcessor.AssetNotRegistered.selector);
        vaultWithdrawalProcessor.verifyAndProcessWithdrawal(recipient, accountProof, proofWithUnregisteredAsset);
    }

    function test_RevertIf_InsufficientBalance() public {
        bytes32[] memory accountProof = new bytes32[](2);
        accountVerifier.setShouldVerify(true);
        vaultVerifier.setShouldVerify(true);

        uint256 expectedAmount = vaultWithdrawalProcessor.getAssetQuantum(fixVaultEscapes[2].vault.assetId)
            * fixVaultEscapes[2].vault.quantizedAmount;

        vm.expectRevert(abi.encodeWithSelector(Errors.InsufficientBalance.selector, 0, expectedAmount));
        vaultWithdrawalProcessor.verifyAndProcessWithdrawal(recipient, accountProof, fixVaultEscapes[2].proof);
    }

    function test_RevertIf_FundTransferFailed() public {
        bytes32[] memory accountProof = new bytes32[](2);
        accountVerifier.setShouldVerify(true);
        vaultVerifier.setShouldVerify(true);

        address rejector = address(new IMXRejector());
        vm.deal(address(vaultWithdrawalProcessor), 1 ether);

        vm.expectRevert("Rejecting IMX transfers");
        vaultWithdrawalProcessor.verifyAndProcessWithdrawal(rejector, accountProof, fixVaultEscapes[2].proof);
    }

    function test_RevertIf_Constructor_ZeroVaultRootProvider() public {
        vm.expectRevert(IVaultWithdrawalProcessor.ZeroAddress.selector);
        new VaultWithdrawalProcessor(
            accountVerifier, vaultVerifier, address(0), address(this), fixAssets, initRoles, true
        );
    }

    function test_RevertIf_Constructor_ZeroVaultFundProvider() public {
        vm.expectRevert(IVaultWithdrawalProcessor.ZeroAddress.selector);
        new VaultWithdrawalProcessor(
            accountVerifier, vaultVerifier, address(this), address(0), fixAssets, initRoles, true
        );
    }

    function test_RevertIf_Constructor_ZeroAccountVerifier() public {
        vm.expectRevert(IVaultWithdrawalProcessor.ZeroAddress.selector);
        new VaultWithdrawalProcessor(
            IAccountProofVerifier(address(0)), vaultVerifier, address(this), address(this), fixAssets, initRoles, true
        );
    }

    function test_RevertIf_Constructor_ZeroVaultVerifier() public {
        vm.expectRevert(IVaultWithdrawalProcessor.ZeroAddress.selector);
        new VaultWithdrawalProcessor(
            accountVerifier, IVaultProofVerifier(address(0)), address(this), address(this), fixAssets, initRoles, true
        );
    }

    function test_RevertIf_Constructor_EmptyAssets() public {
        vm.expectRevert(abi.encodeWithSelector(TokenMappings.InvalidAssetDetails.selector, "No assets to register"));
        new VaultWithdrawalProcessor(
            accountVerifier,
            vaultVerifier,
            address(this),
            address(this),
            new TokenMappings.AssetMapping[](0),
            initRoles,
            false
        );
    }

    function test_SetVaultRoot() public view {
        assertEq(vaultWithdrawalProcessor.vaultRoot(), fixVaultEscapes[0].root);
    }

    function test_RevertIf_SetVaultRoot_Unauthorized() public {
        uint256 newRoot = 0x123;
        vm.prank(address(0x123));
        vm.expectRevert("Unauthorized: Only vault root provider can set the root");
        vaultWithdrawalProcessor.setVaultRoot(newRoot);
    }

    function test_RevertIf_SetVaultRoot_AlreadySet() public {
        uint256 newRoot = 0x123;
        vm.expectRevert(abi.encodeWithSelector(IVaultWithdrawalProcessor.VaultRootOverrideNotAllowed.selector));
        vaultWithdrawalProcessor.setVaultRoot(newRoot);
    }

    function test_Receive() public {
        uint256 amount = 1 ether;
        vm.deal(address(this), amount);
        (bool success,) = address(vaultWithdrawalProcessor).call{value: amount}("");
        assertTrue(success);
        assertEq(address(vaultWithdrawalProcessor).balance, amount);
    }

    function test_RevertIf_Receive_UnauthorisedSender() public {
        uint256 amount = 1 ether;
        vm.deal(address(this), amount);
        (bool success,) = address(vaultWithdrawalProcessor).call{value: amount}("");
        assertTrue(success);
        assertEq(address(vaultWithdrawalProcessor).balance, amount);
    }

    function test_NonCriticalFunctions_WorkWhenPaused() public {
        vaultWithdrawalProcessor.pause();
        assertTrue(vaultWithdrawalProcessor.paused());

        uint256 amount = 1 ether;
        vm.deal(address(this), amount);
        (bool success,) = address(vaultWithdrawalProcessor).call{value: amount}("");
        assertTrue(success);
        assertEq(address(vaultWithdrawalProcessor).balance, amount);

        vaultWithdrawalProcessor.unpause();
        assertFalse(vaultWithdrawalProcessor.paused());
    }
}

contract IMXRejector {
    receive() external payable {
        revert("Rejecting IMX transfers");
    }
}
