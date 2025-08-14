// Copyright Immutable Pty Ltd 2018 - 2025
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/**
 * @title IStarkExchangeMigration
 * @notice Interface for migrating assets and vault state from Immutable X to zkEVM
 * @dev This interface defines the functions for migrating ERC20 holdings, ETH holdings,
 *      and vault state from the Immutable X system to the zkEVM chain
 */
interface IStarkExchangeMigration {
    /// @notice Thrown when no bridge fee is provided for the migration
    error ZeroBridgeFee();
    /// @notice Thrown when a zero address is provided where a valid address is required
    error ZeroAddress();
    /// @notice Thrown when attempting to migrate zero amount
    error ZeroAmount();
    /// @notice Thrown when there are insufficient funds for the migration
    error InsufficientBalance();
    /// @notice Thrown when an unauthorized account attempts to initiate migration
    error UnauthorizedMigrationInitiator();

    /**
     * @notice Emitted when vault state migration is initiated
     * @param vaultRoot The vault root hash being migrated
     * @param inititator The address that initiated the migration
     */
    event VaultStateMigrationInitiated(uint256 indexed vaultRoot, address inititator);

    /**
     * @notice Emitted when ERC20 holdings migration is initiated
     * @param token The address of the ERC20 token being migrated
     * @param amount The amount of tokens being migrated
     */
    event ERC20HoldingMigrationInitiated(address indexed token, uint256 amount);

    /**
     * @notice Emitted when ETH holdings migration is initiated
     * @param amount The amount of ETH being migrated
     */
    event ETHHoldingMigrationInitiated(uint256 amount);

    /**
     * @notice Emitted when a withdrawal is performed
     * @param ownerKey The Stark key of the vault owner
     * @param assetType The type of asset being withdrawn
     * @param nonQuantizedAmount The non-quantized amount withdrawn
     * @param quantizedAmount The quantized amount withdrawn
     * @param recipient The address receiving the withdrawn funds
     */
    event LogWithdrawalPerformed(
        uint256 ownerKey, uint256 assetType, uint256 nonQuantizedAmount, uint256 quantizedAmount, address recipient
    );

    /**
     * @notice Migrates ERC20 token holdings from Immutable X to zkEVM
     * @param token The ERC20 token to migrate
     * @param amount The amount of tokens to migrate
     * @dev Requires a bridge fee to be sent with the transaction
     */
    function migrateERC20Holdings(IERC20Metadata token, uint256 amount) external payable;

    /**
     * @notice Migrates ETH holdings from Immutable X to zkEVM
     * @param amount The amount of ETH to migrate
     * @dev Requires a bridge fee to be sent with the transaction
     */
    function migrateETHHoldings(uint256 amount) external payable;

    /**
     * @notice Migrates the vault state from Immutable X to zkEVM
     * @dev Requires a bridge fee to be sent with the transaction
     */
    function migrateVaultState() external payable;
}
