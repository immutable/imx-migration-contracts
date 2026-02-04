// Copyright Immutable Pty Ltd 2018 - 2025
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../src/verifiers/vaults/VaultEscapeProofVerifier.sol";
import "forge-std/Script.sol";
import "forge-std/console.sol";
import {VaultWithdrawalProcessor} from "../src/withdrawals/VaultWithdrawalProcessor.sol";
import {ProcessorAccessControl} from "@src/withdrawals/ProcessorAccessControl.sol";

/**
 * @title DeployL2Contracts
 * @notice Deploys the VaultWithdrawalProcessor and optionally the VaultEscapeProofVerifier.
 * @dev Token mapping registration is handled separately by RegisterTokenMappings.s.sol
 *      since it will typically be executed by a different account (TOKEN_MAPPING_MANAGER).
 *
 * @dev After deployment, this script writes an updated config file with the deployed addresses.
 *      Required env vars:
 *        - DEPLOYMENT_CONFIG_FILE: Path to input config
 *        - DEPLOYMENT_OUTPUT_FILE: Path to write output config with deployed addresses
 */
contract DeployL2Contracts is Script {
    bool private allowRootOverride;
    address private vaultVerifier;
    address[63] private lookupTables;
    VaultWithdrawalProcessor private withdrawalProcessor;
    VaultWithdrawalProcessor.RoleOperators private operators;

    string private configFilePath;
    string private outputFilePath;

    function setUp() external {
        configFilePath = vm.envString("DEPLOYMENT_CONFIG_FILE");
        outputFilePath = vm.envString("DEPLOYMENT_OUTPUT_FILE");

        string memory config = vm.readFile(configFilePath);
        allowRootOverride = vm.parseJsonBool(config, "$.allow_root_override");

        vaultVerifier = vm.parseJsonAddress(config, "$.vault_verifier");

        operators = abi.decode(vm.parseJson(config, "$.operators"), (ProcessorAccessControl.RoleOperators));

        address[] memory _lookupTables = vm.parseJsonAddressArray(config, "$.lookup_tables");
        require(_lookupTables.length == 63, "Lookup tables should contain exactly 63 addresses");
        for (uint256 i = 0; i < _lookupTables.length; i++) {
            lookupTables[i] = _lookupTables[i];
        }
    }

    // NOTE: Make sure to use either --slow or -batch-size 1 when running this script for Tenderly to avoid out of order deployments of contracts and incorrect addresses.
    function run() external {
        vm.startBroadcast();

        // Deploy vault verifier if not provided
        if (vaultVerifier == address(0)) {
            vaultVerifier = address(new VaultEscapeProofVerifier(lookupTables));
        }

        withdrawalProcessor = new VaultWithdrawalProcessor(vaultVerifier, operators, allowRootOverride);

        vm.stopBroadcast();

        _writeDeploymentOutput();
        _logDeploymentDetails();
    }

    /**
     * @dev Writes an updated config file with the deployed contract addresses.
     *      This output can be used directly as input for RegisterTokenMappings.s.sol
     */
    function _writeDeploymentOutput() private {
        // Copy the original config to output file
        string memory config = vm.readFile(configFilePath);
        vm.writeFile(outputFilePath, config);

        // Update with deployed addresses
        vm.writeJson(vm.toString(vaultVerifier), outputFilePath, ".vault_verifier");
        vm.writeJson(vm.toString(address(withdrawalProcessor)), outputFilePath, ".withdrawal_processor");

        console.log("Deployment output written to: ", outputFilePath);
    }

    function _logDeploymentDetails() private view {
        console.log("VaultWithdrawalProcessor: ", address(withdrawalProcessor));
        console.log("VaultEscapeProofVerifier: ", address(vaultVerifier));
    }
}
