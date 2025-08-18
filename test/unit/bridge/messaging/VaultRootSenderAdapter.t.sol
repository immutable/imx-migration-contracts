// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {VaultRootSenderAdapter} from "@src/bridge/messaging/VaultRootSenderAdapter.sol";
import {IAxelarExecutable} from "@axelar-gmp-sdk-solidity/interfaces/IAxelarExecutable.sol";
import {MockAxelarGasService} from "../../../common/MockAxelarGasService.sol";
import {MockAxelarGateway} from "../../../common/MockAxelarGateway.sol";

contract VaultRootSenderAdapterTest is Test {
    address private constant L1_STARKEX_BRIDGE = 0x5FDCCA53617f4d2b9134B29090C87D01058e27e9;
    address private constant L2_VAULT_PROCESSOR = 0x5Ffb1b3C4D6E8B7A9c1E8d3f2b5e6f7a8B9C0d1E; // Mock L2 Vault Processor address
    string private constant L2_VAULT_RECEIVER = "0x0987654321098765432109876543210987654321"; // Mock L2 Vault Receiver
    string private constant L2_CHAIN_ID = "immutable";

    address private gasService;
    address private gateway;

    uint256 private constant bridgeFee = 0.001 ether;
    VaultRootSenderAdapter private sender;

    function setUp() public {
        gasService = address(new MockAxelarGasService());
        gateway = address(new MockAxelarGateway(true));
        sender = new VaultRootSenderAdapter(L1_STARKEX_BRIDGE, L2_VAULT_RECEIVER, L2_CHAIN_ID, gasService, gateway);
    }

    function test_Constructor() public view {
        assertEq(sender.vaultRootSource(), L1_STARKEX_BRIDGE);
        assertEq(sender.rootReceiver(), L2_VAULT_RECEIVER);
        assertEq(sender.rootReceiverChain(), L2_CHAIN_ID);
        assertEq(address(sender.axelarGasService()), gasService);
        assertEq(address(sender.gateway()), gateway);
    }

    function test_RevertIf_Constructor_ZeroStarkExBridgeAddress() public {
        vm.expectRevert(IAxelarExecutable.InvalidAddress.selector);
        new VaultRootSenderAdapter(address(0), L2_VAULT_RECEIVER, L2_CHAIN_ID, gasService, gateway);
    }

    function test_RevertIf_Constructor_InvalidVaultReceiver() public {
        vm.expectRevert(IAxelarExecutable.InvalidAddress.selector);
        new VaultRootSenderAdapter(L1_STARKEX_BRIDGE, "", L2_CHAIN_ID, gasService, gateway);
    }

    function test_RevertIf_Constructor_InvalidChainId() public {
        vm.expectRevert(VaultRootSenderAdapter.InvalidChainId.selector);
        new VaultRootSenderAdapter(L1_STARKEX_BRIDGE, L2_VAULT_RECEIVER, "", gasService, gateway);
    }

    function test_RevertIf_Constructor_ZeroGasServiceAddress() public {
        vm.expectRevert(IAxelarExecutable.InvalidAddress.selector);
        new VaultRootSenderAdapter(L1_STARKEX_BRIDGE, L2_VAULT_RECEIVER, L2_CHAIN_ID, address(0), gateway);
    }

    function test_RevertIf_Constructor_ZeroGatewayAddress() public {
        vm.expectRevert(IAxelarExecutable.InvalidAddress.selector);
        new VaultRootSenderAdapter(L1_STARKEX_BRIDGE, L2_VAULT_RECEIVER, L2_CHAIN_ID, gasService, address(0));
    }

    function test_SendVaultRoot() public {
        vm.deal(L1_STARKEX_BRIDGE, bridgeFee);
        vm.startPrank(L1_STARKEX_BRIDGE);
        uint256 vaultRoot = 1234567890;
        address refundAddress = address(0x1);
        bytes memory payload = abi.encode(sender.SET_VAULT_ROOT(), vaultRoot);

        vm.expectCall(
            address(gasService),
            bridgeFee,
            abi.encodeCall(
                MockAxelarGasService(gasService).payNativeGasForContractCall,
                (address(sender), L2_CHAIN_ID, L2_VAULT_RECEIVER, payload, refundAddress)
            )
        );
        vm.expectCall(
            address(gateway),
            0,
            abi.encodeCall(MockAxelarGateway(gateway).callContract, (L2_CHAIN_ID, L2_VAULT_RECEIVER, payload))
        );

        // Check that the event was emitted
        vm.expectEmit(true, true, true, true);
        emit VaultRootSenderAdapter.VaultRootSent(L2_CHAIN_ID, L2_VAULT_RECEIVER, payload);
        sender.sendVaultRoot{value: bridgeFee}(vaultRoot, refundAddress);
    }

    function test_RevertIf_SendVaultRoot_CallerNotBridge() public {
        vm.expectRevert(VaultRootSenderAdapter.UnauthorizedCaller.selector);
        sender.sendVaultRoot(1234567890, address(0));
    }

    function test_RevertIf_SendVaultRoot_NoBridgeFee() public {
        vm.startPrank(L1_STARKEX_BRIDGE);
        vm.expectRevert(VaultRootSenderAdapter.NoBridgeFee.selector);
        sender.sendVaultRoot(1234567890, address(0x123));
    }

    function test_RevertIf_SendVaultRoot_ZeroGasRefundAddress() public {
        vm.deal(L1_STARKEX_BRIDGE, bridgeFee);
        vm.startPrank(L1_STARKEX_BRIDGE);
        vm.expectRevert(IAxelarExecutable.InvalidAddress.selector);
        sender.sendVaultRoot{value: bridgeFee}(1234567890, address(0));
    }

    function test_RevertIf_SendVaultRoot_InvalidVaultRoot() public {
        vm.deal(L1_STARKEX_BRIDGE, bridgeFee);
        vm.startPrank(L1_STARKEX_BRIDGE);
        vm.expectRevert(VaultRootSenderAdapter.InvalidVaultRoot.selector);
        sender.sendVaultRoot{value: bridgeFee}(0, address(0x123));
    }

    function test_Execute_NotSupported() public {
        vm.expectRevert("Not Supported");
        sender.execute(keccak256("test-command"), "chain", "address", "payload");
    }
}
