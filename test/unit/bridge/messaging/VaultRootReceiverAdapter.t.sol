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
    }

    function test_SetVaultRootReceiver() public {
        adapter.setVaultRootReceiver(vaultRootReceiver);
        assertEq(address(adapter.rootReceiver()), address(vaultRootReceiver));
    }

    function test_RevertIf_SetVaultRootReceiver_ZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(IAxelarExecutable.InvalidAddress.selector));
        adapter.setVaultRootReceiver(VaultRootReceiver(address(0)));
    }

    function test_RevertIf_SetVaultRootReceiver_Unauthorized() public {
        address unauthProvider = address(0x789);
        vm.prank(unauthProvider);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, unauthProvider));
        adapter.setVaultRootReceiver(vaultRootReceiver);
    }

    function setVaultRootSource() public {
        adapter.setVaultRootSource(rootProviderChain, rootProviderContract);
        assertEq(adapter.rootSenderChain(), rootProviderChain);
        assertEq(adapter.rootSenderAddress(), rootProviderContract);
    }

    function setVaultRootSource_InvalidChain() public {
        vm.expectRevert(VaultRootReceiverAdapter.InvalidChainId.selector);
        adapter.setVaultRootSource("", rootProviderContract);
    }

    function setVaultRootSource_InvalidAddress() public {
        vm.expectRevert(IAxelarExecutable.InvalidAddress.selector);
        adapter.setVaultRootSource(rootProviderChain, "");
    }

    function setVaultRootSource_Unauthorized() public {
        address unauthProvider = address(0x789);
        vm.prank(unauthProvider);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, unauthProvider));
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
        vm.expectRevert(abi.encodeWithSelector(VaultRootReceiverAdapter.UnauthorizedMessageSender.selector, "polygon"));
        adapter.execute(commandId, "polygon", rootProviderContract, payload);
    }

    function test_RevertIf_Execute_UnauthorizedSenderAddress() public {
        adapter.setVaultRootSource(rootProviderChain, rootProviderContract);
        adapter.setVaultRootReceiver(vaultRootReceiver);
        uint256 newRoot = 0x123;

        bytes memory payload = abi.encode(adapter.SET_VAULT_ROOT(), newRoot);
        bytes32 commandId = keccak256("test-command");
        vm.expectRevert(abi.encodeWithSelector(VaultRootReceiverAdapter.UnauthorizedMessageSender.selector, "0x789"));
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
