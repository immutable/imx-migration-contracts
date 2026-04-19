// Copyright Immutable Pty Ltd 2018 - 2025
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {VaultWithdrawalProcessor} from "../src/withdrawals/VaultWithdrawalProcessor.sol";
import {BridgedTokenMapping} from "../src/assets/BridgedTokenMapping.sol";

/**
 * @title RegisterTokenMappings
 * @notice Registers token mappings on an existing VaultWithdrawalProcessor.
 * @dev This script is separate from deployment since token registration is typically
 *      executed by a different account (TOKEN_MAPPING_MANAGER role).
 *
 * Required env vars:
 *   - DEPLOYMENT_CONFIG_FILE: Path to input config with withdrawal_processor and asset_mappings
 */
contract RegisterTokenMappings is Script {
    VaultWithdrawalProcessor private withdrawalProcessor;
    BridgedTokenMapping.TokenMapping[] private assetMappings;

    function setUp() external {
        string memory config = vm.readFile(vm.envString("DEPLOYMENT_CONFIG_FILE"));

        address processorAddress = vm.parseJsonAddress(config, "$.withdrawal_processor");
        require(processorAddress != address(0), "Withdrawal processor address must be provided");
        withdrawalProcessor = VaultWithdrawalProcessor(payable(processorAddress));

        BridgedTokenMapping.TokenMapping[] memory assetMappingsMem =
            abi.decode(vm.parseJson(config, "$.asset_mappings"), (BridgedTokenMapping.TokenMapping[]));
        for (uint256 i = 0; i < assetMappingsMem.length; i++) {
            assetMappings.push(assetMappingsMem[i]);
        }
        require(assetMappings.length > 0, "At least one asset mapping must be provided");
    }

    function run() external {
        console.log(
            "Registering %d token mappings on processor: %s", assetMappings.length, address(withdrawalProcessor)
        );

        vm.startBroadcast();
        withdrawalProcessor.registerTokenMappings(assetMappings);
        vm.stopBroadcast();

        console.log("Successfully registered %d token mappings", assetMappings.length);
    }
}
