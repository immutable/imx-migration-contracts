// Copyright Immutable Pty Ltd 2018 - 2025
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import "@src/assets/TokenRegistry.sol";
import "@src/verifiers/vaults/VaultEscapeProofVerifier.sol";
import "@src/withdrawals/IVaultWithdrawalProcessor.sol";
import "@src/withdrawals/VaultWithdrawalProcessor.sol";
import "../../common/FixtureVaultEscapes.sol";
import "../../common/FixtureAssets.sol";
import "../../common/FixtureLookupTables.sol";
import {Errors} from "@openzeppelin/contracts/utils/Errors.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {FixtureAccounts} from "../../common/FixtureAccounts.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

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

contract VaultWithdrawalProcessorTest is
    Test,
    FixtureVaultEscapes,
    FixtureAssets,
    FixtureAccounts,
    FixtureLookupTables
{
    VaultWithdrawalProcessor private vaultWithdrawalProcessor;
    MockVaultVerifier private vaultVerifier;
    ProcessorAccessControl.RoleOperators private initRoles = ProcessorAccessControl.RoleOperators({
        pauser: address(this),
        unpauser: address(this),
        disburser: address(this),
        defaultAdmin: address(this),
        vaultRootProvider: address(this),
        accountRootProvider: address(this),
        tokenMappingManager: address(this)
    });

    uint256[] private invalidProofBadKey;
    uint256[] private invalidProofBadPath;
    address private recipient = address(0xA123);
    AccountAssociation private sampleAccount;

    function setUp() public {
        string memory ZKEVM_RPC_URL = vm.envString("ZKEVM_RPC_URL");
        vm.createSelectFork(ZKEVM_RPC_URL);

        vaultVerifier = new MockVaultVerifier(ZKEVM_MAINNET_LOOKUP_TABLES);

        vaultWithdrawalProcessor = new VaultWithdrawalProcessor(address(vaultVerifier), initRoles, true);
        vaultWithdrawalProcessor.setVaultRoot(fixVaultEscapes[0].root);
        vaultWithdrawalProcessor.setAccountRoot(accountsRoot);
        vaultWithdrawalProcessor.registerTokenMappings(fixAssets);

        sampleAccount = fixAccounts[79411809110095984468032809253690107888721902246953260848891387903178601];
    }

    function test_Constructor() public view {
        assertEq(address(vaultWithdrawalProcessor.vaultProofVerifier()), address(vaultVerifier));
        assertEq(vaultWithdrawalProcessor.vaultRoot(), fixVaultEscapes[0].root);

        for (uint256 i = 0; i < fixAssets.length; i++) {
            uint256 id = fixAssets[i].tokenOnIMX.id;
            assertEq(vaultWithdrawalProcessor.getZKEVMToken(id), fixAssets[i].tokenOnZKEVM);
            assertEq(vaultWithdrawalProcessor.getTokenMapping(id).tokenOnIMX.quantum, fixAssets[i].tokenOnIMX.quantum);
        }
    }

    function test_Constants() public view {
        assertEq(vaultWithdrawalProcessor.VAULT_PROOF_LENGTH(), 68, "VAULT_PROOF_LENGTH should be 68");
        assertEq(vaultWithdrawalProcessor.rootOverrideAllowed(), true, "rootOverrideAllowed should be true initially");
    }

    function test_Constructor_RootOverrideAllowed() public {
        // Test with rootOverrideAllowed = false
        VaultWithdrawalProcessor processorWithOverrideDisabled =
            new VaultWithdrawalProcessor(address(vaultVerifier), initRoles, false);
        assertEq(
            processorWithOverrideDisabled.rootOverrideAllowed(),
            false,
            "rootOverrideAllowed should be false when set in constructor"
        );
    }

    function test_ProcessValidEscapeClaim_IMX() public {
        vaultVerifier.setShouldVerify(true);
        VaultWithProof memory v = fixVaultEscapes[2];
        address _recipient = fixAccounts[v.vault.starkKey].ethAddress;

        uint256 expectedTransfer = vaultWithdrawalProcessor.getTokenQuantum(v.vault.assetId) * v.vault.quantizedBalance;

        vm.deal(address(vaultWithdrawalProcessor), expectedTransfer);
        uint256 initialBalance = _recipient.balance;

        vm.expectEmit(true, true, true, true);
        emit IVaultWithdrawalProcessor.WithdrawalProcessed(
            v.vault.starkKey,
            _recipient,
            v.vault.assetId,
            vaultWithdrawalProcessor.NATIVE_IMX_ADDRESS(),
            expectedTransfer
        );

        vaultWithdrawalProcessor.verifyAndProcessWithdrawal(_recipient, fixAccounts[v.vault.starkKey].proof, v.proof);

        assertTrue(
            vaultWithdrawalProcessor.isWithdrawalProcessed(
                fixVaultEscapes[2].vault.starkKey, fixVaultEscapes[2].vault.assetId
            ),
            "Withdrawal should be marked as processed"
        );
        assertEq(_recipient.balance, expectedTransfer + initialBalance, "Recipient should receive the expected amount");
    }

    function test_ProcessValidEscapeClaim_ERC20() public {
        vaultVerifier.setShouldVerify(true);
        VaultWithProof memory testVaultWithProof = fixVaultEscapes[0];
        AccountAssociation memory _recipient = fixAccounts[testVaultWithProof.vault.starkKey];
        uint256 assetId = testVaultWithProof.vault.assetId;

        uint256 expectedTransfer =
            vaultWithdrawalProcessor.getTokenQuantum(assetId) * testVaultWithProof.vault.quantizedBalance;

        IERC20 token = IERC20(vaultWithdrawalProcessor.getZKEVMToken(assetId));
        deal(address(token), address(vaultWithdrawalProcessor), 3 ether);

        uint256 initialBalance = token.balanceOf(_recipient.ethAddress);

        vm.expectEmit(true, true, true, true);
        emit IVaultWithdrawalProcessor.WithdrawalProcessed(
            testVaultWithProof.vault.starkKey, _recipient.ethAddress, assetId, address(token), expectedTransfer
        );

        vaultWithdrawalProcessor.verifyAndProcessWithdrawal(
            _recipient.ethAddress, _recipient.proof, testVaultWithProof.proof
        );

        assertTrue(
            vaultWithdrawalProcessor.isWithdrawalProcessed(
                testVaultWithProof.vault.starkKey, testVaultWithProof.vault.assetId
            ),
            "Withdrawal should be marked as processed"
        );
        assertEq(
            token.balanceOf(_recipient.ethAddress),
            expectedTransfer + initialBalance,
            "Recipient should receive the expected amount"
        );
    }

    function test_RevertIf_UnauthorizedWithdrawal() public {
        bytes32[] memory accountProof = new bytes32[](2);
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
        vaultVerifier.setShouldVerify(true);

        vaultWithdrawalProcessor.pause();
        assertTrue(vaultWithdrawalProcessor.paused());

        vm.expectRevert(Pausable.EnforcedPause.selector);
        vaultWithdrawalProcessor.verifyAndProcessWithdrawal(recipient, accountProof, fixVaultEscapes[0].proof);
    }

    function test_RevertIf_ZeroAddress() public {
        bytes32[] memory accountProof = new bytes32[](2);
        vaultVerifier.setShouldVerify(true);

        vm.expectRevert(IVaultWithdrawalProcessor.ZeroAddress.selector);
        vaultWithdrawalProcessor.verifyAndProcessWithdrawal(address(0), accountProof, fixVaultEscapes[0].proof);
    }

    function test_RevertIf_EmptyAccountProof() public {
        bytes32[] memory emptyProof = new bytes32[](0);
        vaultVerifier.setShouldVerify(true);

        vm.expectRevert(
            abi.encodeWithSelector(AccountProofVerifier.InvalidAccountProof.selector, "Invalid account proof length")
        );
        vaultWithdrawalProcessor.verifyAndProcessWithdrawal(recipient, emptyProof, fixVaultEscapes[0].proof);
    }

    function test_RevertIf_EmptyVaultProof() public {
        uint256[] memory emptyProof = new uint256[](0);

        vm.expectRevert(
            abi.encodeWithSelector(IVaultProofVerifier.InvalidVaultProof.selector, "Invalid vault proof length")
        );
        vaultWithdrawalProcessor.verifyAndProcessWithdrawal(recipient, sampleAccount.proof, emptyProof);
    }

    function test_RevertIf_VaultProofWrongLength() public {
        // Create a proof with wrong length (not 68)
        uint256[] memory wrongLengthProof = new uint256[](67);
        for (uint256 i = 0; i < 67; i++) {
            wrongLengthProof[i] = i;
        }

        vm.expectRevert(
            abi.encodeWithSelector(IVaultProofVerifier.InvalidVaultProof.selector, "Invalid vault proof length")
        );
        vaultWithdrawalProcessor.verifyAndProcessWithdrawal(recipient, sampleAccount.proof, wrongLengthProof);
    }

    function test_RevertIf_InvalidAccountProof() public {
        vaultVerifier.setShouldVerify(true);

        vm.expectRevert(
            abi.encodeWithSelector(AccountProofVerifier.InvalidAccountProof.selector, "Invalid merkle proof")
        );
        vaultWithdrawalProcessor.verifyAndProcessWithdrawal(recipient, sampleAccount.proof, fixVaultEscapes[0].proof);
    }

    function test_RevertIf_InvalidVaultProof() public {
        VaultWithProof memory v = fixVaultEscapes[0];
        bytes32[] memory accountProof = fixAccounts[v.vault.starkKey].proof;
        address _recipient = fixAccounts[v.vault.starkKey].ethAddress;
        vaultVerifier.setShouldVerify(false);

        vm.expectRevert(abi.encodeWithSelector(IVaultProofVerifier.InvalidVaultProof.selector, "Invalid vault proof"));
        vaultWithdrawalProcessor.verifyAndProcessWithdrawal(_recipient, accountProof, fixVaultEscapes[0].proof);
    }

    function test_RevertIf_ClaimAlreadyProcessed() public {
        VaultWithProof memory v = fixVaultEscapes[2];
        bytes32[] memory accountProof = fixAccounts[v.vault.starkKey].proof;
        address _recipient = fixAccounts[v.vault.starkKey].ethAddress;
        vaultVerifier.setShouldVerify(true);

        uint256 vaultBalance = fixVaultEscapes[2].vault.quantizedBalance * fixAssets[0].tokenOnIMX.quantum;
        vm.deal(address(vaultWithdrawalProcessor), vaultBalance);

        vaultWithdrawalProcessor.verifyAndProcessWithdrawal(_recipient, accountProof, v.proof);

        vm.expectRevert(
            abi.encodeWithSelector(
                IVaultWithdrawalProcessor.WithdrawalAlreadyProcessed.selector, v.vault.starkKey, v.vault.assetId
            )
        );
        vaultWithdrawalProcessor.verifyAndProcessWithdrawal(_recipient, accountProof, fixVaultEscapes[2].proof);
    }

    function test_RevertIf_UnregisteredAsset() public {
        vaultVerifier.setShouldVerify(true);

        uint256[] memory proofWithUnregisteredAsset = fixVaultEscapes[1].proof;
        proofWithUnregisteredAsset[1] = proofWithUnregisteredAsset[1] << 1;

        vm.expectPartialRevert(TokenRegistry.AssetNotRegistered.selector);
        vaultWithdrawalProcessor.verifyAndProcessWithdrawal(recipient, sampleAccount.proof, proofWithUnregisteredAsset);
    }

    function test_RevertIf_InsufficientBalance() public {
        VaultWithProof memory v = fixVaultEscapes[2];
        bytes32[] memory accountProof = fixAccounts[v.vault.starkKey].proof;
        address _recipient = fixAccounts[v.vault.starkKey].ethAddress;
        vaultVerifier.setShouldVerify(true);

        uint256 expectedAmount = vaultWithdrawalProcessor.getTokenQuantum(fixVaultEscapes[2].vault.assetId)
            * fixVaultEscapes[2].vault.quantizedBalance;

        vm.expectRevert(abi.encodeWithSelector(Errors.InsufficientBalance.selector, 0, expectedAmount));
        vaultWithdrawalProcessor.verifyAndProcessWithdrawal(_recipient, accountProof, fixVaultEscapes[2].proof);
    }

    function test_RevertIf_Constructor_ZeroVaultVerifier() public {
        vm.expectRevert(IVaultWithdrawalProcessor.ZeroAddress.selector);
        new VaultWithdrawalProcessor(address(0), initRoles, true);
    }

    function test_RevertIf_Constructor_InvalidPauserOperator() public {
        ProcessorAccessControl.RoleOperators memory invalidRoles = ProcessorAccessControl.RoleOperators({
            pauser: address(0), // Invalid: zero address
            unpauser: address(this),
            disburser: address(this),
            defaultAdmin: address(this),
            vaultRootProvider: address(this),
            accountRootProvider: address(this),
            tokenMappingManager: address(this)
        });

        vm.expectRevert(ProcessorAccessControl.InvalidOperatorAddress.selector);
        new VaultWithdrawalProcessor(address(vaultVerifier), invalidRoles, true);
    }

    function test_RevertIf_Constructor_InvalidUnpauserOperator() public {
        ProcessorAccessControl.RoleOperators memory invalidRoles = ProcessorAccessControl.RoleOperators({
            pauser: address(this),
            unpauser: address(0), // Invalid: zero address
            disburser: address(this),
            defaultAdmin: address(this),
            vaultRootProvider: address(this),
            accountRootProvider: address(this),
            tokenMappingManager: address(this)
        });

        vm.expectRevert(ProcessorAccessControl.InvalidOperatorAddress.selector);
        new VaultWithdrawalProcessor(address(vaultVerifier), invalidRoles, true);
    }

    function test_RevertIf_Constructor_InvalidDisburserOperator() public {
        ProcessorAccessControl.RoleOperators memory invalidRoles = ProcessorAccessControl.RoleOperators({
            pauser: address(this),
            unpauser: address(this),
            disburser: address(0), // Invalid: zero address
            defaultAdmin: address(this),
            vaultRootProvider: address(this),
            accountRootProvider: address(this),
            tokenMappingManager: address(this)
        });

        vm.expectRevert(ProcessorAccessControl.InvalidOperatorAddress.selector);
        new VaultWithdrawalProcessor(address(vaultVerifier), invalidRoles, true);
    }

    function test_RevertIf_Constructor_InvalidDefaultAdminOperator() public {
        ProcessorAccessControl.RoleOperators memory invalidRoles = ProcessorAccessControl.RoleOperators({
            pauser: address(this),
            unpauser: address(this),
            disburser: address(this),
            defaultAdmin: address(0), // Invalid: zero address
            vaultRootProvider: address(this),
            accountRootProvider: address(this),
            tokenMappingManager: address(this)
        });

        vm.expectRevert(ProcessorAccessControl.InvalidOperatorAddress.selector);
        new VaultWithdrawalProcessor(address(vaultVerifier), invalidRoles, true);
    }

    function test_RevertIf_Constructor_InvalidVaultRootProviderOperator() public {
        ProcessorAccessControl.RoleOperators memory invalidRoles = ProcessorAccessControl.RoleOperators({
            pauser: address(this),
            unpauser: address(this),
            disburser: address(this),
            defaultAdmin: address(this),
            vaultRootProvider: address(0), // Invalid: zero address
            accountRootProvider: address(this),
            tokenMappingManager: address(this)
        });

        vm.expectRevert(ProcessorAccessControl.InvalidOperatorAddress.selector);
        new VaultWithdrawalProcessor(address(vaultVerifier), invalidRoles, true);
    }

    function test_RevertIf_Constructor_InvalidAccountRootProviderOperator() public {
        ProcessorAccessControl.RoleOperators memory invalidRoles = ProcessorAccessControl.RoleOperators({
            pauser: address(this),
            unpauser: address(this),
            disburser: address(this),
            defaultAdmin: address(this),
            vaultRootProvider: address(this),
            accountRootProvider: address(0), // Invalid: zero address
            tokenMappingManager: address(this)
        });

        vm.expectRevert(ProcessorAccessControl.InvalidOperatorAddress.selector);
        new VaultWithdrawalProcessor(address(vaultVerifier), invalidRoles, true);
    }

    function test_RevertIf_Constructor_InvalidTokenMappingManagerOperator() public {
        ProcessorAccessControl.RoleOperators memory invalidRoles = ProcessorAccessControl.RoleOperators({
            pauser: address(this),
            unpauser: address(this),
            disburser: address(this),
            defaultAdmin: address(this),
            vaultRootProvider: address(this),
            accountRootProvider: address(this),
            tokenMappingManager: address(0) // Invalid: zero address
        });

        vm.expectRevert(ProcessorAccessControl.InvalidOperatorAddress.selector);
        new VaultWithdrawalProcessor(address(vaultVerifier), invalidRoles, true);
    }

    function test_SetVaultRoot() public view {
        assertEq(vaultWithdrawalProcessor.vaultRoot(), fixVaultEscapes[0].root);
    }

    function test_RevertIf_SetVaultRoot_Unauthorized() public {
        uint256 newRoot = 0x123;
        vm.startPrank(address(0x123));
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                address(0x123),
                vaultWithdrawalProcessor.VAULT_ROOT_PROVIDER_ROLE()
            )
        );
        vaultWithdrawalProcessor.setVaultRoot(newRoot);
    }

    function test_RevertIf_SetVaultRoot_AlreadySet_OverrideDisabled() public {
        vaultWithdrawalProcessor.setRootOverrideAllowed(false);
        uint256 newRoot = 0x123;
        vm.expectRevert(abi.encodeWithSelector(VaultRootReceiver.VaultRootOverrideNotAllowed.selector));
        vaultWithdrawalProcessor.setVaultRoot(newRoot);
    }

    function test_SetAccountRoot() public {
        bytes32 newAccountRoot = keccak256("new-account-root");
        vaultWithdrawalProcessor.setAccountRoot(newAccountRoot);
        assertEq(vaultWithdrawalProcessor.accountRoot(), newAccountRoot);
    }

    function test_RevertIf_SetAccountRoot_Unauthorized() public {
        bytes32 newAccountRoot = keccak256("new-account-root");
        vm.startPrank(address(0x123));
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                address(0x123),
                vaultWithdrawalProcessor.ACCOUNT_ROOT_PROVIDER_ROLE()
            )
        );
        vaultWithdrawalProcessor.setAccountRoot(newAccountRoot);
    }

    function test_SetRootOverrideAllowed() public {
        vaultWithdrawalProcessor.setRootOverrideAllowed(false);
        assertEq(vaultWithdrawalProcessor.rootOverrideAllowed(), false, "rootOverrideAllowed should be set to false");

        vaultWithdrawalProcessor.setRootOverrideAllowed(true);
        assertEq(vaultWithdrawalProcessor.rootOverrideAllowed(), true, "rootOverrideAllowed should be set to true");
    }

    function test_RevertIf_SetRootOverrideAllowed_Unauthorized() public {
        vm.startPrank(address(0x123));
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                address(0x123),
                vaultWithdrawalProcessor.DEFAULT_ADMIN_ROLE()
            )
        );
        vaultWithdrawalProcessor.setRootOverrideAllowed(false);
    }

    function test_RegisterTokenMappings() public {
        TokenRegistry.TokenAssociation[] memory newAssets = new TokenRegistry.TokenAssociation[](1);
        newAssets[0] = TokenRegistry.TokenAssociation(TokenRegistry.ImmutableXToken(999, 18), address(0x999));

        vaultWithdrawalProcessor.registerTokenMappings(newAssets);
        assertEq(vaultWithdrawalProcessor.getZKEVMToken(999), address(0x999), "New asset should be registered");
    }

    function test_RevertIf_RegisterTokenMappings_Unauthorized() public {
        TokenRegistry.TokenAssociation[] memory newAssets = new TokenRegistry.TokenAssociation[](1);
        newAssets[0] = TokenRegistry.TokenAssociation(TokenRegistry.ImmutableXToken(999, 18), address(0x999));

        vm.startPrank(address(0x123));
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                address(0x123),
                vaultWithdrawalProcessor.TOKEN_MAPPING_MANAGER()
            )
        );
        vaultWithdrawalProcessor.registerTokenMappings(newAssets);
    }

    function test_RevertIf_VaultRootNotSet() public {
        // Create a new processor without setting vault root
        VaultWithdrawalProcessor newProcessor = new VaultWithdrawalProcessor(address(vaultVerifier), initRoles, true);
        newProcessor.setAccountRoot(accountsRoot);
        newProcessor.registerTokenMappings(fixAssets);

        bytes32[] memory accountProof = new bytes32[](2);
        vaultVerifier.setShouldVerify(true);

        vm.expectRevert(IVaultWithdrawalProcessor.VaultRootNotSet.selector);
        newProcessor.verifyAndProcessWithdrawal(recipient, accountProof, fixVaultEscapes[0].proof);
    }

    function test_RevertIf_AccountRootNotSet() public {
        // Create a new processor without setting account root
        VaultWithdrawalProcessor newProcessor = new VaultWithdrawalProcessor(address(vaultVerifier), initRoles, true);
        newProcessor.setVaultRoot(fixVaultEscapes[0].root);
        newProcessor.registerTokenMappings(fixAssets);

        bytes32[] memory accountProof = new bytes32[](2);
        vaultVerifier.setShouldVerify(true);

        vm.expectRevert(AccountRootReceiver.AccountRootNotSet.selector);
        newProcessor.verifyAndProcessWithdrawal(recipient, accountProof, fixVaultEscapes[0].proof);
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
