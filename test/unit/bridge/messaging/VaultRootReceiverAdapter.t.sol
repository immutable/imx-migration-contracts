// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import "@src/bridge/messaging/VaultRootReceiverAdapter.sol";
import "../../../../src/withdrawals/VaultRootReceiver.sol";
import "../../../common/MockAxelarGateway.sol";
import {IAxelarExecutable} from "@axelar-gmp-sdk-solidity/interfaces/IAxelarExecutable.sol";

contract MockVaultRootReceiver is VaultRootReceiver {
    function setVaultRoot(uint256 _vaultRoot) external override {
        _setVaultRoot(_vaultRoot, true);
    }
}

contract VaultRootReceiverTest is Test {
    VaultRootReceiverAdapter private adapter;
    VaultRootReceiver private vaultRootReceiver;
    MockAxelarGateway private axelarGateway;
    address private owner;
    string private rootProviderChain;
    string private rootProviderContract;

    function setUp() public {
        owner = address(this);
        axelarGateway = new MockAxelarGateway(true);
        rootProviderChain = "ethereum";
        rootProviderContract = "0x456";

        vaultRootReceiver = new MockVaultRootReceiver();
        adapter = new VaultRootReceiverAdapter(owner, address(axelarGateway));
    }

    function test_Constructor() public view {
        assertEq(adapter.owner(), owner);
        assertEq(address(adapter.gateway()), address(axelarGateway));

        assertEq(address(adapter.rootReceiver()), address(0), "rootReceiver should be zero initially");
        assertEq(adapter.rootSenderChain(), "", "rootSenderChain should be empty initially");
        assertEq(adapter.rootSenderAddress(), "", "rootSenderAddress should be empty initially");
    }

    function test_SetVaultRootReceiver() public {
        vm.expectEmit(true, true, true, true);
        emit VaultRootReceiverAdapter.VaultRootReceiverSet(address(vaultRootReceiver));

        adapter.setVaultRootReceiver(vaultRootReceiver);
        assertEq(address(adapter.rootReceiver()), address(vaultRootReceiver));
    }

    function test_RevertIf_SetVaultRootReceiver_ZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(IAxelarExecutable.InvalidAddress.selector));
        adapter.setVaultRootReceiver(VaultRootReceiver(address(0)));
    }

    function test_RevertIf_SetVaultRootReceiver_Unauthorized() public {
        address notOwner = address(0x789);
        vm.prank(notOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, notOwner));
        adapter.setVaultRootReceiver(vaultRootReceiver);
    }

    function test_SetVaultRootSource() public {
        vm.expectEmit(true, true, true, true);
        emit VaultRootReceiverAdapter.VaultRootSourceSet("", "", rootProviderContract, rootProviderChain);

        adapter.setVaultRootSource(rootProviderChain, rootProviderContract);
        assertEq(adapter.rootSenderChain(), rootProviderChain);
        assertEq(adapter.rootSenderAddress(), rootProviderContract);
    }

    function test_SetVaultRootSource_UpdateExisting() public {
        string memory oldProviderChain = "old-chain";
        string memory oldProviderContract = "0xabc";
        adapter.setVaultRootSource(oldProviderChain, oldProviderContract);

        vm.expectEmit(true, true, true, true);
        emit VaultRootReceiverAdapter.VaultRootSourceSet(
            oldProviderContract, oldProviderChain, rootProviderContract, rootProviderChain
        );
        adapter.setVaultRootSource(rootProviderChain, rootProviderContract);

        assertEq(adapter.rootSenderChain(), rootProviderChain);
        assertEq(adapter.rootSenderAddress(), rootProviderContract);
    }

    function test_RevertIf_SetVaultRootSource_InvalidChain() public {
        vm.expectRevert(VaultRootReceiverAdapter.InvalidChainId.selector);
        adapter.setVaultRootSource("", rootProviderContract);
    }

    function test_RevertIf_SetVaultRootSource_InvalidAddress() public {
        vm.expectRevert(IAxelarExecutable.InvalidAddress.selector);
        adapter.setVaultRootSource(rootProviderChain, "");
    }

    function test_RevertIf_SetVaultRootSource_Unauthorized() public {
        address notOwner = address(0x789);
        vm.prank(notOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, notOwner));
        adapter.setVaultRootSource(rootProviderChain, rootProviderContract);
    }

    function test_Execute_ValidMessage() public {
        adapter.setVaultRootSource(rootProviderChain, rootProviderContract);
        adapter.setVaultRootReceiver(vaultRootReceiver);
        uint256 newRoot = 0x123;

        bytes memory payload = abi.encode(adapter.SET_VAULT_ROOT(), newRoot);
        bytes32 commandId = keccak256("test-command");
        adapter.execute(commandId, rootProviderChain, rootProviderContract, payload);

        assertEq(vaultRootReceiver.vaultRoot(), newRoot);
    }

    function test_RevertIf_Execute_UnauthorizedSenderChain() public {
        adapter.setVaultRootSource(rootProviderChain, rootProviderContract);
        adapter.setVaultRootReceiver(vaultRootReceiver);
        uint256 newRoot = 0x123;

        bytes memory payload = abi.encode(adapter.SET_VAULT_ROOT(), newRoot);
        bytes32 commandId = keccak256("test-command");
        vm.expectRevert(
            abi.encodeWithSelector(VaultRootReceiverAdapter.UnauthorizedMessageSender.selector, "unexpected chain")
        );
        adapter.execute(commandId, "polygon", rootProviderContract, payload);
    }

    function test_RevertIf_Execute_UnauthorizedSenderAddress() public {
        adapter.setVaultRootSource(rootProviderChain, rootProviderContract);
        adapter.setVaultRootReceiver(vaultRootReceiver);
        uint256 newRoot = 0x123;

        bytes memory payload = abi.encode(adapter.SET_VAULT_ROOT(), newRoot);
        bytes32 commandId = keccak256("test-command");
        vm.expectRevert(
            abi.encodeWithSelector(
                VaultRootReceiverAdapter.UnauthorizedMessageSender.selector, "unexpected contract address"
            )
        );
        adapter.execute(commandId, rootProviderChain, "0x789", payload);
    }

    function test_RevertIf_Execute_VaultRootReceiverNotSet() public {
        adapter.setVaultRootSource(rootProviderChain, rootProviderContract);
        uint256 newRoot = 0x123;
        bytes memory payload = abi.encode(adapter.SET_VAULT_ROOT(), newRoot);
        bytes32 commandId = keccak256("test-command");

        vm.expectRevert(VaultRootReceiverAdapter.VaultRootReceiverNotSet.selector);
        adapter.execute(commandId, rootProviderChain, rootProviderContract, payload);
    }

    function test_RevertIf_Execute_VaultRootSourceNotSet() public {
        adapter.setVaultRootReceiver(vaultRootReceiver);
        uint256 newRoot = 0x123;
        bytes memory payload = abi.encode(adapter.SET_VAULT_ROOT(), newRoot);
        bytes32 commandId = keccak256("test-command");

        vm.expectRevert(VaultRootReceiverAdapter.VaultRootSourceNotSet.selector);
        adapter.execute(commandId, rootProviderChain, rootProviderContract, payload);
    }

    function test_RevertIf_Execute_InvalidPayloadTooShort() public {
        adapter.setVaultRootSource(rootProviderChain, rootProviderContract);
        adapter.setVaultRootReceiver(vaultRootReceiver);

        // Create payload that's shorter than expected 64 bytes
        bytes memory shortPayload = new bytes(32);
        bytes32 commandId = keccak256("test-command");

        vm.expectRevert(abi.encodeWithSelector(VaultRootReceiverAdapter.InvalidMessageLength.selector, 32));
        adapter.execute(commandId, rootProviderChain, rootProviderContract, shortPayload);
    }

    function test_RevertIf_Execute_InvalidMessageCommand() public {
        adapter.setVaultRootSource(rootProviderChain, rootProviderContract);
        adapter.setVaultRootReceiver(vaultRootReceiver);
        uint256 newRoot = 0x123;

        bytes32 wrongCmd = keccak256("WRONG_COMMAND");
        bytes memory payload = abi.encode(wrongCmd, newRoot);
        bytes32 commandId = keccak256("test-command");

        vm.expectRevert(abi.encodeWithSelector(VaultRootReceiverAdapter.InvalidMessageSignature.selector, wrongCmd));
        adapter.execute(commandId, rootProviderChain, rootProviderContract, payload);
    }

    function test_RevertIf_Execute_AdapterStatePartiallySet() public {
        // Test when only receiver is set but source chain/address are not set
        adapter.setVaultRootReceiver(vaultRootReceiver);
        uint256 newRoot = 0x123;
        bytes memory payload = abi.encode(adapter.SET_VAULT_ROOT(), newRoot);
        bytes32 commandId = keccak256("test-command");

        // Should revert with VaultRootSourceNotSet since chain and address are empty strings
        vm.expectRevert(VaultRootReceiverAdapter.VaultRootSourceNotSet.selector);
        adapter.execute(commandId, "", "", payload);
    }

    function test_RevertIf_Execute_NotApprovedByGateway() public {
        adapter.setVaultRootReceiver(vaultRootReceiver);
        uint256 newRoot = 0x123;

        axelarGateway.setShouldValidate(false);
        bytes memory payload = abi.encode(adapter.SET_VAULT_ROOT(), newRoot);
        bytes32 commandId = keccak256("test-command");

        vm.expectRevert(abi.encodeWithSelector(IAxelarExecutable.NotApprovedByGateway.selector));
        adapter.execute(commandId, rootProviderChain, rootProviderContract, payload);
    }

    function test_Execute_EventEmitted() public {
        adapter.setVaultRootSource(rootProviderChain, rootProviderContract);
        adapter.setVaultRootReceiver(vaultRootReceiver);
        uint256 newRoot = 0x123;

        bytes32 commandId = keccak256("test-command");
        bytes memory payload = abi.encode(adapter.SET_VAULT_ROOT(), newRoot);

        vm.expectEmit(true, true, true, true);
        emit VaultRootReceiverAdapter.VaultRootReceived(newRoot);

        adapter.execute(commandId, rootProviderChain, rootProviderContract, payload);
    }
}
