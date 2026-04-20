// Copyright Immutable Pty Ltd 2018 - 2025
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {VaultRootSenderAdapter} from "../src/bridge/messaging/VaultRootSenderAdapter.sol";
import {StarkExchangeMigration} from "../src/bridge/starkex/StarkExchangeMigration.sol";
import {StarkExchangeMigrationV2} from "../src/bridge/starkex/StarkExchangeMigrationV2.sol";

/**
 * @title DeployEthContracts
 * @notice Deploys the migration contracts on Ethereum:
 *         1. VaultRootSenderAdapter
 *         2. StarkExchangeMigration implementation (version selected via config)
 *
 * @dev The StarkExchangeMigration is deployed as an implementation contract only.
 *      The existing StarkEx bridge proxy on-chain will be upgraded to point to this
 *      implementation separately (e.g., via governance), at which point `initialize`
 *      will be called with the appropriate parameters.
 *
 * @dev This script should be run AFTER DeployZkEVMContracts.s.sol, since the
 *      VaultRootSenderAdapter requires the VaultRootReceiverAdapter address from zkEVM.
 *
 * @dev After deployment, this script writes an updated config file with the deployed addresses.
 *
 *      Required env vars:
 *        - DEPLOYMENT_CONFIG_FILE: Path to input config (see config/sample_eth_config.json)
 *        - DEPLOYMENT_OUTPUT_FILE: Path to write output config with deployed addresses
 */
contract DeployEthContracts is Script {
    // VaultRootSenderAdapter
    address private senderAdapter;
    address private vaultRootSender;
    string private rootReceiver;
    string private rootReceiverChain;
    address private axelarGasService;
    address private axelarGateway;

    // StarkExchangeMigration implementation (version 1 or 2, selected via config)
    address private migrationImpl;
    uint256 private migrationVersion;

    string private configFilePath;
    string private outputFilePath;

    function setUp() external {
        configFilePath = vm.envString("DEPLOYMENT_CONFIG_FILE");
        outputFilePath = vm.envString("DEPLOYMENT_OUTPUT_FILE");

        string memory config = vm.readFile(configFilePath);

        // --- VaultRootSenderAdapter ---
        senderAdapter = vm.parseJsonAddress(config, "$.vault_root_sender_adapter.address");
        vaultRootSender = vm.parseJsonAddress(config, "$.vault_root_sender_adapter.vault_root_sender");
        rootReceiverChain = vm.parseJsonString(config, "$.vault_root_sender_adapter.root_receiver_chain");
        axelarGasService = vm.parseJsonAddress(config, "$.vault_root_sender_adapter.axelar_gas_service");
        axelarGateway = vm.parseJsonAddress(config, "$.vault_root_sender_adapter.axelar_gateway");

        // root_receiver is the VaultRootReceiverAdapter address on zkEVM, stored as a string
        // since Axelar uses string addresses for cross-chain messaging
        address rootReceiverAddr = vm.parseJsonAddress(config, "$.vault_root_sender_adapter.root_receiver");
        rootReceiver = vm.toString(rootReceiverAddr);

        // --- StarkExchangeMigration ---
        migrationImpl = vm.parseJsonAddress(config, "$.stark_exchange_migration.implementation_address");
        migrationVersion = vm.parseJsonUint(config, "$.stark_exchange_migration.version");
    }

    /// @notice Deploys the Ethereum contracts.
    /// @dev Use --slow or --batch-size 1 when running on Tenderly to avoid out-of-order deployments.
    function run() external {
        _validateConfig();

        vm.startBroadcast();

        // 1. Deploy VaultRootSenderAdapter (if not already deployed)
        if (senderAdapter == address(0)) {
            senderAdapter = address(
                new VaultRootSenderAdapter(
                    vaultRootSender, rootReceiver, rootReceiverChain, axelarGasService, axelarGateway
                )
            );
            console.log("Deployed VaultRootSenderAdapter:", senderAdapter);
        } else {
            console.log("Using existing VaultRootSenderAdapter:", senderAdapter);
        }

        // 2. Deploy StarkExchangeMigration implementation (if not already deployed).
        //    The version is selected via stark_exchange_migration.version in the config.
        //    The constructor only calls _disableInitializers(). No proxy is deployed here.
        //    The existing StarkEx bridge proxy will be upgraded separately via governance.
        if (migrationImpl == address(0)) {
            if (migrationVersion == 1) {
                migrationImpl = address(new StarkExchangeMigration());
            } else {
                migrationImpl = address(new StarkExchangeMigrationV2());
            }
            console.log("Deployed StarkExchangeMigration v%d implementation:", migrationVersion, migrationImpl);
        } else {
            console.log("Using existing StarkExchangeMigration v%d implementation:", migrationVersion, migrationImpl);
        }

        vm.stopBroadcast();

        _writeDeploymentOutput();
        _logSummary();
    }

    /**
     * @dev Validates that all required config addresses are non-zero for contracts being deployed.
     *      Only checks constructor params for contracts where address == 0 (i.e., will be deployed).
     */
    function _validateConfig() private view {
        // VaultRootSenderAdapter: validate all constructor params if deploying
        if (senderAdapter == address(0)) {
            require(vaultRootSender != address(0), "vault_root_sender_adapter.vault_root_sender is zero address");
            require(bytes(rootReceiver).length > 0, "vault_root_sender_adapter.root_receiver is empty");
            require(bytes(rootReceiverChain).length > 0, "vault_root_sender_adapter.root_receiver_chain is empty");
            require(axelarGasService != address(0), "vault_root_sender_adapter.axelar_gas_service is zero address");
            require(axelarGateway != address(0), "vault_root_sender_adapter.axelar_gateway is zero address");
        }

        // StarkExchangeMigration: validate version selector
        require(migrationVersion == 1 || migrationVersion == 2, "stark_exchange_migration.version must be 1 or 2");
    }

    /**
     * @dev Writes an updated config file with the deployed contract addresses.
     *      Copies the original config and updates the address fields.
     */
    function _writeDeploymentOutput() private {
        string memory config = vm.readFile(configFilePath);
        vm.writeFile(outputFilePath, config);

        vm.writeJson(vm.toString(senderAdapter), outputFilePath, ".vault_root_sender_adapter.address");
        vm.writeJson(vm.toString(migrationImpl), outputFilePath, ".stark_exchange_migration.implementation_address");

        console.log("Deployment output written to:", outputFilePath);
    }

    function _logSummary() private view {
        console.log("--- Ethereum Deployment Summary ---");
        console.log("VaultRootSenderAdapter:", senderAdapter);
        console.log("StarkExchangeMigration v%d (impl):", migrationVersion, migrationImpl);
    }
}
