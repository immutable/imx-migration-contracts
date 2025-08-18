// Copyright Immutable Pty Ltd 2018 - 2025
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {AxelarExecutable} from "@axelar-gmp-sdk-solidity/executable/AxelarExecutable.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import "../../withdrawals/VaultRootReceiver.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import "forge-std/console.sol";

/**
 * @title VaultRootReceiverAdapter
 * @notice Receives a cross-chain message containing the latest vault root hash, from the StarkExchange contract on Ethereum, and forwards it to the registered VaultRootReceiver contract.
 * @dev This contract relies on the Axelar cross-chain messaging protocol to receive messages from the StarkExchange contract on Ethereum.
 * @dev The contract owner can set the VaultRootReceiver and the source chain and contract that are authorised to send the vault root hash.
 * @dev Once key security parameters are configured, it is expected that the owner of this contract will renounce ownership to prevent further changes.
 */
contract VaultRootReceiverAdapter is AxelarExecutable, Ownable {
    /// @notice Thrown when an invalid chain ID is provided for the vault root source.
    error InvalidChainId();

    /// @notice Thrown when the cross-chain message does not match the expected format or signature.
    error InvalidMessage();

    /// @notice Thrown when a cross-chain message is received by an unauthorized sender.
    error UnauthorizedMessageSender();

    /// @notice Thrown when attempting to perform an action that requires the VaultRootReceiver to be set, when it is not set.
    error VaultRootReceiverNotSet();

    /// @notice Thrown when attempting to perform an action that requires the vault root source chain id and contract to be set, when they are not set.
    error VaultRootSourceNotSet();

    /// @notice Emitted when the VaultRootReceiver contract is set.
    event VaultRootReceiverSet(address indexed vaultRootReceiver);

    /// @notice Emitted when a vault root has been received from the StarkExchange contract on Ethereum, and forwarded to the VaultRootReceiver contract.
    event VaultRootReceived(uint256 vaultRoot);

    bytes32 public constant SET_VAULT_ROOT = keccak256("SET_VAULT_ROOT");

    /// @notice The VaultRootReceiver contract that stores the vault root hash.
    VaultRootReceiver public rootReceiver;

    /// @notice The chain ID of the root provider contract that is authorised to send the vault root hash.
    /// @dev The chain ID is based on Axelar's chain ID format, which is the chain name, and not EIP-155 chain IDs.
    string public rootSenderChain;

    /// @notice The address of the root provider contract that is authorised to send the vault root hash.
    /// @dev This is a string representation of the contract address
    string public rootSenderAddress;

    /**
     * @notice Constructs the VaultRootReceiverAdapter contract.
     * @param _owner The address of the privileged operator who can set parameters.
     * @param _axelarGateway The address of the AxelarGateway contract that validates cross-chain messages.
     */
    constructor(address _owner, address _axelarGateway) AxelarExecutable(_axelarGateway) Ownable(_owner) {}

    /**
     * @notice Sets the VaultRootReceiver contract that this adapter will forward received vault root hash to.
     * @param _vaultRootReceiver The address of the VaultRootReceiver contract.
     * @dev This function can only be called by the contract owner.
     */
    function setVaultRootReceiver(VaultRootReceiver _vaultRootReceiver) external onlyOwner {
        require(address(_vaultRootReceiver) != address(0), InvalidAddress());
        rootReceiver = _vaultRootReceiver;
        emit VaultRootReceiverSet(address(_vaultRootReceiver));
    }

    /**
     * @notice Sets the source chain and contract that this receiver will accept vault root hashes from.
     * @param _rootSenderChain The chain ID of the root provider contract.
     * @param _rootSenderAddress The address of the root provider contract.
     * @dev This function can only be called by the contract owner.
     * @dev The chain ID is based on Axelar's chain ID format, which is the chain name, and not EIP-155 chain IDs.
     */
    function setVaultRootSource(string calldata _rootSenderChain, string calldata _rootSenderAddress)
        external
        onlyOwner
    {
        require(bytes(_rootSenderChain).length != 0, InvalidChainId());
        require(bytes(_rootSenderAddress).length != 0, InvalidAddress());

        rootSenderChain = _rootSenderChain;
        rootSenderAddress = _rootSenderAddress;
    }

    /**
     * @dev Executed when a cross-chain message is received.
     * @dev If the sender, as identified by the source chain and contract address of the message, is the authorised sender then the provided vault root hash is forwarded to the VaultRootReceiver contract.
     * @param _sourceChain The ID of the source chain that sent the message.
     * @param _sourceAddress The address of the contract that sent the message.
     * @param _payload The payload of the message, which should contain the vault root hash to be set.
     */
    function _execute(bytes32, string calldata _sourceChain, string calldata _sourceAddress, bytes calldata _payload)
        internal
        override
    {
        // Ensure that the VaultRootReceiver and the root sender details are set
        require(address(rootReceiver) != address(0), VaultRootReceiverNotSet());
        require(bytes(rootSenderChain).length != 0 && bytes(rootSenderAddress).length != 0, VaultRootSourceNotSet());

        require(Strings.equal(_sourceChain, rootSenderChain), UnauthorizedMessageSender());
        require(Strings.equal(_sourceAddress, rootSenderAddress), UnauthorizedMessageSender());
        require(_payload.length > 32, InvalidMessage());

        (bytes32 sig, uint256 vaultRoot) = abi.decode(_payload, (bytes32, uint256));

        require(sig == SET_VAULT_ROOT, InvalidMessage());

        rootReceiver.setVaultRoot(vaultRoot);
        emit VaultRootReceived(vaultRoot);
    }
}
