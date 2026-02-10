# Immutable X Asset Migration Contracts

[![License: Apache 2.0](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![Solidity](https://img.shields.io/badge/Solidity-0.8.27+-brightgreen.svg)](https://soliditylang.org/)
[![Foundry](https://img.shields.io/badge/Foundry-1.0+-orange.svg)](https://getfoundry.sh/)

<!-- TOC -->
* [Immutable X Asset Migration Contracts](#immutable-x-asset-migration-contracts)
  * [External Audit](#external-audit)
  * [Overview](#overview)
  * [Capabilities](#capabilities)
    * [Legacy Bridge Lifecycle](#legacy-bridge-lifecycle)
    * [Migration and Disbursement](#migration-and-disbursement)
  * [System Guarantees](#system-guarantees)
  * [Trust Assumptions](#trust-assumptions)
  * [Design Constraints](#design-constraints)
  * [Known Limitations](#known-limitations)
  * [Definitions](#definitions)
  * [System Overview](#system-overview)
    * [Core Contracts](#core-contracts)
      * [Ethereum](#ethereum)
      * [Immutable zkEVM](#immutable-zkevm)
    * [Cross-chain Components](#cross-chain-components)
  * [Project Structure](#project-structure)
  * [Prerequisites](#prerequisites)
  * [Installation](#installation)
  * [Build and Test](#build-and-test)
  * [Deployment](#deployment)
    * [Configuration](#configuration)
    * [Deploy L2 Contracts](#deploy-l2-contracts)
  * [Supporting Documents](#supporting-documents)
<!-- TOC -->


## External Audit
The contracts in this repository were independently audited by Nethermind Security in February 2026. The full audit report is available [here](./audit/20260209-nethermind-audit.pdf).

## Overview
The Immutable X chain will be sunset in early 2026. Most users will withdraw their assets before the sunset date. However, for some users, the cost and friction of standard withdrawals may exceed the value of their remaining on-chain assets.

To address this, an automated post-sunset migration process will transfer remaining user funds from the legacy Immutable X bridge to Immutable zkEVM, where assets will be automatically disbursed to their rightful owners.

The migration contracts in this repository implement this process while minimising additional trust assumptions. The mechanism anchors on the final StarkEx vault root of the Immutable X chain at shutdown, and strictly constrains all fund disbursements on zkEVM to require valid proofs against this root, ensuring migrated assets are disbursed only to their rightful owners.

---

## Capabilities
### Legacy Bridge Lifecycle
1. **Pending Withdrawal Finalisation:**
   The Immutable X bridge should continue to enable users with withdrawals initiated prior to sunset to finalise those withdrawals via the Immutable X bridge using the standard withdrawal mechanism.
1. **Legacy Bridge Functionality:**
   Disable defunct functionality of the legacy bridge following chain sunset, while preserving only the minimum functionality required to finalise pre-sunset withdrawals.
### Migration and Disbursement
1. **Phased Fund Migration:**
   Enable the transfer of remaining funds from the Immutable X bridge to Immutable zkEVM in administrator-defined, bounded phases *(note exclusions for pending withdrawals and burnt assets)*
1. **Proof-Gated Disbursement:**
   Enable a permissioned entity to disburse migrated funds on zkEVM to their rightful owners, strictly subject to the submission and on-chain verification of cryptographic proofs of Immutable X vault ownership against the final vault root.
1. **Idempotent Disbursement:**
   Ensure that each Immutable X vault can be withdrawn or disbursed at most once, preventing double-disbursements across all migration phases.
1. **Preservation of Burn Semantics:**
    Migration of assets should account for assets that were considered burnt on Immutable X, by leaving these funds permanently on the legacy bridge.

---

## System Guarantees
- **Security and Migration Integrity**: The system must guarantee correct fund disbursement based on authenticated vault ownership, with no loss of funds and no permanently stuck balances.
- **Public Transparency**: All data and mechanisms required to independently verify migration correctness - including final vault and account roots - are publicly accessible and do not rely on privileged access.
- **Bounded Migration Latency**: The overall migration should complete within a bounded and predictable timeframe, minimising user friction and prioritising active or high-value vaults where practical.

---

## Trust Assumptions
- **Permissioned Operators:**
  - **Disburser**  
   The disbursement function on zkEVM is executed by a permissioned role. While this operator is not trusted to determine recipient correctness (as all disbursements are strictly gated by on-chain verification of vault proofs), it is trusted to execute the disbursement process in a timely manner, such that user funds are not left permanently stuck.
  - **Migration Initiator**  
    This operator is responsible for initiating the migration process and advancing the phased transfer of funds from the Immutable X bridge. It is trusted to (i) ensure the migration progresses without leaving user funds stranded, and (ii) migrate only eligible funds, explicitly excluding pending withdrawals and assets considered burnt.
- **Finalised Account Mappings:**  
  Finalised Immutable X account mappings (i.e. Stark key → Ethereum address associations) will be published publicly in advance to allow users to verify correctness. These mappings are derived from off-chain systems, as there is no reliable or complete on-chain source of truth.  
  Trust assumptions are mitigated by (i) publishing the full account association data for public verification, and (ii) pre-committing the corresponding account root to the zkEVM disbursement contract prior to the legacy bridge upgrade. This process requires that new account creation and modification mechanisms are disabled before the commitment is made, which is ensured through disabling relevant off-chain systems.
---

## Design Constraints
- **Disburser Contract Immutability:** The disburser contract on Immutable zkEVM is immutable and non-upgradable. While certain security parameters will initially be configurable, ownership and all role-based access controls will be irrevocably renounced prior to the corresponding L1 bridge upgrade taking effect, ensuring no further administrative control over the contract post-activation.
- **Bridge Upgrade Timelock:** Upgrades to the Immutable X bridge contract on Ethereum are subject to a mandatory 14-day timelock prior to activation.

---
## Known Limitations
- **Post-sunset Deposits**:
  Deposits made after chain sunset but before finalisation of the legacy bridge contract upgrade may result in permanently stuck funds. This is mitigated through adequate public communication relating to the migration timeline.
- **Post-sunset Account Creation**:
  New accounts created through on-chain operations following final account root commitments on the disbursal contract, would not be reflected in finalised account association. This is mitigated through adequate public communication relating to the migration timeline. 

---
## Definitions
- **Vault Root:** The final StarkEx-proven Merkle root representing Immutable X vault ownership at shutdown.
- **Vault Proof:** A cryptographic proof of owner address, token and balance information relating to a specific Immutable X vault under the final vault root committed on Ethereum.
- **Account Mapping:** The association of a user's Stark Key to Ethereum addresses.
---

## System Overview
The overall automated migration system consists of both off-chain and on-chain components. This section outlines the on-chain components, housed in this repository:

### Core Contracts
#### Ethereum
- **`StarkExchangeMigration`**: Main migration contract that handles asset migration from Immutable X
   - Migrates vault root hashes to zkEVM
   - Processes ERC-20 and ETH holdings migration
   - Handles pending withdrawal finalization
   - Integrates with Axelar for cross-chain messaging 
#### Immutable zkEVM
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

---


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
git clone https://github.com/immutable/imx-migration-contracts.git
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



## Supporting Documents
- [Key Decisions and Technical Considerations](https://immutable.atlassian.net/wiki/spaces/~712020640315cc7a594fb28a6b452c5a8ef6a3/pages/3186852061/Key+Technical+Decisions)
- [Migration Process Outline](https://immutable.atlassian.net/wiki/spaces/~712020640315cc7a594fb28a6b452c5a8ef6a3/pages/3186131252/Immutable+X+ERC-20+Migration+Process+Overview)
- [Architecture and Security Analysis](https://immutable.atlassian.net/wiki/spaces/~712020640315cc7a594fb28a6b452c5a8ef6a3/pages/3309731899/StarkExchange+ERC-20+Migration+Contracts+Overview)
