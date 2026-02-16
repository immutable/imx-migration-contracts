// Copyright Immutable Pty Ltd 2018 - 2025
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "forge-std/console.sol";

/**
 * @title VerifyAssetMappings
 * @notice Verifies that asset_mappings in the token_mappings config match the bridge contract's
 *         rootTokenToChildToken() results for every token in the imx_tokens file.
 * @dev For each token in the tokens file, this script:
 *      1. Finds the matching entry in asset_mappings (by token_int == tokenOnIMX.id)
 *      2. Queries rootTokenToChildToken(token_address) on the bridge contract
 *      3. Compares the bridge result with the tokenOnZKEVM in the config
 *
 * Required env vars:
 *   - TOKENS_FILE: Path to imx_tokens JSON file
 *   - DEPLOYMENT_CONFIG_FILE: Path to token_mappings JSON file (with asset_mappings array)
 *   - BRIDGE_CONTRACT: Address of contract with rootTokenToChildToken(address) function
 *   - ETH_MAPPING: Address of the ETH ERC20 token on zkEVM (for the special "eth" token)
 *
 * Usage:
 *   TOKENS_FILE=config/operate/sandbox/imx_tokens.json \
 *   DEPLOYMENT_CONFIG_FILE=config/operate/sandbox/token_mappings.json \
 *   BRIDGE_CONTRACT=0x... \
 *   ETH_MAPPING=0x... \
 *   forge script script/VerifyAssetMappings.s.sol --rpc-url $RPC_URL
 */
interface ITokenMapper {
    function rootTokenToChildToken(address rootToken) external view returns (address);
}

