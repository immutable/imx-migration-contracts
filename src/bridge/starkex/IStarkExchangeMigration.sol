// Copyright Immutable Pty Ltd 2018 - 2025
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

interface IStarkExchangeMigration {
    error ZeroBridgeFee();
    error ZeroAddress();
    error ZeroAmount();
    error InsufficientBalance();

    event VaultStateMigrationInitiated(uint256 indexed vaultRoot, address inititator);
    event ERC20HoldingMigrationInitiated(address indexed token, uint256 amount);
    event ETHHoldingMigrationInitiated(uint256 amount);

    event LogWithdrawalPerformed(
        uint256 ownerKey, uint256 assetType, uint256 nonQuantizedAmount, uint256 quantizedAmount, address recipient
    );

    error UnauthorizedMigrationInitiator();

    function migrateERC20Holdings(IERC20Metadata token, uint256 amount) external payable;
    function migrateETHHoldings(uint256 amount) external payable;
    function migrateVaultState() external payable;
}
