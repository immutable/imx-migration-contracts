# Re-enable `registerEthAddress` with STARK Signature Verification

## Background

The StarkEx bridge contract's `ethKeys` mapping associates STARK public keys with Ethereum addresses. This mapping is required for the `withdraw` function to resolve a Stark key to a recipient address. For Stark keys that are >160 bits (i.e., not v4 standard keys that are simply Ethereum addresses cast to uint256), the `ethKeys` entry must exist or `withdraw` reverts with `"USER_UNREGISTERED"`.

The original StarkEx contract included a `registerEthAddress` function that allowed users to register their Stark key → Ethereum address association by providing a STARK-curve ECDSA signature proving ownership of the key. This function was removed during the migration upgrade. It now needs to be re-enabled because:

- 6 of 7 VCO token holders have Stark keys that return `address(0)` from `getEthKey`
- Other users with pre-existing `pendingWithdrawals` may also have unregistered Stark keys

## Architecture

### New Libraries

**`src/bridge/starkex/libraries/EllipticCurve.sol`**
- Port of the [Witnet EllipticCurve library](https://github.com/witnet/elliptic-curve-solidity) (MIT license) from Solidity `>=0.5.3 <0.7.0` to `^0.8.27`
- Provides low-level elliptic curve arithmetic: modular inverse, point addition, point doubling, scalar multiplication (Jacobian coordinates)
- Pure math library with no state or external dependencies

**`src/bridge/starkex/libraries/StarkCurveECDSA.sol`**
- Port of StarkEx's STARK-curve ECDSA verification from Solidity `^0.6.12` to `^0.8.27`
- Defines the Stark curve constants: `FIELD_PRIME`, `ALPHA` (1), `BETA`, `EC_ORDER`, generator point (`EC_GEN_X`, `EC_GEN_Y`)
- Provides `verify(msgHash, r, s, pubX, pubY)` which validates a STARK-curve ECDSA signature
- Uses `EllipticCurve` library for point arithmetic

### Modified Contract

**`src/bridge/starkex/LegacyStarkExchangeBridge.sol`**

Adds the following functions from the original StarkEx `Users.sol` contract. These belong in `LegacyStarkExchangeBridge` (not `StarkExchangeVCODistribution`) because key registration is a general bridge function that was part of the original StarkEx implementation, not VCO-specific. Since `StarkExchangeVCODistribution` inherits from `LegacyStarkExchangeBridge` through the chain, the functions are available on the deployed contract.

```solidity
function registerEthAddress(
    address ethKey,
    uint256 starkKey,
    bytes calldata starkSignature
) public
```
- Open to anyone (permissionless, matching the original)
- Validates: `starkKey != 0`, `starkKey < K_MODULUS`, `ethKey != address(0)`, `ethKeys[starkKey] == address(0)` (not already registered), `isOnCurve(starkKey)`
- Signature is 96 bytes: `abi.encode(r, s, StarkKeyY)` where `StarkKeyY` is the y-coordinate of the Stark public key
- Message hash: `uint256(keccak256("UserRegistration:", ethKey, starkKey)) % EC_ORDER`
- On success: writes `ethKeys[starkKey] = ethKey`, emits `LogUserRegistered(ethKey, starkKey, msg.sender)`

```solidity
function registerSender(uint256 starkKey, bytes calldata starkSignature) external
```
- Convenience wrapper: calls `registerEthAddress(msg.sender, starkKey, starkSignature)`

Supporting private/internal functions:
- `isOnCurve(uint256 starkKey)` — checks if the x-coordinate lies on the Stark curve
- `isQuadraticResidue(uint256 fieldElement)` — Euler's criterion via modular exponentiation
- `fieldPow(uint256 base, uint256 exponent)` — modular exponentiation using the `modexp` precompile at `address(5)`

Stark curve constants defined in the contract:
- `K_MODULUS = 0x800000000000011000000000000000000000000000000000000000000000001`
- `K_BETA = 0x6f21413efbe40de150e596d72f7a8c5609ad26c15c915c1f4cdfcb99cee9e89`

## Data Flow

1. User obtains their STARK private key and generates a signature over `keccak256("UserRegistration:", ethAddress, starkKey)`
2. User calls `registerEthAddress(ethAddress, starkKey, abi.encode(r, s, starkKeyY))` on the proxy
3. Contract validates the key, checks it's on the curve, verifies the signature
4. Contract writes `ethKeys[starkKey] = ethAddress` and emits `LogUserRegistered`
5. User (or anyone) calls `withdraw(starkKey, assetType)` which now resolves to the registered address

## Porting Notes (Solidity 0.6.12 → 0.8.27)

- **Overflow safety**: Solidity 0.8+ has built-in overflow checks. The EllipticCurve library primarily uses `mulmod`/`addmod` (overflow-safe by design) and patterns like `_pp - value` where `value < _pp` is guaranteed by prior checks. Raw subtractions in Jacobian arithmetic that could underflow must be wrapped in `unchecked {}` blocks since the original code relied on 0.6's wrapping behavior, or restructured to use `addmod` with negation (the `_pp - x` pattern already used throughout).
- **Pragma**: `^0.6.12` / `>=0.5.3 <0.7.0` → `^0.8.27`
- **`address(5).staticcall`**: The modexp precompile works identically in 0.8
- **`using Library for uint256`**: Same syntax in 0.8

## Testing

### Unit Tests

Added to `test/unit/bridge/starkex/StarkExchangeVCODistribution.t.sol`:

- **Valid registration**: Generate a known Stark key pair, sign a registration message, call `registerEthAddress`, verify `getEthKey` returns the registered address
- **`registerSender` wrapper**: Call via `registerSender`, verify `ethKeys` is set to `msg.sender`
- **Invalid Stark key**: key = 0, key >= K_MODULUS → revert
- **Invalid Ethereum address**: ethKey = address(0) → revert
- **Duplicate registration**: Register once, try again → revert with `"STARK_KEY_UNAVAILABLE"`
- **Invalid signature length**: signature not 96 bytes → revert
- **Invalid signature**: wrong signature data → revert with `"INVALID_STARK_SIGNATURE"`
- **Off-curve key**: key not on Stark curve → revert with `"INVALID_STARK_KEY"`
- **Register then withdraw**: Register a >160-bit Stark key, then withdraw VCO tokens to the registered address

### Integration Test

Added to integration test:
- Register a holder's Stark key on the mainnet fork, then withdraw VCO

## Files

| File | Action | Description |
|------|--------|-------------|
| `src/bridge/starkex/libraries/EllipticCurve.sol` | Create | Port of Witnet EC arithmetic library |
| `src/bridge/starkex/libraries/StarkCurveECDSA.sol` | Create | Port of StarkEx STARK-curve ECDSA verification |
| `src/bridge/starkex/LegacyStarkExchangeBridge.sol` | Modify | Add `registerEthAddress`, `registerSender`, curve helpers, constants |
| `test/unit/bridge/starkex/StarkExchangeVCODistribution.t.sol` | Modify | Add registration and register-then-withdraw tests |
| `test/integration/bridge/starkex/StarkExchangeVCODistribution.t.sol` | Modify | Add registration integration test |
