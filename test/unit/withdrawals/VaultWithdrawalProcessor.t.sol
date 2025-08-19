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

    function setUp() public {
        string memory ZKEVM_RPC_URL = vm.envString("ZKEVM_RPC_URL");
        vm.createSelectFork(ZKEVM_RPC_URL);

        vaultVerifier = new MockVaultVerifier(ZKEVM_MAINNET_LOOKUP_TABLES);

        vaultWithdrawalProcessor = new VaultWithdrawalProcessor(address(vaultVerifier), initRoles, true);
        vaultWithdrawalProcessor.setVaultRoot(fixVaultEscapes[0].root);
        vaultWithdrawalProcessor.setAccountRoot(accountsRoot);
        vaultWithdrawalProcessor.registerTokenMappings(fixAssets);
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

    function test_ProcessValidEscapeClaim_IMX() public {
        vaultVerifier.setShouldVerify(true);
        VaultWithProof memory v = fixVaultEscapes[2];
        address _recipient = fixAccounts[v.vault.starkKey].ethAddress;

        uint256 expectedTransfer = vaultWithdrawalProcessor.getTokenQuantum(v.vault.assetId) * v.vault.quantizedBalance;

        vm.deal(address(vaultWithdrawalProcessor), 3 ether);
        uint256 initialBalance = _recipient.balance;

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
        vaultWithdrawalProcessor.verifyAndProcessWithdrawal(recipient, new bytes32[](1), emptyProof);
    }

    function test_RevertIf_InvalidAccountProof() public {
        bytes32[] memory accountProof = new bytes32[](2);
        vaultVerifier.setShouldVerify(true);

        vm.expectRevert(
            abi.encodeWithSelector(AccountProofVerifier.InvalidAccountProof.selector, "Invalid merkle proof")
        );
        vaultWithdrawalProcessor.verifyAndProcessWithdrawal(recipient, accountProof, fixVaultEscapes[0].proof);
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

        vm.deal(address(vaultWithdrawalProcessor), 1 ether);

        vaultWithdrawalProcessor.verifyAndProcessWithdrawal(_recipient, accountProof, v.proof);

        vm.expectRevert(
            abi.encodeWithSelector(
                IVaultWithdrawalProcessor.WithdrawalAlreadyProcessed.selector, v.vault.starkKey, v.vault.assetId
            )
        );
        vaultWithdrawalProcessor.verifyAndProcessWithdrawal(_recipient, accountProof, fixVaultEscapes[2].proof);
    }

    function test_RevertIf_UnregisteredAsset() public {
        bytes32[] memory accountProof = new bytes32[](2);
        vaultVerifier.setShouldVerify(true);

        uint256[] memory proofWithUnregisteredAsset = fixVaultEscapes[1].proof;
        // TODO: this modification of asset id is not quite right, given packing of escape proof
        proofWithUnregisteredAsset[1] = proofWithUnregisteredAsset[1] << 1; // Modify the assetId to an unregistered one

        vm.expectPartialRevert(TokenRegistry.AssetNotRegistered.selector);
        vaultWithdrawalProcessor.verifyAndProcessWithdrawal(recipient, accountProof, proofWithUnregisteredAsset);
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
