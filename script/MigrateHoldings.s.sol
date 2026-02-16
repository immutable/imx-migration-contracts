// Copyright Immutable Pty Ltd 2018 - 2025
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {IStarkExchangeMigration} from "../src/bridge/starkex/IStarkExchangeMigration.sol";

/**
 * @title MigrateHoldings
 * @notice Calls migrateHoldings() on the StarkExchangeMigration contract for a given phase.
 * @dev Reads token_phases config, aggregates amounts per token address for the specified phase,
 *      and invokes migrateHoldings(). Simulates by default; add --broadcast to send on-chain.
 *
 * Required env vars:
 *   - PHASES_FILE: Path to token_phases JSON file
 *   - PHASE: The phase number to migrate
 *   - BRIDGE_FEE: The bridge fee (in wei) to use for each token
 *   - MIGRATION_CONTRACT: Address of the StarkExchangeMigration contract
 *
 * Usage (simulate):
 *   PHASES_FILE=config/operate/sandbox/token_phases.json \
 *   PHASE=2 \
 *   BRIDGE_FEE=100000000000000 \
 *   MIGRATION_CONTRACT=0x... \
 *   forge script script/MigrateHoldings.s.sol --rpc-url $RPC_URL
 *
 * Usage (broadcast):
 *   PHASES_FILE=config/operate/sandbox/token_phases.json \
 *   PHASE=2 \
 *   BRIDGE_FEE=100000000000000 \
 *   MIGRATION_CONTRACT=0x... \
 *   forge script script/MigrateHoldings.s.sol --rpc-url $RPC_URL --broadcast
 */
contract MigrateHoldings is Script {
    /// @dev Reference to native ETH, matching StarkExchangeMigration.NATIVE_ETH
    address constant NATIVE_ETH = address(0xeee);

    address[] private aggTokens;
    uint256[] private aggAmounts;
    string[] private aggTickers;

    function setUp() external {}

    function run() external {
        uint256 phase = vm.envUint("PHASE");
        uint256 bridgeFee = vm.envUint("BRIDGE_FEE");
        string memory phasesFilePath = vm.envString("PHASES_FILE");
        address migrationContract = vm.envAddress("MIGRATION_CONTRACT");

        string memory json = vm.readFile(phasesFilePath);
        uint256 entryCount = _countJsonArrayElements(json);

        console.log("========================================");
        console.log("  migrateHoldings() ");
        console.log("========================================");
        console.log("");
        console.log("Phases file:    %s", phasesFilePath);
        console.log("Phase:          %d", phase);
        console.log("Bridge fee/tok: %s wei", vm.toString(bridgeFee));
        console.log("Target:         %s", vm.toString(migrationContract));
        console.log("");

        // Filter by phase, log each raw entry, and aggregate by token_address
        console.log("--- Raw entries for phase %d ---", phase);
        console.log("");
        uint256 rawCount = 0;
        for (uint256 i = 0; i < entryCount; i++) {
            string memory basePath = string(abi.encodePacked("$[", vm.toString(i), "]"));

            uint256 entryPhase = vm.parseJsonUint(json, string(abi.encodePacked(basePath, ".phase")));
            if (entryPhase != phase) continue;

            string memory tokenAddressStr =
                vm.parseJsonString(json, string(abi.encodePacked(basePath, ".token_address")));
            string memory ticker = vm.parseJsonString(json, string(abi.encodePacked(basePath, ".ticker_symbol")));
            uint256 amount = vm.parseJsonUint(json, string(abi.encodePacked(basePath, ".unquantised_sum")));

            address tokenAddr;
            if (_isEth(tokenAddressStr)) {
                tokenAddr = NATIVE_ETH;
            } else {
                tokenAddr = vm.parseAddress(tokenAddressStr);
            }

            console.log("  [%d] %s  %s", rawCount, ticker, vm.toString(tokenAddr));
            console.log("      amount: %s", vm.toString(amount));
            rawCount++;

            // Aggregate: find existing entry or create new one
            bool found = false;
            for (uint256 j = 0; j < aggTokens.length; j++) {
                if (aggTokens[j] == tokenAddr) {
                    aggAmounts[j] += amount;
                    found = true;
                    break;
                }
            }
            if (!found) {
                aggTokens.push(tokenAddr);
                aggAmounts.push(amount);
                aggTickers.push(ticker);
            }
        }

        uint256 numTokens = aggTokens.length;
        require(numTokens > 0, "No tokens found for the specified phase");

        uint256 totalMsgValue = bridgeFee * numTokens;

        // Build TokenMigrationDetails array and show aggregated results
        IStarkExchangeMigration.TokenMigrationDetails[] memory details =
            new IStarkExchangeMigration.TokenMigrationDetails[](numTokens);

        console.log("");
        console.log("--- Aggregated tokens (%d unique from %d entries) ---", numTokens, rawCount);
        console.log("");
        for (uint256 i = 0; i < numTokens; i++) {
            details[i] = IStarkExchangeMigration.TokenMigrationDetails({
                token: aggTokens[i], amount: aggAmounts[i], bridgeFee: bridgeFee
            });

            console.log("  [%d] %s", i, aggTickers[i]);
            console.log("      token:     %s", vm.toString(aggTokens[i]));
            console.log("      amount:    %s", vm.toString(aggAmounts[i]));
            console.log("      bridgeFee: %s", vm.toString(bridgeFee));
        }

        // Encode the full calldata
        bytes memory callData = abi.encodeCall(IStarkExchangeMigration.migrateHoldings, (details));

        // Transaction summary
        console.log("");
        console.log("=== Transaction to be sent ===");
        console.log("");
        console.log("  to:        %s", vm.toString(migrationContract));
        console.log("  function:  migrateHoldings(TokenMigrationDetails[])");
        console.log("  selector:  0x701f9fae");
        console.log("  msg.value: %s wei", vm.toString(totalMsgValue));
        console.log("             = %d tokens x %s fee per token", numTokens, vm.toString(bridgeFee));
        console.log("");
        console.log("  calldata (%d bytes):", callData.length);
        console.log("  %s", vm.toString(callData));
        console.log("");
        console.log("  calldata hash (keccak256):");
        console.log("  %s", vm.toString(keccak256(callData)));
        console.log("");
        console.log("========================================");

        // Execute the call (simulated unless --broadcast is passed)
        vm.startBroadcast();
        IStarkExchangeMigration(migrationContract).migrateHoldings{value: totalMsgValue}(details);
        vm.stopBroadcast();

        console.log("");
        console.log("migrateHoldings() executed successfully");
        console.log("========================================");
    }

    function _isEth(string memory tokenAddress) private pure returns (bool) {
        return keccak256(bytes(tokenAddress)) == keccak256(bytes("eth"));
    }

    /// @dev Count top-level objects in a JSON array.
    function _countJsonArrayElements(string memory json) private pure returns (uint256) {
        bytes memory jsonBytes = bytes(json);
        uint256 count = 0;
        uint256 depth = 0;
        bool inString = false;

        for (uint256 i = 0; i < jsonBytes.length; i++) {
            bytes1 c = jsonBytes[i];

            if (c == '"' && (i == 0 || jsonBytes[i - 1] != "\\")) {
                inString = !inString;
            }

            if (!inString) {
                if (c == "[") {
                    depth++;
                } else if (c == "]") {
                    depth--;
                } else if (c == "{" && depth == 1) {
                    count++;
                }
            }
        }

        return count;
    }
}
