// Copyright Immutable Pty Ltd 2018 - 2025
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../src/verifiers/accounts/AccountProofVerifier.sol";
import "../src/verifiers/vaults/VaultEscapeProofVerifier.sol";
import "forge-std/Script.sol";
import "forge-std/console.sol";
import {VaultWithdrawalProcessor} from "../src/withdrawals/VaultWithdrawalProcessor.sol";
import {BridgedTokenMapping} from "../src/assets/BridgedTokenMapping.sol";
import {ProcessorAccessControl} from "@src/withdrawals/ProcessorAccessControl.sol";

contract DeployL2Contracts is Script {
    bool private allowRootOverride;
    address private vaultVerifier;
    address[63] private lookupTables;
    VaultWithdrawalProcessor private withdrawalProcessor;
    VaultWithdrawalProcessor.RoleOperators private operators;
    BridgedTokenMapping.TokenMapping[] private assetMappings;

    function setUp() external {
        string memory config = vm.readFile(vm.envString("DEPLOYMENT_CONFIG_FILE"));
        allowRootOverride = vm.parseJsonBool(config, "$.allow_root_override");

        vaultVerifier = vm.parseJsonAddress(config, "$.vault_verifier");

        operators = abi.decode(vm.parseJson(config, "$.operators"), (ProcessorAccessControl.RoleOperators));

        address[] memory _lookupTables = vm.parseJsonAddressArray(config, "$.lookup_tables");
        require(_lookupTables.length == 63, "Lookup tables should contain exactly 63 addresses");
        for (uint256 i = 0; i < _lookupTables.length; i++) {
            lookupTables[i] = _lookupTables[i];
        }

        BridgedTokenMapping.TokenMapping[] memory assetMappingsMem =
            abi.decode(vm.parseJson(config, "$.asset_mappings"), (BridgedTokenMapping.TokenMapping[]));
        for (uint256 i = 0; i < assetMappingsMem.length; i++) {
            assetMappings.push(assetMappingsMem[i]);
        }
        require(assetMappings.length > 0, "At least one asset mapping must be provided");
    }

    // NOTE: Make sure to use either --slow or -batch-size 1 when running this script for Tenderly to avoid out of order deployments of contracts and incorrect addresses.
    function run() external {
        // Deploy vault verifier if not provided
        vm.startBroadcast();
        if (vaultVerifier == address(0)) {
            vaultVerifier = address(new VaultEscapeProofVerifier(lookupTables));
        }

        withdrawalProcessor = new VaultWithdrawalProcessor(vaultVerifier, operators, allowRootOverride);
        withdrawalProcessor.registerTokenMappings(assetMappings);

        _logDeploymentDetails();
        vm.stopBroadcast();
    }

    function _logDeploymentDetails() private view {
        console.log("VaultWithdrawalProcessor: ", address(withdrawalProcessor));
        console.log("VaultEscapeProofVerifier: ", address(vaultVerifier));
    }
}
