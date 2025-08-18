// Copyright Immutable Pty Ltd 2018 - 2025
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

abstract contract ProcessorAccessControl is AccessControl, Pausable {
    error InvalidOperatorAddress();

    /// @notice Role for pausing the contract
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    /// @notice Role for unpausing the contract
    bytes32 public constant UNPAUSER_ROLE = keccak256("UNPAUSER_ROLE");
    /// @notice Role for processing withdrawals
    bytes32 public constant DISBURSER_ROLE = keccak256("DISBURSER_ROLE");
    /// @notice Role for setting the account root
    bytes32 public constant ACCOUNT_ROOT_PROVIDER_ROLE = keccak256("ACCOUNT_ROOT_PROVIDER_ROLE");
    /// @notice Role for setting the vault root
    bytes32 public constant VAULT_ROOT_PROVIDER_ROLE = keccak256("VAULT_ROOT_PROVIDER_ROLE");
    /// @notice Role for managing token mappings
    bytes32 public constant TOKEN_MAPPING_MANAGER = keccak256("TOKEN_MAPPING_MANAGER");

    struct Operators {
        address accountRootProvider;
        address vaultRootProvider;
        address tokenMappingManager;
        address disburser;
        address pauser;
        address unpauser;
        address defaultAdmin;
    }

    /**
     * @notice Pauses the contract, preventing withdrawals from being processed
     * @dev Only accounts with PAUSER_ROLE can call this function
     */
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /**
     * @notice Unpauses the contract, allowing withdrawals to be processed again
     * @dev Only accounts with UNPAUSER_ROLE can call this function
     */
    function unpause() external onlyRole(UNPAUSER_ROLE) {
        _unpause();
    }

    function _validateOperators(Operators memory operators) internal pure {
        require(operators.accountRootProvider != address(0), InvalidOperatorAddress());
        require(operators.vaultRootProvider != address(0), InvalidOperatorAddress());
        require(operators.tokenMappingManager != address(0), InvalidOperatorAddress());
        require(operators.disburser != address(0), InvalidOperatorAddress());
        require(operators.pauser != address(0), InvalidOperatorAddress());
        require(operators.unpauser != address(0), InvalidOperatorAddress());
        require(operators.defaultAdmin != address(0), InvalidOperatorAddress());
    }

    function _grantOperatorRoles(Operators memory operators) internal {
        _grantRole(ACCOUNT_ROOT_PROVIDER_ROLE, operators.accountRootProvider);
        _grantRole(VAULT_ROOT_PROVIDER_ROLE, operators.vaultRootProvider);
        _grantRole(TOKEN_MAPPING_MANAGER, operators.tokenMappingManager);
        _grantRole(DISBURSER_ROLE, operators.disburser);
        _grantRole(PAUSER_ROLE, operators.pauser);
        _grantRole(UNPAUSER_ROLE, operators.unpauser);
        _grantRole(DEFAULT_ADMIN_ROLE, operators.defaultAdmin);
    }
}
