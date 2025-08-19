// Copyright Immutable Pty Ltd 2018 - 2025
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

abstract contract AccountRootReceiver {
    /// @notice Thrown when the account root hash is invalid
    error InvalidAccountRoot();

    /// @notice Thrown when the account root has not been set before attempting to verify a proof
    error AccountRootNotSet();

    /// @notice Emitted when the account root is set or updated
    event AccountRootSet(bytes32 indexed oldRoot, bytes32 indexed newRoot);

    /// @notice Thrown when attempting to override an existing account root without proper authorization
    error RootOverrideNotAllowed();

    /// @notice The Merkle root of the account associations tree
    bytes32 public accountRoot;

    function _setAccountRoot(bytes32 newRoot, bool _overrideExisting) internal {
        require(newRoot != bytes32(0), InvalidAccountRoot());
        require(accountRoot == bytes32(0) || _overrideExisting, RootOverrideNotAllowed());

        bytes32 oldRoot = accountRoot;
        accountRoot = newRoot;

        emit AccountRootSet(oldRoot, newRoot);
    }

    function setAccountRoot(bytes32 newRoot) external virtual;
}
