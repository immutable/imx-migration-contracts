// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

//  TODO: One possible optimisation to consider is having multiple intermediate roots in the main merkle tree, stored and used to prove against
abstract contract VaultRootStore {
    error InvalidVaultRoot();
    error VaultRootAlreadySet();

    event VaultRootSet(uint256 indexed vaultRoot);

    address public immutable vaultRootProvider;
    uint256 public vaultRoot;

    constructor(address _vaultRootProvider) {
        require(_vaultRootProvider != address(0), "Invalid vault root provider address");
        vaultRootProvider = _vaultRootProvider;
    }

    function _setVaultRoot(uint256 _vaultRoot) internal virtual {
        require(msg.sender == vaultRootProvider, "Unauthorized: Only vault root provider can set the root");
        require(_vaultRoot != 0, InvalidVaultRoot());

        // Vault root can only be set once
        require(vaultRoot == 0, VaultRootAlreadySet());

        vaultRoot = _vaultRoot;

        emit VaultRootSet(_vaultRoot);
    }

    function setVaultRoot(uint256 _vaultRoot) external virtual;
}
