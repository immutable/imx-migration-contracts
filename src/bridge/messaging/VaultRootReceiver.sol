// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {AxelarExecutable} from "@axelar-gmp-sdk-solidity/executable/AxelarExecutable.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import "@src/withdrawals/VaultRootStore.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @notice VaultRootReceiver receives an Axelar message containing a vault root hash from a corresponding vault root provider contract on L1, and stores it in the VaultRootStore.
 */
contract VaultRootReceiver is AxelarExecutable, Ownable {
    /// @notice Emitted when the source chain is invalid or does not match the expected one.
    error InvalidSourceChain(string sourceChain);
    /// @notice Emitted when the source address is invalid or does not match the expected one.
    error InvalidSourceAddress(string sourceAddress);

    /// @notice Emitted when the VaultRootStore address is invalid.
    error InvalidVaultRootStore();

    error VaultRootNotSet();

    /// @notice Emitted when the VaultRootStore is set.
    event VaultRootStoreSet(address indexed vaultRootStore);

    event VaultRootReceived(uint256 vaultRoot);

    /// @notice The VaultRootStore contract that stores the vault root hash.
    VaultRootStore public vaultRootStore;
    /// @notice The chain ID of the root provider contract that is authorised to send the vault root hash.
    string public rootProviderChain;
    /// @notice The contract address of the root provider contract that is authorised to send the vault root hash.
    string public rootProviderContract;

    /**
     * @notice Constructs the VaultRootReceiver contract.
     * @param _rootProviderChain The chain ID of the root provider contract that is authorised to send the vault root hash.
     * @param _rootProviderContract The contract address of the root provider contract that is authorised to send the vault root hash.
     * @param _owner The address of the owner of the contract, who can set the VaultRootStore.
     * @param _axelarGateway The address of the Axelar gateway contract that validates cross-chain messages.
     */
    constructor(
        string memory _rootProviderChain,
        string memory _rootProviderContract,
        address _owner,
        address _axelarGateway
    ) AxelarExecutable(_axelarGateway) Ownable(_owner) {
        require(bytes(_rootProviderChain).length != 0, InvalidSourceChain(""));
        require(bytes(_rootProviderContract).length != 0, InvalidSourceAddress(""));

        // Register the vault state sender as a trusted source for messages
        rootProviderChain = _rootProviderChain;
        rootProviderContract = _rootProviderContract;
    }

    function setVaultRootStore(VaultRootStore _vaultRootStore) external onlyOwner {
        require(address(_vaultRootStore) != address(0), InvalidVaultRootStore());
        vaultRootStore = _vaultRootStore;
        emit VaultRootStoreSet(address(_vaultRootStore));
    }

    /**
     * @notice Executed when a cross-chain message is received from L1. If the sender is authorised, it sets the provided vault root hash in the VaultRootStore contract.
     * @param _sourceChain The chain ID of the source chain from which the message was sent.
     * @param _sourceAddress The contract address of the source contract that sent the message.
     * @param _payload The payload of the message, which contains the vault root hash to be set.
     */
    function _execute(bytes32, string calldata _sourceChain, string calldata _sourceAddress, bytes calldata _payload)
        internal
        override
    {
        require(Strings.equal(_sourceChain, rootProviderChain), InvalidSourceChain(_sourceChain));
        require(Strings.equal(_sourceAddress, rootProviderContract), InvalidSourceAddress(_sourceAddress));
        require(address(vaultRootStore) != address(0), VaultRootNotSet());

        (uint256 vaultRoot) = abi.decode(_payload, (uint256));

        vaultRootStore.setVaultRoot(vaultRoot);
        emit VaultRootReceived(vaultRoot);
    }
}
