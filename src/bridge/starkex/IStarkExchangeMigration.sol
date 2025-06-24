// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

interface IStarkExchangeMigration {
    error NoBridgeFee();
    error ZeroAddress();
    error ZeroAmount();
    error InsufficientBalance();

    event VaultStateMigrationInitiated(uint256 indexed vaultRoot, address inititator);
    event ERC20HoldingMigrationInitiated(address indexed token, uint256 amount);
    event ETHHoldingMigrationInitiated(uint256 amount);

    function migrateERC20Holdings(IERC20Metadata token, uint256 amount) external payable;
    function migrateETHHoldings(uint256 amount) external payable;
    function migrateVaultState() external payable;
}
