# Anvil Scripts

Shell scripts for local development and testing on **Anvil fork chains only**.

These scripts use Anvil-specific RPC methods (`anvil_setBalance`, `anvil_impersonateAccount`) that are not available on real networks. They are intended for local testing and sandbox environments.

## Prerequisites

- [Foundry](https://book.getfoundry.sh/) installed (`cast` CLI)
- `jq` for JSON processing
- A running **Anvil** instance (forked or standalone)

## Scripts

| Script | Purpose |
|--------|---------|
| `anvil_mint_tokens.sh` | Mint tokens to the withdrawal processor by impersonating the bridge |
| `anvil_setup_disbursers.sh` | Fund accounts and grant DISBURSER_ROLE |

---

### anvil_mint_tokens.sh

Mints tokens to the withdrawal processor for testing. Uses Anvil's account impersonation to mint tokens as if the bridge were calling.

**Usage:**

```bash
./scripts/anvil_mint_tokens.sh \
    --rpc-url http://localhost:8545 \
    --bridge 0xBa5E35E26Ae59c7aea6F029B68c6460De2d13eB6 \
    --config config/sandbox/anvil/anvil_zkevm_testnet_config_deployed.json \
    --tokens config/sandbox/imx_token_amounts.json
```

**Arguments:**

| Argument | Required | Description |
|----------|----------|-------------|
| `--rpc-url` | Yes | Anvil RPC endpoint |
| `--bridge` | Yes | Bridge address to impersonate (must have mint rights on tokens) |
| `--config` | Yes | Path to deployed config with `withdrawal_processor` and `asset_mappings` |
| `--tokens` | Yes | Path to JSON file with token amounts |
| `--private-key` | No | Private key (alternative to impersonation) |

**Behavior:**

- Reads `withdrawal_processor` from config as the beneficiary
- For each token in the amounts file:
  - Matches `token_int` to `tokenOnIMX.id` in `asset_mappings`
  - **IMX tokens**: Uses `anvil_setBalance` to set native balance
  - **Other tokens**: Impersonates bridge and calls `mint(address,uint256)`
- Skips tokens without a matching asset mapping

**Anvil-Specific Features Used:**
- `anvil_impersonateAccount` / `anvil_stopImpersonatingAccount`
- `anvil_setBalance` (for IMX native token)

---

### anvil_setup_disbursers.sh

Sets up disburser accounts by funding them with native tokens and granting the `DISBURSER_ROLE` on the withdrawal processor contract.

**Usage:**

```bash
./scripts/anvil_setup_disbursers.sh \
    --rpc-url http://localhost:8545 \
    --contract 0xA15BB66138824a1c7167f5E85b957d04Dd34E468 \
    --disbursers config/sandbox/disbursers.txt \
    --admin-key $ADMIN_PRIVATE_KEY
```

**Arguments:**

| Argument | Required | Description |
|----------|----------|-------------|
| `--rpc-url` | Yes | Anvil RPC endpoint |
| `--contract` | Yes | Withdrawal processor contract address |
| `--disbursers` | Yes | Path to file with comma-separated addresses |
| `--admin-key` | Yes | Private key of account with DEFAULT_ADMIN_ROLE |
| `--balance` | No | Amount to fund in hex (default: 100 ETH = `0x56bc75e2d63100000`) |

**Behavior:**

- Reads comma-separated addresses from the disbursers file
- For each address:
  - Funds with native tokens via `anvil_setBalance`
  - Grants `DISBURSER_ROLE` (`0x83b1a44decfa848e00bb3100d7cc1596f7f72453e6ae10ceea99dc7cd75046f0`)

**Anvil-Specific Features Used:**
- `anvil_setBalance`

**Disbursers File Format:**

```
0xAddress1, 0xAddress2, 0xAddress3
```

---

## Example Workflow

```bash
# 1. Start Anvil fork
anvil --fork-url $ZKEVM_RPC_URL

# 2. Deploy contracts (see script/README.md)
DEPLOYMENT_CONFIG_FILE=config/sandbox/anvil/anvil_zkevm_testnet_config.json \
DEPLOYMENT_OUTPUT_FILE=config/sandbox/anvil/anvil_zkevm_testnet_config_deployed.json \
forge script script/DeployL2Contracts.s.sol --rpc-url http://localhost:8545 --broadcast

# 3. Setup disbursers
./scripts/anvil_setup_disbursers.sh \
    --rpc-url http://localhost:8545 \
    --contract $WITHDRAWAL_PROCESSOR \
    --disbursers config/sandbox/disbursers.txt \
    --admin-key $ADMIN_KEY

# 4. Mint tokens to withdrawal processor
./scripts/anvil_mint_tokens.sh \
    --rpc-url http://localhost:8545 \
    --bridge $BRIDGE_ADDRESS \
    --config config/sandbox/anvil/anvil_zkevm_testnet_config_deployed.json \
    --tokens config/sandbox/imx_token_amounts.json
```

## Why Anvil-Only?

These scripts rely on Anvil's special RPC methods:

| Method | Purpose |
|--------|---------|
| `anvil_setBalance` | Set arbitrary ETH/native token balance |
| `anvil_impersonateAccount` | Send transactions as any address without private key |

These methods don't exist on real networks (mainnet, testnets, Tenderly, etc.).
