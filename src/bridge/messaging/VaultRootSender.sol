// Copyright Immutable Pty Ltd 2018 - 2025
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "@axelar-gmp-sdk-solidity/interfaces/IAxelarGasService.sol";
import {AxelarExecutable} from "@axelar-gmp-sdk-solidity/executable/AxelarExecutable.sol";
import {IAxelarGateway} from "@axelar-gmp-sdk-solidity/interfaces/IAxelarGateway.sol";

/**
 * @title VaultRootSender
 * @notice This contract is responsible for sending vault root hashes from L1 to L2 via Axelar's cross-chain messaging protocol.
 * @dev The contract integrates with Axelar's gas service to handle cross-chain gas payments and the gateway for message passing.
 * @dev Only the StarkEx bridge contract is authorized to trigger vault root sending.
 */
contract VaultRootSender is AxelarExecutable {
    /// @notice The StarkEx bridge contract address that is authorized to send vault roots
    address public immutable vaultRootSource;

    /// @notice The Axelar gas service contract for handling cross-chain gas payments
    IAxelarGasService public immutable axelarGasService;

    /// @notice The chain ID of the destination zkEVM chain
    string public destinationChain;
    /// @notice The address of the vault receiver contract on the destination zkEVM chain
    string public destinationReceiver;

    /**
     * @notice Emitted when a vault root is sent to the destination chain
     * @param destinationChain The chain ID of the destination chain
     * @param vaultReceiver The address of the vault receiver contract on the destination chain
     * @param payload The encoded vault root data being sent
     */
    event VaultRootSent(string indexed destinationChain, string indexed vaultReceiver, bytes indexed payload);

    /// @notice Thrown when an invalid chain ID is provided
    error InvalidChainId();
    /// @notice Thrown when an unauthorized caller attempts to send a vault root
    error UnauthorizedCaller();
    /// @notice Thrown when no bridge fee is provided for the cross-chain transaction
    error NoBridgeFee();
    /// @notice Thrown when an invalid vault root (zero value) is provided
    error InvalidVaultRoot();

    /**
     * @notice Constructs the VaultRootSender contract
     * @param _vaultRootSource The address of the StarkEx bridge contract that can send vault roots
     * @param _destinationReceiver The address of the vault receiver contract on the destination zkEVM chain
     * @param _destinationChain The chain ID of the destination zkEVM chain
     * @param _axelarGasService The address of the Axelar gas service contract
     * @param _axelarGateway The address of the Axelar gateway contract
     */
    constructor(
        address _vaultRootSource,
        string memory _destinationReceiver,
        string memory _destinationChain,
        address _axelarGasService,
        address _axelarGateway
    ) AxelarExecutable(_axelarGateway) {
        require(_vaultRootSource != address(0), InvalidAddress());
        require(_axelarGasService != address(0), InvalidAddress());
        require(bytes(_destinationReceiver).length > 0, InvalidAddress());
        require(bytes(_destinationChain).length > 0, InvalidChainId());

        vaultRootSource = _vaultRootSource;
        destinationReceiver = _destinationReceiver;
        destinationChain = _destinationChain;
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

        // Load from storage.
        string memory _zkEVMVaultReceiver = destinationReceiver;
        string memory _zkEVMChainId = destinationChain;
        bytes memory payload = abi.encode(vaultRoot);

        axelarGasService.payNativeGasForContractCall{value: msg.value}(
            address(this), _zkEVMChainId, _zkEVMVaultReceiver, payload, gasRefundReceiver
        );

        IAxelarGateway(gatewayAddress).callContract(_zkEVMChainId, _zkEVMVaultReceiver, payload);
        emit VaultRootSent(_zkEVMChainId, _zkEVMVaultReceiver, payload);
    }

    function _execute(bytes32, string calldata, string calldata, bytes calldata) internal pure override {
        revert("Not Supported");
    }
}
