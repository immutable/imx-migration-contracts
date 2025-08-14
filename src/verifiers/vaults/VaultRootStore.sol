// Copyright Immutable Pty Ltd 2018 - 2025
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/**
 * @title VaultRootStore
 * @notice Abstract contract for storing and managing vault root hashes
 * @dev This contract provides a base implementation for storing Merkle root hashes
 *      that represent the state of vaults in the Immutable X system
 * @dev TODO: One possible optimisation to consider is having multiple intermediate roots
 *      in the main merkle tree, stored and used to prove against
 */
abstract contract VaultRootStore {
    /// @notice Thrown when attempting to set an invalid vault root (zero value)
    error InvalidVaultRoot();
    error VaultRootNotSet();
    /// @notice Thrown when attempting to override an existing vault root without proper authorization
    error VaultRootOverrideNotAllowed();

    /**
     * @notice Emitted when the vault root is updated
     * @param oldRoot The previous vault root hash
     * @param newRoot The new vault root hash
     */
    event VaultRootSet(uint256 indexed oldRoot, uint256 indexed newRoot);

    /// @notice The current vault root hash representing the state of all vaults
    uint256 public vaultRoot;

    /**
     * @notice Internal function to set a new vault root hash
     * @dev This function validates that the new root is not zero and emits an event
     * @param _newRoot The new vault root hash to set
     */
    function _setVaultRoot(uint256 _newRoot, bool _rootOverrideAllowed) internal virtual {
        require(_newRoot != 0, InvalidVaultRoot());
        require(vaultRoot == 0 || _rootOverrideAllowed, VaultRootOverrideNotAllowed());
        emit VaultRootSet(vaultRoot, _newRoot);
        vaultRoot = _newRoot;
    }

    /**
     * @notice External function to set the vault root hash
     * @dev This function must be implemented by derived contracts
     * @param _vaultRoot The vault root hash to set
     */
    function setVaultRoot(uint256 _vaultRoot) external virtual;
}
