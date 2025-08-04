// Copyright Immutable Pty Ltd 2018 - 2025
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

//  TODO: One possible optimisation to consider is having multiple intermediate roots in the main merkle tree, stored and used to prove against
abstract contract VaultRootStore {
    error InvalidVaultRoot();

    event VaultRootSet(uint256 indexed oldRoot, uint256 indexed newRoot);

    uint256 public vaultRoot;

    function _setVaultRoot(uint256 _newRoot) internal virtual {
        require(_newRoot != 0, InvalidVaultRoot());
        emit VaultRootSet(vaultRoot, _newRoot);
        vaultRoot = _newRoot;
    }

    function setVaultRoot(uint256 _vaultRoot) external virtual;
}
