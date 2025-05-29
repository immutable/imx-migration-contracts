// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

interface IVaultRootStore {
    error InvalidVaultRoot();
    error VaultRootAlreadySet();

    event VaultRootSet(uint256 indexed vaultRoot);

    function setVaultRoot(uint256 vaultRoot) external;
}
