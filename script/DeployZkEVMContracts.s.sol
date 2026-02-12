// Copyright Immutable Pty Ltd 2018 - 2025
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {VaultEscapeProofVerifier} from "../src/verifiers/vaults/VaultEscapeProofVerifier.sol";
import {VaultRootReceiverAdapter} from "../src/bridge/messaging/VaultRootReceiverAdapter.sol";
import {VaultWithdrawalProcessor} from "../src/withdrawals/VaultWithdrawalProcessor.sol";
import {ProcessorAccessControl} from "../src/withdrawals/ProcessorAccessControl.sol";

/**
 * @title DeployZkEVMContracts
 * @notice Deploys the migration contracts on Immutable zkEVM:
 *         1. VaultEscapeProofVerifier
 *         2. VaultRootReceiverAdapter
 *         3. VaultWithdrawalProcessor
 *
 * @dev Deployment ordering matters: VaultWithdrawalProcessor depends on the addresses of
 *      VaultEscapeProofVerifier (as its proof verifier) and VaultRootReceiverAdapter (as its
 *      vault root provider). These are wired automatically within the script.
 *
 * @dev For each contract, if its `address` field in the config is non-zero, the script skips
 *      deployment and uses the provided address instead. This allows partial re-runs.
 *
 * @dev After deployment, this script writes an updated config file with the deployed addresses.
 *      Token mapping registration is handled separately by RegisterTokenMappings.s.sol.
 *
 *      Required env vars:
 *        - DEPLOYMENT_CONFIG_FILE: Path to input config (see config/sample_zkevm_config.json)
 *        - DEPLOYMENT_OUTPUT_FILE: Path to write output config with deployed addresses
 */
