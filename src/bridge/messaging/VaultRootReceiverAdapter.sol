// Copyright Immutable Pty Ltd 2018 - 2025
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {AxelarExecutable} from "@axelar-gmp-sdk-solidity/executable/AxelarExecutable.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {VaultRootReceiver} from "@src/withdrawals/VaultRootReceiver.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title Vault Root Receiver Adapter
 * @notice Receives vault root hash from the StarkEx bridge on Ethereum, through a cross-chain message, which it then forwards to a VaultRootReceiver.
 * @dev This contract relies on the Axelar GMP to receive cross-chain messages from the StarkEx bridge on Ethereum.
 * @dev The contract's owner can:
 *     - Set details of the source of the vault root hash, as identified by the chain ID and contract address.
 *     - Set the VaultRootReceiver contract that the vault root hash will be forwarded to.
 * @dev The contract does not process messages if the VaultRootReceiver and the source of the vault root hash are not yet configured.
 */
contract VaultRootReceiverAdapter is AxelarExecutable, Ownable {
    /// @notice Thrown when an invalid chain ID is provided for the vault root source.
    error InvalidChainId();

    /// @notice Thrown when the cross-chain message does not match the expected format or signature.
    error InvalidMessage();

    /// @notice Thrown when a cross-chain message is received by an unauthorized sender.
    error UnauthorizedMessageSender(string);

    /// @notice Thrown when attempting to perform an action that requires the VaultRootReceiver to be set, when it is not set.
    error VaultRootReceiverNotSet();

    /// @notice Thrown when attempting to perform an action that requires the vault root source chain id and contract to be set, when they are not set.
    error VaultRootSourceNotSet();

    /// @notice Emitted when the vault root source chain and contract are set.
    event VaultRootSourceSet(
        string indexed oldRootSenderAddress,
        string indexed oldRootSenderChain,
        string indexed newRootSenderAddress,
        string newRootSenderChain
    );

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

        string memory _oldRootSenderChain = rootSenderChain;
        string memory _oldRootSenderAddress = rootSenderAddress;

        rootSenderChain = _rootSenderChain;
        rootSenderAddress = _rootSenderAddress;

        emit VaultRootSourceSet(_oldRootSenderAddress, _oldRootSenderChain, _rootSenderAddress, _rootSenderChain);
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
        // Ensure the adapter is in a valid state to process messages.
        require(address(rootReceiver) != address(0), VaultRootReceiverNotSet());
        require(bytes(rootSenderAddress).length != 0, VaultRootSourceNotSet());

        // Validate the sender
        require(Strings.equal(_sourceChain, rootSenderChain), UnauthorizedMessageSender("unexpected chain"));
        require(
            Strings.equal(_sourceAddress, rootSenderAddress), UnauthorizedMessageSender("unexpected contract address")
        );

        // Decode the payload and ensure it is structurally valid.
        require(_payload.length > 32, InvalidMessage());
        (bytes32 sig, uint256 vaultRoot) = abi.decode(_payload, (bytes32, uint256));
        require(sig == SET_VAULT_ROOT, InvalidMessage());

        // Forward the vault root to the VaultRootReceiver contract.
        rootReceiver.setVaultRoot(vaultRoot);

        emit VaultRootReceived(vaultRoot);
    }
}
