#!/bin/bash
# Copyright Immutable Pty Ltd 2018 - 2025
# SPDX-License-Identifier: MIT
#
# Setup disbursers by funding them and granting DISBURSER_ROLE.
# This script reads addresses from a file, funds them via Anvil,
# and grants them the DISBURSER_ROLE on the specified contract.
#
# Usage:
#   ./scripts/setup_disbursers.sh \
#       --rpc-url http://localhost:8545 \
#       --contract 0xA15BB66138824a1c7167f5E85b957d04Dd34E468 \
#       --disbursers config/sandbox/disbursers.txt \
#       --admin-key $ADMIN_PRIVATE_KEY
#
# Options:
#   --rpc-url       RPC endpoint (Anvil)
#   --contract      Contract address to call grantRole on (e.g., withdrawal_processor)
#   --disbursers    Path to file with comma-separated addresses
#   --admin-key     Private key of account with admin rights to grant roles
#   --balance       Optional: Amount of native tokens to fund in hex (default: 100 ETH)

set -e

# DISBURSER_ROLE hash
DISBURSER_ROLE="0x83b1a44decfa848e00bb3100d7cc1596f7f72453e6ae10ceea99dc7cd75046f0"

# Default balance: 100 ETH in wei (hex)
DEFAULT_BALANCE="0x56bc75e2d63100000"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --rpc-url)
            RPC_URL="$2"
            shift 2
            ;;
        --contract)
            CONTRACT="$2"
            shift 2
            ;;
        --disbursers)
            DISBURSERS_FILE="$2"
            shift 2
            ;;
        --admin-key)
            ADMIN_KEY="$2"
            shift 2
            ;;
        --balance)
            BALANCE="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Use default balance if not provided
BALANCE="${BALANCE:-$DEFAULT_BALANCE}"

# Validate required arguments
if [ -z "$RPC_URL" ]; then
    echo "Error: --rpc-url is required"
    exit 1
fi

if [ -z "$CONTRACT" ]; then
    echo "Error: --contract is required"
    exit 1
fi

if [ -z "$DISBURSERS_FILE" ]; then
    echo "Error: --disbursers is required"
    exit 1
fi

if [ -z "$ADMIN_KEY" ]; then
    echo "Error: --admin-key is required"
    exit 1
fi

# Check file exists
if [ ! -f "$DISBURSERS_FILE" ]; then
    echo "Error: Disbursers file not found: $DISBURSERS_FILE"
    exit 1
fi

echo "Contract: $CONTRACT"
echo "Disbursers file: $DISBURSERS_FILE"
echo "Balance to set: $BALANCE"
echo ""

# Read addresses from file (comma-space separated, convert to newline-separated)
ADDRESSES=$(cat "$DISBURSERS_FILE" | tr ',' '\n' | tr -d ' ' | tr -d '\n' | tr -s '\n')

# Count addresses
ADDRESS_COUNT=$(echo "$ADDRESSES" | grep -c . || echo 0)
echo "Processing $ADDRESS_COUNT disbursers..."
echo ""

# Process each address
SUCCESS_COUNT=0
FAIL_COUNT=0

for addr in $(cat "$DISBURSERS_FILE" | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'); do
    # Skip empty lines
    if [ -z "$addr" ]; then
        continue
    fi
    
    echo -n "[$addr] "
    
    # 1. Fund the address
    echo -n "Funding... "
    if cast rpc anvil_setBalance "$addr" "$BALANCE" --rpc-url "$RPC_URL" 2>/dev/null; then
        echo -n "OK. "
    else
        echo "FAILED to fund"
        ((FAIL_COUNT++)) || true
        continue
    fi
    
    # 2. Grant DISBURSER_ROLE
    echo -n "Granting DISBURSER_ROLE... "
    if cast send "$CONTRACT" "grantRole(bytes32,address)" \
        "$DISBURSER_ROLE" \
        "$addr" \
        --private-key "$ADMIN_KEY" \
        --rpc-url "$RPC_URL" \
        --quiet 2>/dev/null; then
        echo "OK"
        ((SUCCESS_COUNT++)) || true
    else
        echo "FAILED to grant role"
        ((FAIL_COUNT++)) || true
    fi
done

echo ""
echo "Done!"
echo "  Success: $SUCCESS_COUNT"
echo "  Failed:  $FAIL_COUNT"