contract DeployZkEVMContracts is Script {
    // VaultEscapeProofVerifier
    address private vaultVerifier;
    address[63] private lookupTables;

    // VaultRootReceiverAdapter
    address private receiverAdapter;
    address private receiverAdapterOwner;
    address private receiverAdapterAxelarGateway;

    // VaultWithdrawalProcessor
    address private withdrawalProcessor;
    bool private allowRootOverride;
    ProcessorAccessControl.RoleOperators private operators;

    string private configFilePath;
    string private outputFilePath;

    function setUp() external {
        configFilePath = vm.envString("DEPLOYMENT_CONFIG_FILE");
        outputFilePath = vm.envString("DEPLOYMENT_OUTPUT_FILE");

        string memory config = vm.readFile(configFilePath);

        // --- VaultEscapeProofVerifier ---
        vaultVerifier = vm.parseJsonAddress(config, "$.vault_escape_proof_verifier.address");
        address[] memory _lookupTables =
            vm.parseJsonAddressArray(config, "$.vault_escape_proof_verifier.lookup_tables");
        require(_lookupTables.length == 63, "Lookup tables must contain exactly 63 addresses");
        for (uint256 i = 0; i < _lookupTables.length; i++) {
            lookupTables[i] = _lookupTables[i];
        }

        // --- VaultRootReceiverAdapter ---
        receiverAdapter = vm.parseJsonAddress(config, "$.vault_root_receiver_adapter.address");
        receiverAdapterOwner = vm.parseJsonAddress(config, "$.vault_root_receiver_adapter.owner");
        receiverAdapterAxelarGateway = vm.parseJsonAddress(config, "$.vault_root_receiver_adapter.axelar_gateway");

        // --- VaultWithdrawalProcessor ---
        withdrawalProcessor = vm.parseJsonAddress(config, "$.vault_withdrawal_processor.address");
        allowRootOverride = vm.parseJsonBool(config, "$.vault_withdrawal_processor.allow_root_override");

        // Parse operators individually to avoid alphabetical key ordering issues with abi.decode
        operators.accountRootProvider =
            vm.parseJsonAddress(config, "$.vault_withdrawal_processor.operators.accountRootProvider");
        operators.tokenMappingManager =
            vm.parseJsonAddress(config, "$.vault_withdrawal_processor.operators.tokenMappingManager");
        operators.disburser = vm.parseJsonAddress(config, "$.vault_withdrawal_processor.operators.disburser");
        operators.pauser = vm.parseJsonAddress(config, "$.vault_withdrawal_processor.operators.pauser");
        operators.unpauser = vm.parseJsonAddress(config, "$.vault_withdrawal_processor.operators.unpauser");
        operators.defaultAdmin = vm.parseJsonAddress(config, "$.vault_withdrawal_processor.operators.defaultAdmin");
    }

    /// @notice Deploys all zkEVM contracts in dependency order.
    /// @dev Use --slow or --batch-size 1 when running on Tenderly to avoid out-of-order deployments.
    function run() external {
        _validateConfig();

        vm.startBroadcast();

        // 1. Deploy VaultEscapeProofVerifier (if not already deployed)
        if (vaultVerifier == address(0)) {
            vaultVerifier = address(new VaultEscapeProofVerifier(lookupTables));
            console.log("Deployed VaultEscapeProofVerifier:", vaultVerifier);
        } else {
            console.log("Using existing VaultEscapeProofVerifier:", vaultVerifier);
        }

        // 2. Deploy VaultRootReceiverAdapter (if not already deployed)
        if (receiverAdapter == address(0)) {
            receiverAdapter = address(new VaultRootReceiverAdapter(receiverAdapterOwner, receiverAdapterAxelarGateway));
            console.log("Deployed VaultRootReceiverAdapter:", receiverAdapter);
        } else {
            console.log("Using existing VaultRootReceiverAdapter:", receiverAdapter);
        }

        // 3. Deploy VaultWithdrawalProcessor (if not already deployed)
        //    - _vaultProofVerifier = VaultEscapeProofVerifier from step 1
        //    - _vaultRootProvider  = VaultRootReceiverAdapter from step 2
        if (withdrawalProcessor == address(0)) {
            withdrawalProcessor =
                address(new VaultWithdrawalProcessor(vaultVerifier, receiverAdapter, operators, allowRootOverride));
            console.log("Deployed VaultWithdrawalProcessor:", withdrawalProcessor);
        } else {
            console.log("Using existing VaultWithdrawalProcessor:", withdrawalProcessor);
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
        // VaultEscapeProofVerifier: validate lookup tables if deploying
        if (vaultVerifier == address(0)) {
            for (uint256 i = 0; i < lookupTables.length; i++) {
                require(lookupTables[i] != address(0), string.concat("Lookup table at index ", vm.toString(i), " is zero address"));
            }
        }

        // VaultRootReceiverAdapter: validate owner and gateway if deploying
        if (receiverAdapter == address(0)) {
            require(receiverAdapterOwner != address(0), "vault_root_receiver_adapter.owner is zero address");
            require(receiverAdapterAxelarGateway != address(0), "vault_root_receiver_adapter.axelar_gateway is zero address");
        }

        // VaultWithdrawalProcessor: validate operators if deploying
        if (withdrawalProcessor == address(0)) {
            require(operators.accountRootProvider != address(0), "operators.accountRootProvider is zero address");
            require(operators.tokenMappingManager != address(0), "operators.tokenMappingManager is zero address");
            require(operators.disburser != address(0), "operators.disburser is zero address");
            require(operators.pauser != address(0), "operators.pauser is zero address");
            require(operators.unpauser != address(0), "operators.unpauser is zero address");
            require(operators.defaultAdmin != address(0), "operators.defaultAdmin is zero address");
        }
    }

    /**
     * @dev Writes an updated config file with the deployed contract addresses.
     *      Copies the original config and updates the address fields.
     */
    function _writeDeploymentOutput() private {
        string memory config = vm.readFile(configFilePath);
        vm.writeFile(outputFilePath, config);

        vm.writeJson(vm.toString(vaultVerifier), outputFilePath, ".vault_escape_proof_verifier.address");
        vm.writeJson(vm.toString(receiverAdapter), outputFilePath, ".vault_root_receiver_adapter.address");
        vm.writeJson(vm.toString(withdrawalProcessor), outputFilePath, ".vault_withdrawal_processor.address");

        console.log("Deployment output written to:", outputFilePath);
    }

    function _logSummary() private view {
        console.log("--- zkEVM Deployment Summary ---");
        console.log("VaultEscapeProofVerifier:", vaultVerifier);
        console.log("VaultRootReceiverAdapter:", receiverAdapter);
        console.log("VaultWithdrawalProcessor:", withdrawalProcessor);
    }
}
