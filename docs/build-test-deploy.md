# Build, Test and Deploy

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


