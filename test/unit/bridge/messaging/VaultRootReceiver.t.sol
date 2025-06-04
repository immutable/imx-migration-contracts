// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import "@src/bridge/messaging/VaultRootReceiver.sol";
import "@src/withdrawals/VaultRootStore.sol";
import "../../../common/MockAxelarGateway.sol";
import {IAxelarExecutable} from "@axelar-gmp-sdk-solidity/interfaces/IAxelarExecutable.sol";

contract MockVaultRootStore is VaultRootStore {
    function setVaultRoot(uint256 _vaultRoot) external override {
        _setVaultRoot(_vaultRoot);
    }
}

contract VaultRootReceiverTest is Test {
    VaultRootReceiver private vaultRootReceiver;
    VaultRootStore private vaultRootStore;
    MockAxelarGateway private axelarGateway;
    address private owner;
    string private rootProviderChain;
    string private rootProviderContract;

    function setUp() public {
        owner = address(this);
        axelarGateway = new MockAxelarGateway(true);
        rootProviderChain = "ethereum";
        rootProviderContract = "0x456";

        vaultRootStore = new MockVaultRootStore();
        vaultRootReceiver =
            new VaultRootReceiver(rootProviderChain, rootProviderContract, owner, address(axelarGateway));
    }

    function test_Constructor() public view {
        assertEq(vaultRootReceiver.rootProviderChain(), rootProviderChain);
        assertEq(vaultRootReceiver.rootProviderContract(), rootProviderContract);
        assertEq(vaultRootReceiver.owner(), owner);
    }

    function test_RevertIf_Constructor_EmptyRootProviderChain() public {
        vm.expectRevert(abi.encodeWithSelector(VaultRootReceiver.InvalidSourceChain.selector, ""));
        new VaultRootReceiver("", rootProviderContract, owner, address(axelarGateway));
    }

    function test_RevertIf_Constructor_EmptyRootProviderContract() public {
        vm.expectRevert(abi.encodeWithSelector(VaultRootReceiver.InvalidSourceAddress.selector, ""));
        new VaultRootReceiver(rootProviderChain, "", owner, address(axelarGateway));
    }

    function test_SetVaultRootStore() public {
        vaultRootReceiver.setVaultRootStore(vaultRootStore);
        assertEq(address(vaultRootReceiver.vaultRootStore()), address(vaultRootStore));
    }

    function test_RevertIf_SetVaultRootStore_ZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(VaultRootReceiver.InvalidVaultRootStore.selector));
        vaultRootReceiver.setVaultRootStore(VaultRootStore(address(0)));
    }

    function test_RevertIf_SetVaultRootStore_Unauthorized() public {
        address unauthProvider = address(0x789);
        vm.prank(unauthProvider);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, unauthProvider));
        vaultRootReceiver.setVaultRootStore(vaultRootStore);
    }

    function test_Execute_ValidMessage() public {
        vaultRootReceiver.setVaultRootStore(vaultRootStore);
        uint256 newRoot = 0x123;

        bytes memory payload = abi.encode(newRoot);
        bytes32 commandId = keccak256("test-command");
        vaultRootReceiver.execute(commandId, rootProviderChain, rootProviderContract, payload);

        assertEq(vaultRootStore.vaultRoot(), newRoot);
    }

    function test_RevertIf_Execute_InvalidSourceChain() public {
        vaultRootReceiver.setVaultRootStore(vaultRootStore);
        uint256 newRoot = 0x123;

        bytes memory payload = abi.encode(newRoot);
        bytes32 commandId = keccak256("test-command");
        vm.expectRevert(abi.encodeWithSelector(VaultRootReceiver.InvalidSourceChain.selector, "polygon"));
        vaultRootReceiver.execute(commandId, "polygon", rootProviderContract, payload);
    }

    function test_RevertIf_Execute_InvalidSourceAddress() public {
        vaultRootReceiver.setVaultRootStore(vaultRootStore);
        uint256 newRoot = 0x123;

        bytes memory payload = abi.encode(newRoot);
        bytes32 commandId = keccak256("test-command");
        vm.expectRevert(abi.encodeWithSelector(VaultRootReceiver.InvalidSourceAddress.selector, "0x789"));
        vaultRootReceiver.execute(commandId, rootProviderChain, "0x789", payload);
    }

    function test_RevertIf_Execute_VaultRootStoreNotSet() public {
        uint256 newRoot = 0x123;
        bytes memory payload = abi.encode(newRoot);
        bytes32 commandId = keccak256("test-command");

        vm.expectRevert(VaultRootReceiver.VaultRootNotSet.selector);
        vaultRootReceiver.execute(commandId, rootProviderChain, rootProviderContract, payload);
    }

    function test_RevertIf_Execute_NotApprovedByGateway() public {
        vaultRootReceiver.setVaultRootStore(vaultRootStore);
        uint256 newRoot = 0x123;

        axelarGateway.setShouldValidate(false);
        bytes memory payload = abi.encode(newRoot);
        bytes32 commandId = keccak256("test-command");

        vm.expectRevert(abi.encodeWithSelector(IAxelarExecutable.NotApprovedByGateway.selector));
        vaultRootReceiver.execute(commandId, rootProviderChain, rootProviderContract, payload);
    }

    function test_Execute_EventEmitted() public {
        vaultRootReceiver.setVaultRootStore(vaultRootStore);
        uint256 newRoot = 0x123;

        bytes32 commandId = keccak256("test-command");
        bytes memory payload = abi.encode(newRoot);

        vm.expectEmit(true, true, true, true);
        emit VaultRootReceiver.VaultRootReceived(newRoot);

        vaultRootReceiver.execute(commandId, rootProviderChain, rootProviderContract, payload);
    }
}