contract VerifyAssetMappings is Script {
    /// @dev Special address for native IMX on zkEVM
    address constant NATIVE_IMX_ADDRESS = 0x0000000000000000000000000000000000000FfF;

    string private tokensFilePath;
    string private configFilePath;
    address private bridgeContract;
    address private ethMapping;

    function setUp() external {
        tokensFilePath = vm.envString("TOKENS_FILE");
        configFilePath = vm.envString("DEPLOYMENT_CONFIG_FILE");
        bridgeContract = vm.envAddress("BRIDGE_CONTRACT");
        ethMapping = vm.envAddress("ETH_MAPPING");
    }

    function run() external view {
        string memory tokensJson = vm.readFile(tokensFilePath);
        string memory configJson = vm.readFile(configFilePath);

        uint256 tokenCount = _countJsonArrayElements(tokensJson);
        uint256 mappingCount = _countJsonArrayElements2(configJson);

        console.log("=== Asset Mapping Verification ===");
        console.log("Tokens file:  %s (%d tokens)", tokensFilePath, tokenCount);
        console.log("Config file:  %s (%d mappings)", configFilePath, mappingCount);
        console.log("Bridge:       %s", vm.toString(bridgeContract));
        console.log("ETH mapping:  %s", vm.toString(ethMapping));
        console.log("");

        ITokenMapper bridge = ITokenMapper(bridgeContract);

        uint256 passCount = 0;
        uint256 failCount = 0;
        uint256 missingCount = 0;

        for (uint256 i = 0; i < tokenCount; i++) {
            string memory basePath = string(abi.encodePacked("$[", vm.toString(i), "]"));

            uint256 tokenInt = vm.parseJsonUint(tokensJson, string(abi.encodePacked(basePath, ".token_int")));
            string memory tokenAddress =
                vm.parseJsonString(tokensJson, string(abi.encodePacked(basePath, ".token_address")));
            string memory tickerSymbol =
                vm.parseJsonString(tokensJson, string(abi.encodePacked(basePath, ".ticker_symbol")));
            uint256 quantum = vm.parseJsonUint(tokensJson, string(abi.encodePacked(basePath, ".quantum")));

            // Find matching entry in asset_mappings by tokenOnIMX.id
            (bool found, address configZkevmAddr) = _findMappingById(configJson, mappingCount, tokenInt);

            if (!found) {
                console.log(
                    "  [%d] MISSING  %s (token_int: %s) - not found in asset_mappings",
                    i,
                    tickerSymbol,
                    vm.toString(tokenInt)
                );
                missingCount++;
                continue;
            }

            // Get expected zkEVM address from bridge
            address bridgeZkevmAddr;

            if (_isEthToken(tokenAddress)) {
                bridgeZkevmAddr = ethMapping;
            } else if (_isImxToken(tickerSymbol)) {
                bridgeZkevmAddr = NATIVE_IMX_ADDRESS;
            } else {
                address rootToken = vm.parseAddress(tokenAddress);
                bridgeZkevmAddr = bridge.rootTokenToChildToken(rootToken);
            }

            // Compare
            if (bridgeZkevmAddr == configZkevmAddr) {
                console.log("  [%d] PASS  %s  root=%s", i, tickerSymbol, _formatAddress(tokenAddress));
                console.log("             zkEVM=%s  quantum=%d", vm.toString(configZkevmAddr), quantum);
                passCount++;
            } else {
                console.log("  [%d] FAIL  %s  root=%s", i, tickerSymbol, _formatAddress(tokenAddress));
                console.log("             config tokenOnZKEVM = %s", vm.toString(configZkevmAddr));
                console.log("             bridge rootToChild   = %s", vm.toString(bridgeZkevmAddr));
                failCount++;
            }
        }

        // Summary
        console.log("");
        console.log("=== Summary ===");
        console.log("  Total tokens: %d", tokenCount);
        console.log("  PASS:         %d", passCount);
        console.log("  FAIL:         %d", failCount);
        console.log("  MISSING:      %d", missingCount);

        if (failCount > 0 || missingCount > 0) {
            console.log("");
            console.log("VERIFICATION FAILED");
        } else {
            console.log("");
            console.log("ALL CHECKS PASSED");
        }
    }

    /// @dev Find the tokenOnZKEVM address in asset_mappings where tokenOnIMX.id matches the given id.
    function _findMappingById(string memory configJson, uint256 mappingCount, uint256 targetId)
        private
        pure
        returns (bool found, address tokenOnZKEVM)
    {
        for (uint256 j = 0; j < mappingCount; j++) {
            string memory mappingBase = string(abi.encodePacked("$.asset_mappings[", vm.toString(j), "]"));

            uint256 mappingId = vm.parseJsonUint(configJson, string(abi.encodePacked(mappingBase, ".tokenOnIMX.id")));

            if (mappingId == targetId) {
                tokenOnZKEVM = vm.parseJsonAddress(configJson, string(abi.encodePacked(mappingBase, ".tokenOnZKEVM")));
                return (true, tokenOnZKEVM);
            }
        }

        return (false, address(0));
    }

    /// @dev Count top-level objects in a JSON array (for the tokens file which is a plain array).
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

    /// @dev Count elements in the asset_mappings array inside a JSON object.
    ///      Finds the asset_mappings key and counts objects at the appropriate depth.
    function _countJsonArrayElements2(string memory json) private pure returns (uint256) {
        bytes memory jsonBytes = bytes(json);
        uint256 count = 0;

        // Find the "asset_mappings" key and then count objects in its array
        bytes memory key = bytes('"asset_mappings"');
        uint256 keyStart = _findSubstring(jsonBytes, key);
        if (keyStart == type(uint256).max) return 0;

        // Find the opening '[' after the key
        uint256 arrStart = keyStart + key.length;
        while (arrStart < jsonBytes.length && jsonBytes[arrStart] != "[") {
            arrStart++;
        }
        if (arrStart >= jsonBytes.length) return 0;

        // Count objects at depth 1 within this array
        uint256 depth = 0;
        bool inString = false;
        for (uint256 i = arrStart; i < jsonBytes.length; i++) {
            bytes1 c = jsonBytes[i];

            if (c == '"' && (i == 0 || jsonBytes[i - 1] != "\\")) {
                inString = !inString;
            }

            if (!inString) {
                if (c == "[") {
                    depth++;
                } else if (c == "]") {
                    if (depth == 1) break;
                    depth--;
                } else if (c == "{" && depth == 1) {
                    count++;
                }
            }
        }

        return count;
    }

    function _findSubstring(bytes memory haystack, bytes memory needle) private pure returns (uint256) {
        if (needle.length > haystack.length) return type(uint256).max;
        for (uint256 i = 0; i <= haystack.length - needle.length; i++) {
            bool found = true;
            for (uint256 j = 0; j < needle.length; j++) {
                if (haystack[i + j] != needle[j]) {
                    found = false;
                    break;
                }
            }
            if (found) return i;
        }
        return type(uint256).max;
    }

    function _isEthToken(string memory tokenAddress) private pure returns (bool) {
        return keccak256(bytes(tokenAddress)) == keccak256(bytes("eth"));
    }

    function _isImxToken(string memory tickerSymbol) private pure returns (bool) {
        return keccak256(bytes(tickerSymbol)) == keccak256(bytes("IMX"));
    }

    function _formatAddress(string memory addr) private pure returns (string memory) {
        if (_isEthToken(addr)) return "eth (native)";
        return addr;
    }
}
