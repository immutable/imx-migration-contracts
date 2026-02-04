#!/bin/bash
# Copyright Immutable Pty Ltd 2018 - 2025
# SPDX-License-Identifier: MIT
#
# Mint tokens to the withdrawal processor for testing purposes.
# This script reads token amounts from a JSON file, matches them to zkEVM addresses,
# and mints the tokens by impersonating the bridge.
#
# Usage:
#   ./scripts/mint_tokens.sh \
#       --rpc-url http://localhost:8545 \
#       --bridge 0xBa5E35E26Ae59c7aea6F029B68c6460De2d13eB6 \
#       --config config/sandbox/anvil/anvil_zkevm_testnet_config_deployed.json \
#       --tokens config/sandbox/imx_token_amounts.json
#
# Options:
#   --rpc-url       RPC endpoint for the zkEVM network
#   --bridge        Bridge address to impersonate (must have mint rights on tokens)
#   --config        Path to deployed config with withdrawal_processor and asset_mappings
#   --tokens        Path to JSON file with token amounts
#   --private-key   Optional: Private key for signing (if not using Anvil impersonation)

set -e

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --rpc-url)
            RPC_URL="$2"
            shift 2
            ;;
        --bridge)
            BRIDGE_ADDRESS="$2"
            shift 2
            ;;
        --config)
            CONFIG_FILE="$2"
            shift 2
            ;;
        --tokens)
            TOKENS_FILE="$2"
            shift 2
            ;;
        --private-key)
            PRIVATE_KEY="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Validate required arguments
if [ -z "$RPC_URL" ]; then
    echo "Error: --rpc-url is required"
    exit 1
fi

if [ -z "$BRIDGE_ADDRESS" ]; then
    echo "Error: --bridge is required"
    exit 1
fi

if [ -z "$CONFIG_FILE" ]; then
    echo "Error: --config is required"
    exit 1
fi

if [ -z "$TOKENS_FILE" ]; then
    echo "Error: --tokens is required"
    exit 1
fi

# Check files exist
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: Config file not found: $CONFIG_FILE"
    exit 1
fi

if [ ! -f "$TOKENS_FILE" ]; then
    echo "Error: Tokens file not found: $TOKENS_FILE"
    exit 1
fi

# Read withdrawal_processor from config (beneficiary)
BENEFICIARY=$(jq -r '.withdrawal_processor' "$CONFIG_FILE")
echo "Beneficiary (withdrawal_processor): $BENEFICIARY"
echo "Bridge address: $BRIDGE_ADDRESS"
echo ""

# If no private key, use Anvil impersonation
if [ -z "$PRIVATE_KEY" ]; then
    echo "Using Anvil impersonation mode..."
    cast rpc anvil_impersonateAccount "$BRIDGE_ADDRESS" --rpc-url "$RPC_URL" || {
        echo "Warning: Failed to impersonate account. If not using Anvil, provide --private-key"
    }
fi

# Count tokens
TOKEN_COUNT=$(jq 'length' "$TOKENS_FILE")
echo "Processing $TOKEN_COUNT tokens..."
echo ""

# Process each token
SUCCESS_COUNT=0
SKIP_COUNT=0
FAIL_COUNT=0

jq -c '.[]' "$TOKENS_FILE" | while read -r token; do
    TOKEN_INT=$(echo "$token" | jq -r '.token_int')
    AMOUNT=$(echo "$token" | jq -r '.unquantised_sum')
    TICKER=$(echo "$token" | jq -r '.ticker_symbol')
    
    # Find matching tokenOnZKEVM in asset_mappings
    # Note: token_int is a large number, need to match as string
    ZKEVM_ADDR=$(jq -r --arg id "$TOKEN_INT" \
        '.asset_mappings[] | select(.tokenOnIMX.id == $id) | .tokenOnZKEVM' "$CONFIG_FILE")
    
    if [ -z "$ZKEVM_ADDR" ] || [ "$ZKEVM_ADDR" == "null" ]; then
        echo "[$TICKER] SKIPPED - No matching asset mapping found for token_int: $TOKEN_INT"
        ((SKIP_COUNT++)) || true
        continue
    fi
    
    echo -n "[$TICKER] Minting $AMOUNT to $BENEFICIARY via $ZKEVM_ADDR... "
    
    # Handle IMX specially (native asset on zkEVM)
    if [ "$TICKER" == "IMX" ]; then
        # Convert amount to hex for anvil_setBalance
        AMOUNT_HEX=$(printf '0x%x' "$AMOUNT" 2>/dev/null || echo "0x0")
        
        if cast rpc anvil_setBalance "$BENEFICIARY" "$AMOUNT_HEX" --rpc-url "$RPC_URL" 2>/dev/null; then
            echo "OK (native IMX)"
            ((SUCCESS_COUNT++)) || true
        else
            echo "FAILED"
            ((FAIL_COUNT++)) || true
        fi
    else
        # Mint ERC20 token
        if [ -n "$PRIVATE_KEY" ]; then
            # Use private key
            if cast send "$ZKEVM_ADDR" "mint(address,uint256)" "$BENEFICIARY" "$AMOUNT" \
                --private-key "$PRIVATE_KEY" \
                --rpc-url "$RPC_URL" \
                --quiet 2>/dev/null; then
                echo "OK"
                ((SUCCESS_COUNT++)) || true
            else
                echo "FAILED"
                ((FAIL_COUNT++)) || true
            fi
        else
            # Use unlocked account (Anvil impersonation)
            if cast send "$ZKEVM_ADDR" "mint(address,uint256)" "$BENEFICIARY" "$AMOUNT" \
                --from "$BRIDGE_ADDRESS" \
                --unlocked \
                --rpc-url "$RPC_URL" \
                --quiet 2>/dev/null; then
                echo "OK"
                ((SUCCESS_COUNT++)) || true
            else
                echo "FAILED"
                ((FAIL_COUNT++)) || true
            fi
        fi
    fi
done

# Stop impersonation if we started it
if [ -z "$PRIVATE_KEY" ]; then
    cast rpc anvil_stopImpersonatingAccount "$BRIDGE_ADDRESS" --rpc-url "$RPC_URL" 2>/dev/null || true
fi

echo ""
echo "Done!"
echo "  Success: $SUCCESS_COUNT"
echo "  Skipped: $SKIP_COUNT"
echo "  Failed:  $FAIL_COUNT"
