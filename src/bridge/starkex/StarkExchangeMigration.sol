// SPDX-License-Identifier: Apache-2.0.
pragma solidity ^0.8.27;

import {MainStorage} from "./MainStorage.sol";
import "forge-std/console.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {IRootERC20Bridge} from "../zkEVM/IRootERC20Bridge.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IStarkExchangeMigration} from "./IStarkExchangeMigration.sol";
import {VaultRootSender} from "../messaging/VaultRootSender.sol";

/**
 * @title StarkExchangeMigration
 * @notice This contract is used to initiate the migration of funds and key vault state information for Immutable X to Immutable zkEVM.
 * @dev The contract performs the following functions:
 *      - Enables communicating the vault root to Immutable zkEVM through Axelar GMP.
 *      - Enables an authorised entity to transfer ERC20 tokens and ETH from the contract the Immutable zkEVM bridge.
 */
contract StarkExchangeMigration is MainStorage, Initializable, IStarkExchangeMigration {
    string public constant VERSION = "IMX-Migration-1.0.0";
    address public constant NATIVE_ETH = address(0xeee);

    modifier onlyMigrationManager() {
        require(msg.sender == migrationInitiator, "NOT_MIGRATION_MANAGER");
        _;
    }

    function initialize(bytes calldata data) external initializer {
        (address _migrationManager, address _zkEVMBridge, address _vaultRootSender, address _l2VaultProcessor) =
            abi.decode(data, (address, address, address, address));
        require(_migrationManager != address(0), ZeroAddress());
        require(_zkEVMBridge != address(0), ZeroAddress());
        require(_vaultRootSender != address(0), ZeroAddress());
        require(_l2VaultProcessor != address(0), ZeroAddress());
        migrationInitiator = _migrationManager;
        zkEVMBridge = _zkEVMBridge;
        zkEVMVaultProcessor = _l2VaultProcessor;
        vaultRootSender = VaultRootSender(_vaultRootSender);
    }

    function isFrozen() external pure returns (bool) {
        return false;
    }

    function migrateVaultState() external payable override onlyMigrationManager {
        require(msg.value > 0, NoBridgeFee());
        //TODO: Consider externalising gas refund receipient
        vaultRootSender.sendVaultRoot{value: msg.value}(vaultRoot, msg.sender);
        emit VaultStateMigrationInitiated(vaultRoot, msg.sender);
    }

    function migrateERC20Holdings(IERC20Metadata token, uint256 amount)
        external
        payable
        override
        onlyMigrationManager
    {
        _depositERC20ToZKEVMBridge(token, amount);
        emit ERC20HoldingMigrationInitiated(address(token), amount);
    }

    function migrateETHHoldings(uint256 amount) external payable override onlyMigrationManager {
        _depositETHToZKEVMBridge(amount);
        emit ETHHoldingMigrationInitiated(amount);
    }

    function _depositERC20ToZKEVMBridge(IERC20Metadata token, uint256 amount) private {
        require(address(token) != address(0), ZeroAddress());
        require(amount > 0, ZeroAmount());
        require(msg.value > 0, NoBridgeFee());

        uint256 balance = token.balanceOf(address(this));
        require(balance >= amount, InsufficientBalance());
        // Transfer the specified amount of tokens to the recipient
        token.approve(zkEVMBridge, amount);
        IRootERC20Bridge(zkEVMBridge).depositTo{value: msg.value}(token, zkEVMVaultProcessor, amount);
    }

    function _depositETHToZKEVMBridge(uint256 amount) private {
        require(amount > 0, ZeroAmount());
        require(msg.value > 0, NoBridgeFee());

        uint256 balance = address(this).balance;
        require(balance >= amount, InsufficientBalance());

        IRootERC20Bridge(zkEVMBridge).depositToETH{value: amount + msg.value}(zkEVMVaultProcessor, amount);
    }
}
