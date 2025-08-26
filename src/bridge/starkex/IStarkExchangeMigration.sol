// Copyright Immutable Pty Ltd 2018 - 2025
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/**
 * @title IStarkExchangeMigration
 * @notice Defines the interface for migrating holdings from Immutable X to zkEVM
 */
interface IStarkExchangeMigration {
    struct TokenMigrationDetails {
        address token;
        uint256 amount;
        uint256 bridgeFee;
    }

    /// @notice Thrown when no assets are provided for migration
    error NoMigrationDetails();

    /// @notice Thrown when a zero address is provided
    error InvalidAddress();

    /// @notice Thrown when a zero is provided as amount to migrate
    error InvalidAmount();

    /// @notice Thrown if the bridge does not have sufficient funds of the token to perform the specified migration amount
    error AmountExceedsBalance();

    /// @notice Thrown when the bridge fee provided is insufficient to cover the cost of bridging the assets to zkEVM
    error InsufficientBridgeFee();

    /// @notice Thrown when the bridge fee provided exceeds the required amount
    error ExcessBridgeFeeProvided();

    /// @notice Thrown when an unauthorized account attempts to initiate migration process
    error UnauthorizedMigrationInitiator();

    /**
     * @notice Emitted when migration of ERC20 tokens is initiated
     * @param token The address of the ERC20 token being migrated
     * @param amount The amount of tokens being migrated
     * @param recipient The address receiving the migrated tokens
     * @param initiator The address that initiated the migration
     */
    event ERC20HoldingsMigration(
        address indexed token, uint256 amount, address indexed recipient, address indexed initiator
    );

    /**
     * @notice Emitted when ETH holdings migration is initiated
     * @param amount The amount of ETH being migrated
     * @param recipient The address receiving the migrated ETH
     * @param initiator The address that initiated the migration
     */
    event ETHHoldingsMigration(uint256 amount, address indexed recipient, address indexed initiator);

    /**
     * @notice Migrates the bridge's holdings of the specified assets and amounts to zkEVM, by depositing the funds to the zkEVM bridge contract.
     * @param assets The list of assets to migrate, each containing the token address and amount. ETH is represented by the address(0xeee)
     * @dev Requires a bridge fee to be sent with this transaction.
     */
    function migrateHoldings(TokenMigrationDetails[] calldata assets) external payable;

    /**
     * @notice Sends the latest vault root data stored in this contract to the configured withdrawal processor contract on zkEVM.
     * @dev Requires a bridge fee to be sent with the transaction
     */
    function migrateVaultRoot() external payable;
}
