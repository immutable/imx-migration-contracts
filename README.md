# Immutable X ERC-20 Migration Contracts

[![License: Apache 2.0](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![Solidity](https://img.shields.io/badge/Solidity-0.8.27+-brightgreen.svg)](https://soliditylang.org/)
[![Foundry](https://img.shields.io/badge/Foundry-1.0+-orange.svg)](https://getfoundry.sh/)

<!-- TOC -->
  * [Overview](#overview)
  * [Key Features](#key-features)
  * [Architecture](#architecture)
    * [Core Contracts](#core-contracts)
    * [Cross-chain Components](#cross-chain-components)
  * [Project Structure](#project-structure)
  * [Prerequisites](#prerequisites)
  * [Installation](#installation)
  * [Deployment](#deployment)
    * [Configuration](#configuration)
    * [Deploy L2 Contracts](#deploy-l2-contracts)
  * [Testing](#testing)
  * [Key Contracts](#key-contracts)
    * [StarkExchangeMigration](#starkexchangemigration)
    * [VaultWithdrawalProcessor](#vaultwithdrawalprocessor)
    * [VaultEscapeProofVerifier](#vaultescapeproofverifier)
  * [Cross-Chain Integration](#cross-chain-integration)
<!-- TOC -->

## External Audit status
As of January 28th, 2026 an external audit is currently underway for these contracts. Results of this will be committed into this repository once they are available.

## Overview
The IMX Migration Contracts facilitate the migration of ETH and ERC-20 assets from the legacy Immutable X bridge to Immutable zkEVM. This system provides secure, verifiable asset migration with cryptographic proof verification.

## Key Features
- **Asset Migration**: Seamless migration of ETH and ERC-20 tokens from Immutable X to zkEVM
- **Proof Verification**: Cryptographic verification of vault and account proofs using Merkle trees
- **Withdrawal Processing**: Automated processing of pending withdrawals with proof validation
- **Cross-Chain Messaging**: Axelar GMP integration for secure cross-chain communication
- **Token Mapping**: Flexible mapping between Immutable X asset IDs and zkEVM token addresses
- **Access Control**: Role-based access control for securing migration operations

## Architecture

The system consists of several key components:

### Core Contracts
- **`StarkExchangeMigration`**: Main migration contract that handles asset migration from Immutable X
   - Migrates vault root hashes to zkEVM
   - Processes ERC-20 and ETH holdings migration
   - Handles pending withdrawal finalization
   - Integrates with Axelar for cross-chain messaging 
- **`VaultWithdrawalProcessor`**: Processes withdrawals on zkEVM with proof verification
   - Verifying vault and account proofs
   - Mapping Immutable X assets to zkEVM tokens
   - Processing withdrawals with proper access control
   - Maintaining withdrawal state to prevent double-spending
- **`VaultEscapeProofVerifier`**: Verifies vault escape proofs using, optimised Pedersen hash-based Merkle proof validation
- **`AccountProofVerifier`**: Verifies account ownership proofs
- **`BridgedTokenMapping`**: Maps Immutable X asset IDs to zkEVM token addresses

### Cross-chain Components
- **`VaultRootSenderAdapter`**: Sends vault root hashes to zkEVM via Axelar
- **`VaultRootReceiverAdapter`**: Adapter for receiving vault roots on zkEVM
- **`IRootERC20Bridge`**: Interface for zkEVM bridge operations

Detailed architecture and security analysis is available [here](https://immutable.atlassian.net/wiki/spaces/~712020640315cc7a594fb28a6b452c5a8ef6a3/pages/3309731899/StarkExchange+ERC-20+Migration+Contracts+Overview)

## Project Structure

```
src/
├── bridge/                  # Bridge and messaging contracts
│   ├── starkex/               # Immutable X bridge contracts
│   ├── zkEVM/                 # zkEVM bridge interfaces
│   └── messaging/             # Cross-chain messaging adapters
├── verifiers/              # Proof verification contracts
│   ├── vaults/                # Vault proof verification
│   └── accounts/              # Account proof verification
├── withdrawals/            # Withdrawal processing contracts
└── assets/                 # Asset mapping and management
```

## Prerequisites

- [Foundry](https://getfoundry.sh/) 1.0+
- Solidity 0.8.27+
- Node.js 18+ (for deployment scripts)

## Installation

1. Clone the repository:
```bash
git clone <repository-url>
cd imx-migration-contracts
```

2. Install Foundry dependencies:
```bash
forge install
```

## Build and Test
Build the contracts:
```bash
forge build
```

Run the test suite:
```bash
# Run all tests
forge test

# Run specific test file
forge test --match-path test/unit/StarkExchangeMigration.t.sol
```

## Deployment
### Configuration
The system uses configuration files for deployment. Create a deployment configuration file with the following structure:

```json
{
  "allow_root_override": false,
  "vault_verifier": "0x...",
  "operators": {
    "disburser": "0x...",
    "pauser": "0x...",
    "unpauser": "0x..."
  },
  "lookup_tables": ["0x...", "0x...", ...],
  "asset_mappings": [
    {
      "tokenOnIMX": {
        "id": 123,
        "quantum": 1000000000000000000
      },
      "tokenOnZKEVM": "0x..."
    }
  ]
}
```

### Deploy L2 Contracts

1. Set environment variables:
```bash
export DEPLOYMENT_CONFIG_FILE="path/to/config.json"
export PRIVATE_KEY="your-private-key"
export RPC_URL="your-rpc-url"
```

2. Run deployment script:
```bash
forge script script/DeployL2Contracts.s.sol:DeployL2Contracts \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --verify
```

**Note**: Use `--slow` or `-batch-size 1` when deploying to Tenderly to avoid out-of-order deployments.


