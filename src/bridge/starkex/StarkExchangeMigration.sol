// Copyright Immutable Pty Ltd 2018 - 2025
// SPDX-License-Identifier: Apache-2.0.
pragma solidity ^0.8.27;

import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {IRootERC20Bridge} from "../zkEVM/IRootERC20Bridge.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IStarkExchangeMigration} from "./IStarkExchangeMigration.sol";
import {VaultRootSenderAdapter} from "../messaging/VaultRootSenderAdapter.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {LegacyStarkExchangeBridge} from "./LegacyStarkExchangeBridge.sol";

/**
 * @title StarkExchangeMigration
 * @notice This contract facilitates the migration of ETH and ERC-20 assets held by the legacy Immutable X bridge to Immutable zkEVM.
 * @dev The contract performs the following functions, in service of the migration:
 *      1. Sends the proven vault root hash stored in this contract, to a designated contract on Immutable zkEVM. This root is used by the destination contract to facilitate disbursement of funds to the intended recipients.
 *      2. Enables an authorised entity to migrate ERC-20 tokens and ETH held by the StarkExchange bridge to Immutable zkEVM.
 *      3. Enables users who had already initiated a withdrawal from Immutable X, prior to this contract upgrade taking effect, to finalise their pending withdrawal.
 */
contract StarkExchangeMigration is IStarkExchangeMigration, LegacyStarkExchangeBridge, Initializable, ReentrancyGuard {
    /**
     * @notice Restrict access only to the migration manager
     */
    modifier onlyMigrationManager() {
        require(msg.sender == migrationManager, UnauthorizedMigrationInitiator());
        _;
    }

    /// @dev Reference to native ETH, based on the value used to represent ETH on the zkEVM bridge.
    address public constant NATIVE_ETH = address(0xeee);

    /**
     * @notice Initializes the contract with migration configuration
     * @param data Encoded initialization data containing addresses
     * @dev Can only be called once due to initializer modifier
     * @dev Initializer is called by the proxy during the `upgradeTo()` function call which can only be called by Governance
     * @dev The hash of the data used to initialize the contract is pre-committed to when the contract upgrade is proposed in the Proxy's timelock upgrade.
     */
    function initialize(bytes calldata data) external initializer {
        (
            address _migrationManager,
            address _zkEVMBridge,
            address _rootSenderAdapter,
            address _zkEVMWithdrawalProcessor
        ) = abi.decode(data, (address, address, address, address));

        require(_migrationManager != address(0), InvalidAddress());
        require(_zkEVMBridge != address(0), InvalidAddress());
        require(_rootSenderAdapter != address(0), InvalidAddress());
        require(_zkEVMWithdrawalProcessor != address(0), InvalidAddress());

        migrationManager = _migrationManager;
        zkEVMBridge = _zkEVMBridge;
        zkEVMWithdrawalProcessor = _zkEVMWithdrawalProcessor;
        rootSenderAdapter = VaultRootSenderAdapter(_rootSenderAdapter);
    }

    /**
     * @inheritdoc IStarkExchangeMigration
     * @dev Only the migration manager can call this function
     * @dev Assumes that the caller is the gas refund receiver, and can receive native asset
     */
    function migrateVaultRoot() external payable override nonReentrant onlyMigrationManager {
        rootSenderAdapter.sendVaultRoot{value: msg.value}(vaultRoot, msg.sender);
    }

    /**
     * @inheritdoc IStarkExchangeMigration
     * @dev Only the migration manager can call this function
     * @dev Assumes that the caller is the gas refund receiver, and can receive native asset
     */
    function migrateHoldings(TokenMigrationDetails[] calldata tokens)
        external
        payable
        override
        nonReentrant
        onlyMigrationManager
    {
        require(tokens.length > 0, NoMigrationDetails());

        uint256 totalFees = 0;
        for (uint256 i = 0; i < tokens.length; i++) {
            (address token, uint256 amount, uint256 fee) = (tokens[i].token, tokens[i].amount, tokens[i].bridgeFee);

            totalFees += fee;
            require(totalFees <= msg.value, InsufficientBridgeFee());

            if (token == NATIVE_ETH) {
                _depositETHToZKEVMBridge(amount, fee);
                emit ETHHoldingsMigration(amount, zkEVMWithdrawalProcessor, msg.sender);
            } else {
                _depositERC20ToZKEVMBridge(IERC20Metadata(token), amount, fee);
                emit ERC20HoldingsMigration(token, amount, zkEVMWithdrawalProcessor, msg.sender);
            }
        }
        require(totalFees == msg.value, ExcessBridgeFeeProvided());
    }
    /**
     * @notice Internal function to deposit ERC20 tokens to the zkEVM bridge
     * @param token The ERC20 token to deposit
     * @param amount The amount of tokens to deposit
     * @dev Validates inputs and transfers tokens to the zkEVM bridge
     */

    function _depositERC20ToZKEVMBridge(IERC20Metadata token, uint256 amount, uint256 bridgeFee) private {
        require(address(token) != address(0), InvalidAddress());
        require(amount > 0, InvalidAmount());

        uint256 balance = token.balanceOf(address(this));
        require(balance >= amount, AmountExceedsBalance());
        // Transfer the specified amount of tokens to the recipient
        token.approve(zkEVMBridge, amount);
        IRootERC20Bridge(zkEVMBridge).depositTo{value: bridgeFee}(token, zkEVMWithdrawalProcessor, amount);
    }

    /**
     * @notice Internal function to deposit ETH to the zkEVM bridge
     * @param amount The amount of ETH to deposit
     * @dev Validates inputs and transfers ETH to the zkEVM bridge
     */
    function _depositETHToZKEVMBridge(uint256 amount, uint256 bridgeFee) private {
        require(amount > 0, InvalidAmount());

        uint256 balance = address(this).balance;
        require(balance >= amount + bridgeFee, AmountExceedsBalance());

        IRootERC20Bridge(zkEVMBridge).depositToETH{value: amount + bridgeFee}(zkEVMWithdrawalProcessor, amount);
    }
}
