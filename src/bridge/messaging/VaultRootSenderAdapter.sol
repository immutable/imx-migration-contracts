// Copyright Immutable Pty Ltd 2018 - 2025
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "@axelar-gmp-sdk-solidity/interfaces/IAxelarGasService.sol";
import {AxelarExecutable} from "@axelar-gmp-sdk-solidity/executable/AxelarExecutable.sol";
import {IAxelarGateway} from "@axelar-gmp-sdk-solidity/interfaces/IAxelarGateway.sol";

/**
 * @title VaultRootSenderAdapter
 * @notice This contract serves as an adapter to send vault root hashes from the StarkExchange bridge contract on Ethereum to a designated vault receiver contract on zkEVM using Axelar's cross-chain messaging protocol.
 * @dev The contract relies on Axelar messaging protocol to send vault root hashes to a specified destination chain and receiver contract.
 * @dev Only the configured StarkExchange bridge contract is authorized to send vault root hashes through this adapter.
 */
contract VaultRootSenderAdapter is AxelarExecutable {
    bytes32 public constant SET_VAULT_ROOT = keccak256("SET_VAULT_ROOT");

    /// @notice The StarkEx bridge contract address that is authorized to send vault roots through this adapter
    address public immutable vaultRootSource;

    /// @notice The Axelar gas service contract that handles gas payments for cross-chain transactions
    IAxelarGasService public immutable axelarGasService;

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

    /// @notice Thrown when any entity other than the authorised `vaultRootSource` attempts to send a vault root through this adapter
    error UnauthorizedCaller();

    /// @notice Thrown when no destination gas fee is provided for the cross-chain transaction
    error NoBridgeFee();

    /// @notice Thrown when an invalid vault root (zero value) is provided
    error InvalidVaultRoot();

    /**
     * @notice Constructs the VaultRootSender contract
     * @param _vaultRootSource The address of the StarkEx bridge contract that can send vault roots
     * @param _rootReceiver The address of the vault receiver contract on the destination zkEVM chain
     * @param _rootReceiverChain The chain ID of the destination zkEVM chain
     * @param _axelarGasService The address of the Axelar gas service contract
     * @param _axelarGateway The address of the Axelar gateway contract
     */
    constructor(
        address _vaultRootSource,
        string memory _rootReceiver,
        string memory _rootReceiverChain,
        address _axelarGasService,
        address _axelarGateway
    ) AxelarExecutable(_axelarGateway) {
        require(_axelarGasService != address(0), InvalidAddress());
        require(bytes(_rootReceiverChain).length > 0, InvalidChainId());
        require(bytes(_rootReceiver).length > 0, InvalidAddress());
        require(_vaultRootSource != address(0), InvalidAddress());

        vaultRootSource = _vaultRootSource;
        rootReceiver = _rootReceiver;
        rootReceiverChain = _rootReceiverChain;
        axelarGasService = IAxelarGasService(_axelarGasService);
    }

    /**
     * @notice Sends a vault root hash to the destination zkEVM chain via Axelar
     * @dev Only the StarkEx bridge contract can call this function
     * @dev Requires a bridge fee to be sent with the transaction for gas payment
     * @param vaultRoot The vault root hash to send
     * @param gasRefundReceiver The address that will receive any unused gas fees
     */
    function sendVaultRoot(uint256 vaultRoot, address gasRefundReceiver) external payable {
        require(msg.sender == vaultRootSource, UnauthorizedCaller());
        require(msg.value > 0, NoBridgeFee());
        require(gasRefundReceiver != address(0), InvalidAddress());
        require(vaultRoot != 0, InvalidVaultRoot());

        string memory _rootReceiver = rootReceiver;
        string memory _rootReceiverChain = rootReceiverChain;
        bytes memory vaultRootPayload = abi.encode(SET_VAULT_ROOT, vaultRoot);

        axelarGasService.payNativeGasForContractCall{value: msg.value}(
            address(this), _rootReceiverChain, _rootReceiver, vaultRootPayload, gasRefundReceiver
        );

        IAxelarGateway(gatewayAddress).callContract(_rootReceiverChain, _rootReceiver, vaultRootPayload);
        emit VaultRootSent(_rootReceiverChain, _rootReceiver, vaultRootPayload);
    }

    function _execute(bytes32, string calldata, string calldata, bytes calldata) internal pure override {
        revert("Not Supported");
    }
}
