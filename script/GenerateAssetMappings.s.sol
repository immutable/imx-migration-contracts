// Copyright Immutable Pty Ltd 2018 - 2025
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {BridgedTokenMapping} from "../src/assets/BridgedTokenMapping.sol";

/**
 * @title GenerateAssetMappings
 * @notice Generates asset_mappings config by reading tokens and querying a bridge contract.
 * @dev This script reads tokens from a JSON file, queries rootTokenToChildToken() on a bridge
 *      contract to get zkEVM addresses, and updates the asset_mappings in the config file in place.
 *
 * Required env vars:
 *   - TOKENS_FILE: Path to JSON file with token list (e.g., sandbox tokens.json)
 *   - DEPLOYMENT_CONFIG_FILE: Path to config file (will be updated in place)
 *   - BRIDGE_CONTRACT: Address of contract with rootTokenToChildToken(address) function
 *   - ETH_MAPPING: Address of the ETH ERC20 token on zkEVM (varies by network)
 *
 * Special cases:
 *   - token_address "eth" → tokenOnZKEVM = ETH_MAPPING (provided via env var)
 *   - ticker_symbol "IMX" → tokenOnZKEVM = 0x0000000000000000000000000000000000000FfF
 */
interface IRootTokenMapper {
    function rootTokenToChildToken(address rootToken) external view returns (address);
}

contract GenerateAssetMappings is Script {
    /// @dev Special address for native IMX on zkEVM
    address constant NATIVE_IMX_ADDRESS = 0x0000000000000000000000000000000000000FfF;

    string private tokensFilePath;
    string private configFilePath;
    address private bridgeContract;
    address private ethMapping;

    BridgedTokenMapping.TokenMapping[] private assetMappings;

    function setUp() external {
        tokensFilePath = vm.envString("TOKENS_FILE");
        configFilePath = vm.envString("DEPLOYMENT_CONFIG_FILE");
        bridgeContract = vm.envAddress("BRIDGE_CONTRACT");
        ethMapping = vm.envAddress("ETH_MAPPING");
    }

    function run() external {
        // Read the tokens file
        string memory tokensJson = vm.readFile(tokensFilePath);

        // Count tokens in the JSON array
        uint256 tokenCount = _countJsonArrayElements(tokensJson);

        console.log("Processing %d tokens...", tokenCount);

        IRootTokenMapper bridge = IRootTokenMapper(bridgeContract);

        // Process each token by parsing individual fields
        uint256 mappedCount = 0;
        for (uint256 i = 0; i < tokenCount; i++) {
            // Parse individual fields using JSON path
            string memory basePath = string(abi.encodePacked("$[", vm.toString(i), "]"));

            uint256 tokenInt = vm.parseJsonUint(tokensJson, string(abi.encodePacked(basePath, ".token_int")));
            uint256 quantum = vm.parseJsonUint(tokensJson, string(abi.encodePacked(basePath, ".quantum")));
            string memory tokenAddress =
                vm.parseJsonString(tokensJson, string(abi.encodePacked(basePath, ".token_address")));
            string memory tickerSymbol =
                vm.parseJsonString(tokensJson, string(abi.encodePacked(basePath, ".ticker_symbol")));

            address tokenOnZKEVM;

            // Check for special cases
            if (_isEthToken(tokenAddress)) {
                tokenOnZKEVM = ethMapping;
                console.log("  [%d] %s (ETH) -> %s", i, tickerSymbol, vm.toString(ethMapping));
            } else if (_isImxToken(tickerSymbol)) {
                tokenOnZKEVM = NATIVE_IMX_ADDRESS;
                console.log("  [%d] %s (IMX) -> 0xFfF", i, tickerSymbol);
            } else {
                // Query the bridge contract
                address rootToken = vm.parseAddress(tokenAddress);
                tokenOnZKEVM = bridge.rootTokenToChildToken(rootToken);

                if (tokenOnZKEVM == address(0)) {
                    console.log("  [%d] %s -> SKIPPED (not mapped)", i, tickerSymbol);
                    continue;
                }
                console.log("  [%d] %s -> %s", i, tickerSymbol, vm.toString(tokenOnZKEVM));
            }

            // Add to mappings
            assetMappings.push(
                BridgedTokenMapping.TokenMapping({
                    tokenOnIMX: BridgedTokenMapping.ImmutableXToken({id: tokenInt, quantum: quantum}),
                    tokenOnZKEVM: tokenOnZKEVM
                })
            );
            mappedCount++;
        }

        console.log("Generated %d asset mappings", mappedCount);

        // Write output
        _writeOutput();
    }

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

    function _isEthToken(string memory tokenAddress) private pure returns (bool) {
        return keccak256(bytes(tokenAddress)) == keccak256(bytes("eth"));
    }

    function _isImxToken(string memory tickerSymbol) private pure returns (bool) {
        return keccak256(bytes(tickerSymbol)) == keccak256(bytes("IMX"));
    }

    function _writeOutput() private {
        // Build the asset_mappings JSON array
        string memory mappingsJson = _serializeAssetMappings();

        // Update the asset_mappings in the config file in place
        vm.writeJson(mappingsJson, configFilePath, ".asset_mappings");

        console.log("Updated asset_mappings in: ", configFilePath);
    }

    function _serializeAssetMappings() private returns (string memory) {
        // Serialize each mapping
        string[] memory items = new string[](assetMappings.length);
        for (uint256 i = 0; i < assetMappings.length; i++) {
            string memory itemKey = string(abi.encodePacked("item_", vm.toString(i)));

            // Serialize tokenOnIMX
            string memory tokenOnIMXKey = string(abi.encodePacked("tokenOnIMX_", vm.toString(i)));
            vm.serializeUint(tokenOnIMXKey, "id", assetMappings[i].tokenOnIMX.id);
            string memory tokenOnIMXJson =
                vm.serializeUint(tokenOnIMXKey, "quantum", assetMappings[i].tokenOnIMX.quantum);

            // Serialize the full mapping object
            vm.serializeString(itemKey, "tokenOnIMX", tokenOnIMXJson);
            items[i] = vm.serializeAddress(itemKey, "tokenOnZKEVM", assetMappings[i].tokenOnZKEVM);
        }

        // Combine into array - we need to manually build the JSON array
        if (items.length == 0) {
            return "[]";
        }

        bytes memory result = "[";
        for (uint256 i = 0; i < items.length; i++) {
            if (i > 0) {
                result = abi.encodePacked(result, ",");
            }
            result = abi.encodePacked(result, items[i]);
        }
        result = abi.encodePacked(result, "]");

        return string(result);
    }
}
