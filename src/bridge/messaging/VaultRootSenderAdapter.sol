// Copyright Immutable Pty Ltd 2018 - 2025
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IAxelarGasService} from "@axelar-gmp-sdk-solidity/interfaces/IAxelarGasService.sol";
import {AxelarExecutable} from "@axelar-gmp-sdk-solidity/executable/AxelarExecutable.sol";
import {IAxelarGateway} from "@axelar-gmp-sdk-solidity/interfaces/IAxelarGateway.sol";

/**
 * @title Vault Root Sender Adapter
 * @notice Sends vault root hashes to a designated vault receiver contract on zkEVM.
 * @dev This contract relies on the Axelar GMP to send the vault root hash across chains.
 * @dev Only the configured vault root sender is authorized to send vault root hashes through this adapter. The sender is the StarkEx bridge contract on Ethereum.
 */
contract VaultRootSenderAdapter is AxelarExecutable {
    bytes32 public constant SET_VAULT_ROOT = keccak256("SET_VAULT_ROOT");

    /// @notice The StarkEx bridge contract address that is authorized to send vault roots through this adapter
    address public immutable VAULT_ROOT_SENDER;

    /// @notice The Axelar gas service contract that handles gas payments for cross-chain transactions
    IAxelarGasService public immutable AXELAR_GAS_SERVICE;

    /// @notice The chain ID to which the vault root will be sent
    /// @dev This is a string representation of the chain name, as used by Axelar
    string public rootReceiverChain;

    /// @notice The address of the vault root receiver contract on the destination chain
    /// @dev This is a string representation of the contract address
    string public rootReceiver;

    /**
     * @notice Emitted when a vault root is sent to the destination chain
     * @param _destinationChain The chain ID of the destination chain
     * @param _destinationReceiver The address of the vault receiver contract on the destination chain
     * @param _payload The encoded vault root data being sent
     */
    event VaultRootSent(string indexed _destinationChain, string indexed _destinationReceiver, bytes indexed _payload);

    /// @notice Thrown when an invalid chain ID is provided for the vault root destination.
    error InvalidChainId();

    /// @notice Thrown when any entity other than the authorised `vaultRootSender` attempts to send a vault root through this adapter
    error UnauthorizedRootSender();

    /// @notice Thrown when no destination gas fee is provided for the cross-chain transaction
    error NoBridgeFee();

    /// @notice Thrown when an invalid vault root (zero value) is provided
    error InvalidVaultRoot();

    /**
     * @notice Constructs the VaultRootSender contract
     * @param _vaultRootSender The address of the StarkEx bridge contract that can send vault roots
     * @param _rootReceiver The address of the vault receiver contract on the destination zkEVM chain
     * @param _rootReceiverChain The chain ID of the destination zkEVM chain
     * @param _axelarGasService The address of the Axelar gas service contract
     * @param _axelarGateway The address of the Axelar gateway contract
     */
    constructor(
        address _vaultRootSender,
        string memory _rootReceiver,
        string memory _rootReceiverChain,
        address _axelarGasService,
        address _axelarGateway
    ) AxelarExecutable(_axelarGateway) {
        require(bytes(_rootReceiverChain).length > 0, InvalidChainId());
        require(bytes(_rootReceiver).length > 0, InvalidAddress());
        require(_vaultRootSender != address(0), InvalidAddress());
        require(_axelarGasService != address(0), InvalidAddress());

        rootReceiverChain = _rootReceiverChain;
        rootReceiver = _rootReceiver;
        VAULT_ROOT_SENDER = _vaultRootSender;
        AXELAR_GAS_SERVICE = IAxelarGasService(_axelarGasService);
    }

    /**
     * @notice Sends a vault root hash to the destination zkEVM chain via Axelar
     * @dev Only the StarkEx bridge contract can call this function
     * @dev Requires a bridge fee to be sent with the transaction for gas payment
     * @param vaultRoot The vault root hash to send
     * @param gasRefundReceiver The address that will receive any unused destination gas fee
     */
    function sendVaultRoot(uint256 vaultRoot, address gasRefundReceiver) external payable {
        require(msg.sender == VAULT_ROOT_SENDER, UnauthorizedRootSender());

        require(vaultRoot != 0, InvalidVaultRoot());
        require(gasRefundReceiver != address(0), InvalidAddress());
        require(msg.value > 0, NoBridgeFee());

        string memory _receiverChain = rootReceiverChain;
        string memory _receiverAddr = rootReceiver;
        bytes memory payload = abi.encode(SET_VAULT_ROOT, vaultRoot);

        AXELAR_GAS_SERVICE.payNativeGasForContractCall{value: msg.value}(
            address(this), _receiverChain, _receiverAddr, payload, gasRefundReceiver
        );

        IAxelarGateway(gatewayAddress).callContract(_receiverChain, _receiverAddr, payload);

        emit VaultRootSent(_receiverChain, _receiverAddr, payload);
    }

    function _execute(bytes32, string calldata, string calldata, bytes calldata) internal pure override {
        revert("Not Supported");
    }
}
