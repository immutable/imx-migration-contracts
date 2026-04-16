# registerEthAddress Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Re-enable STARK-curve signature-verified `registerEthAddress` on the StarkEx bridge so users with unregistered Stark keys can associate their Ethereum address and withdraw pending balances.

**Architecture:** Port three files from the original StarkEx contracts (Solidity 0.6.12 → 0.8.27): `EllipticCurve.sol` (EC arithmetic), `StarkCurveECDSA.sol` (STARK signature verification), and the `registerEthAddress`/`registerSender` functions added directly to `StarkExchangeVCODistribution.sol`.

**Tech Stack:** Solidity 0.8.27, Foundry, Witnet EllipticCurve library (MIT), StarkEx STARK-curve ECDSA (Apache-2.0)

---

## File Structure

| File | Action | Responsibility |
|------|--------|----------------|
| `src/bridge/starkex/libraries/EllipticCurve.sol` | Create | EC point arithmetic (add, mul, inverse) on arbitrary curves |
| `src/bridge/starkex/libraries/StarkCurveECDSA.sol` | Create | STARK-curve ECDSA signature verification |
| `src/bridge/starkex/LegacyStarkExchangeBridge.sol` | Modify | Add `registerEthAddress`, `registerSender`, curve helpers |
| `test/unit/bridge/starkex/StarkExchangeVCODistribution.t.sol` | Modify | Add registration tests with in-test STARK signature generation |

---

### Task 1: Create EllipticCurve library

**Files:**
- Create: `src/bridge/starkex/libraries/EllipticCurve.sol`

Port of the [Witnet EllipticCurve library](https://github.com/witnet/elliptic-curve-solidity) (MIT license) from Solidity `>=0.5.3 <0.7.0` to `^0.8.27`. The arithmetic uses `mulmod`/`addmod` and `_pp - x` patterns where `x < _pp`, so all operations are safe under 0.8's overflow checks without needing `unchecked` blocks.

- [ ] **Step 1: Create the library file**

Create `src/bridge/starkex/libraries/EllipticCurve.sol`:

```solidity
// SPDX-License-Identifier: MIT
/*
  MIT License
  Copyright (c) 2019 Witnet Project
  https://github.com/witnet/elliptic-curve-solidity/blob/master/contracts/EllipticCurve.sol

  Ported from Solidity >=0.5.3 <0.7.0 to ^0.8.27 for the Immutable X migration contracts.
  Original source: https://github.com/starkware-libs/starkex-contracts/blob/f4ed79bb04b56d587618c24312e87d81e4efc56b/scalable-dex/contracts/src/third_party/EllipticCurve.sol
*/
pragma solidity ^0.8.27;

/**
 * @title Elliptic Curve Library
 * @dev Library providing arithmetic operations over elliptic curves.
 * @author Witnet Foundation
 */
library EllipticCurve {
    uint256 private constant U255_MAX_PLUS_1 =
        57896044618658097711785492504343953926634992332820282019728792003956564819968;

    /// @dev Modular euclidean inverse of a number (mod p).
    function invMod(uint256 _x, uint256 _pp) internal pure returns (uint256) {
        require(_x != 0 && _x != _pp && _pp != 0, "Invalid number");
        uint256 q = 0;
        uint256 newT = 1;
        uint256 r = _pp;
        uint256 t;
        while (_x != 0) {
            t = r / _x;
            (q, newT) = (newT, addmod(q, (_pp - mulmod(t, newT, _pp)), _pp));
            (r, _x) = (_x, r - t * _x);
        }
        return q;
    }

    /// @dev Modular exponentiation, b^e % _pp.
    function expMod(uint256 _base, uint256 _exp, uint256 _pp) internal pure returns (uint256) {
        require(_pp != 0, "Modulus is zero");
        if (_base == 0) return 0;
        if (_exp == 0) return 1;

        uint256 r = 1;
        uint256 bit = U255_MAX_PLUS_1;
        assembly {
            for {} gt(bit, 0) {} {
                r := mulmod(mulmod(r, r, _pp), exp(_base, iszero(iszero(and(_exp, bit)))), _pp)
                r := mulmod(mulmod(r, r, _pp), exp(_base, iszero(iszero(and(_exp, div(bit, 2))))), _pp)
                r := mulmod(mulmod(r, r, _pp), exp(_base, iszero(iszero(and(_exp, div(bit, 4))))), _pp)
                r := mulmod(mulmod(r, r, _pp), exp(_base, iszero(iszero(and(_exp, div(bit, 8))))), _pp)
                bit := div(bit, 16)
            }
        }
        return r;
    }

    /// @dev Converts a point (x, y, z) expressed in Jacobian coordinates to affine coordinates (x', y', 1).
    function toAffine(uint256 _x, uint256 _y, uint256 _z, uint256 _pp)
        internal
        pure
        returns (uint256, uint256)
    {
        uint256 zInv = invMod(_z, _pp);
        uint256 zInv2 = mulmod(zInv, zInv, _pp);
        uint256 x2 = mulmod(_x, zInv2, _pp);
        uint256 y2 = mulmod(_y, mulmod(zInv, zInv2, _pp), _pp);
        return (x2, y2);
    }

    /// @dev Add two points (x1, y1) and (x2, y2) in affine coordinates.
    function ecAdd(uint256 _x1, uint256 _y1, uint256 _x2, uint256 _y2, uint256 _aa, uint256 _pp)
        internal
        pure
        returns (uint256, uint256)
    {
        uint256 x = 0;
        uint256 y = 0;
        uint256 z = 0;
        if (_x1 == _x2) {
            if (addmod(_y1, _y2, _pp) == 0) {
                return (0, 0);
            } else {
                (x, y, z) = jacDouble(_x1, _y1, 1, _aa, _pp);
            }
        } else {
            (x, y, z) = jacAdd(_x1, _y1, 1, _x2, _y2, 1, _pp);
        }
        return toAffine(x, y, z, _pp);
    }

    /// @dev Multiply point (x1, y1, z1) times d in affine coordinates.
    function ecMul(uint256 _k, uint256 _x, uint256 _y, uint256 _aa, uint256 _pp)
        internal
        pure
        returns (uint256, uint256)
    {
        (uint256 x1, uint256 y1, uint256 z1) = jacMul(_k, _x, _y, 1, _aa, _pp);
        return toAffine(x1, y1, z1, _pp);
    }

    /// @dev Adds two points (x1, y1, z1) and (x2 y2, z2) in Jacobian coordinates.
    function jacAdd(
        uint256 _x1,
        uint256 _y1,
        uint256 _z1,
        uint256 _x2,
        uint256 _y2,
        uint256 _z2,
        uint256 _pp
    ) internal pure returns (uint256, uint256, uint256) {
        if (_x1 == 0 && _y1 == 0) return (_x2, _y2, _z2);
        if (_x2 == 0 && _y2 == 0) return (_x1, _y1, _z1);

        uint256[4] memory zs;
        zs[0] = mulmod(_z1, _z1, _pp);
        zs[1] = mulmod(_z1, zs[0], _pp);
        zs[2] = mulmod(_z2, _z2, _pp);
        zs[3] = mulmod(_z2, zs[2], _pp);

        zs = [
            mulmod(_x1, zs[2], _pp),
            mulmod(_y1, zs[3], _pp),
            mulmod(_x2, zs[0], _pp),
            mulmod(_y2, zs[1], _pp)
        ];

        require(zs[0] != zs[2] || zs[1] != zs[3], "Use jacDouble function instead");

        uint256[4] memory hr;
        hr[0] = addmod(zs[2], _pp - zs[0], _pp);
        hr[1] = addmod(zs[3], _pp - zs[1], _pp);
        hr[2] = mulmod(hr[0], hr[0], _pp);
        hr[3] = mulmod(hr[2], hr[0], _pp);

        uint256 qx = addmod(mulmod(hr[1], hr[1], _pp), _pp - hr[3], _pp);
        qx = addmod(qx, _pp - mulmod(2, mulmod(zs[0], hr[2], _pp), _pp), _pp);

        uint256 qy = mulmod(hr[1], addmod(mulmod(zs[0], hr[2], _pp), _pp - qx, _pp), _pp);
        qy = addmod(qy, _pp - mulmod(zs[1], hr[3], _pp), _pp);

        uint256 qz = mulmod(hr[0], mulmod(_z1, _z2, _pp), _pp);
        return (qx, qy, qz);
    }

    /// @dev Doubles a point (x, y, z) in Jacobian coordinates.
    function jacDouble(uint256 _x, uint256 _y, uint256 _z, uint256 _aa, uint256 _pp)
        internal
        pure
        returns (uint256, uint256, uint256)
    {
        if (_z == 0) return (_x, _y, _z);

        uint256 x = mulmod(_x, _x, _pp);
        uint256 y = mulmod(_y, _y, _pp);
        uint256 z = mulmod(_z, _z, _pp);

        uint256 s = mulmod(4, mulmod(_x, y, _pp), _pp);
        uint256 m = addmod(mulmod(3, x, _pp), mulmod(_aa, mulmod(z, z, _pp), _pp), _pp);

        x = addmod(mulmod(m, m, _pp), _pp - addmod(s, s, _pp), _pp);
        y = addmod(mulmod(m, addmod(s, _pp - x, _pp), _pp), _pp - mulmod(8, mulmod(y, y, _pp), _pp), _pp);
        z = mulmod(2, mulmod(_y, _z, _pp), _pp);

        return (x, y, z);
    }

    /// @dev Multiply point (x, y, z) times d in Jacobian coordinates.
    function jacMul(uint256 _d, uint256 _x, uint256 _y, uint256 _z, uint256 _aa, uint256 _pp)
        internal
        pure
        returns (uint256, uint256, uint256)
    {
        if (_d == 0) return (_x, _y, _z);

        uint256 remaining = _d;
        uint256 qx = 0;
        uint256 qy = 0;
        uint256 qz = 1;

        while (remaining != 0) {
            if ((remaining & 1) != 0) {
                (qx, qy, qz) = jacAdd(qx, qy, qz, _x, _y, _z, _pp);
            }
            remaining = remaining / 2;
            (_x, _y, _z) = jacDouble(_x, _y, _z, _aa, _pp);
        }
        return (qx, qy, qz);
    }
}
```

- [ ] **Step 2: Verify compilation**

Run: `forge build`
Expected: Compiles successfully.

- [ ] **Step 3: Commit**

```bash
git add src/bridge/starkex/libraries/EllipticCurve.sol
git commit -m "feat: port EllipticCurve library to Solidity 0.8.27"
```

---

### Task 2: Create StarkCurveECDSA library

**Files:**
- Create: `src/bridge/starkex/libraries/StarkCurveECDSA.sol`

Port of StarkEx's STARK-curve ECDSA verification. Renamed from `ECDSA` to `StarkCurveECDSA` to avoid conflicts with OpenZeppelin's ECDSA.

- [ ] **Step 1: Create the library file**

Create `src/bridge/starkex/libraries/StarkCurveECDSA.sol`:

```solidity
// Copyright Immutable Pty Ltd 2018 - 2025
// SPDX-License-Identifier: Apache-2.0.
/*
  Ported from Solidity ^0.6.12 to ^0.8.27 for the Immutable X migration contracts.
  Original source: https://github.com/starkware-libs/starkex-contracts/blob/f4ed79bb04b56d587618c24312e87d81e4efc56b/scalable-dex/contracts/src/components/ECDSA.sol
*/
pragma solidity ^0.8.27;

import {EllipticCurve} from "./EllipticCurve.sol";

library StarkCurveECDSA {
    using EllipticCurve for uint256;

    uint256 internal constant FIELD_PRIME =
        0x800000000000011000000000000000000000000000000000000000000000001;
    uint256 internal constant ALPHA = 1;
    uint256 internal constant BETA =
        3141592653589793238462643383279502884197169399375105820974944592307816406665;
    uint256 internal constant EC_ORDER =
        3618502788666131213697322783095070105526743751716087489154079457884512865583;
    uint256 internal constant N_ELEMENT_BITS_ECDSA = 251;
    uint256 internal constant EC_GEN_X =
        0x1ef15c18599971b7beced415a40f0c7deacfd9b0d1819e03d723d8bc943cfca;
    uint256 internal constant EC_GEN_Y =
        0x5668060aa49730b7be4801df46ec62de53ecd11abe43a32873000c36e8dc1f;

    function verify(uint256 msgHash, uint256 r, uint256 s, uint256 pubX, uint256 pubY) internal pure {
        require(msgHash % EC_ORDER == msgHash, "msgHash out of range");
        require((1 <= s) && (s < EC_ORDER), "s out of range");
        uint256 w = s.invMod(EC_ORDER);
        require((1 <= r) && (r < (1 << N_ELEMENT_BITS_ECDSA)), "r out of range");
        require((1 <= w) && (w < (1 << N_ELEMENT_BITS_ECDSA)), "w out of range");

        // Verify that pub is a valid point (y^2 = x^3 + x + BETA).
        {
            uint256 x3 = mulmod(mulmod(pubX, pubX, FIELD_PRIME), pubX, FIELD_PRIME);
            uint256 y2 = mulmod(pubY, pubY, FIELD_PRIME);
            require(y2 == addmod(addmod(x3, pubX, FIELD_PRIME), BETA, FIELD_PRIME), "INVALID_STARK_KEY");
        }

        // Verify signature.
        uint256 b_x;
        uint256 b_y;
        {
            (uint256 zG_x, uint256 zG_y) = msgHash.ecMul(EC_GEN_X, EC_GEN_Y, ALPHA, FIELD_PRIME);
            (uint256 rQ_x, uint256 rQ_y) = r.ecMul(pubX, pubY, ALPHA, FIELD_PRIME);
            (b_x, b_y) = zG_x.ecAdd(zG_y, rQ_x, rQ_y, ALPHA, FIELD_PRIME);
        }
        (uint256 res_x,) = w.ecMul(b_x, b_y, ALPHA, FIELD_PRIME);

        require(res_x == r, "INVALID_STARK_SIGNATURE");
    }
}
```

- [ ] **Step 2: Verify compilation**

Run: `forge build`
Expected: Compiles successfully.

- [ ] **Step 3: Commit**

```bash
git add src/bridge/starkex/libraries/StarkCurveECDSA.sol
git commit -m "feat: port StarkCurveECDSA library to Solidity 0.8.27"
```

---

### Task 3: Add `registerEthAddress` to `StarkExchangeVCODistribution`

**Files:**
- Modify: `src/bridge/starkex/StarkExchangeVCODistribution.sol`

Add the registration functions ported from the original StarkEx `Users.sol`, with curve constants needed for the on-curve check.

- [ ] **Step 1: Add the import and registration code**

In `src/bridge/starkex/StarkExchangeVCODistribution.sol`, add the import after the existing import:

```solidity
import {StarkExchangeMigration} from "./StarkExchangeMigration.sol";
import {StarkCurveECDSA} from "./libraries/StarkCurveECDSA.sol";
```

Add the following constants, event, and functions to the contract body, after the `initialize` function:

```solidity
    // -----------------------------------------------------------------------
    //  Stark key registration (ported from original StarkEx Users.sol)
    // -----------------------------------------------------------------------

    /// @notice Stark-friendly elliptic curve prime field modulus
    uint256 private constant K_MODULUS =
        0x800000000000011000000000000000000000000000000000000000000000001;

    /// @notice Stark curve beta constant
    uint256 private constant K_BETA =
        0x6f21413efbe40de150e596d72f7a8c5609ad26c15c915c1f4cdfcb99cee9e89;

    /// @notice Emitted when a user registers their Stark key to an Ethereum address
    event LogUserRegistered(address ethKey, uint256 starkKey, address sender);

    /**
     * @notice Convenience function: registers msg.sender as the Ethereum address for the given Stark key.
     * @param starkKey The Stark public key (x-coordinate on the Stark curve)
     * @param starkSignature 96-byte signature: abi.encode(r, s, starkKeyY)
     */
    function registerSender(uint256 starkKey, bytes calldata starkSignature) external {
        registerEthAddress(msg.sender, starkKey, starkSignature);
    }

    /**
     * @notice Associates an Ethereum address with a Stark key, verified by a STARK-curve ECDSA signature.
     * @param ethKey The Ethereum address to associate
     * @param starkKey The Stark public key (x-coordinate on the Stark curve)
     * @param starkSignature 96-byte signature: abi.encode(r, s, starkKeyY)
     * @dev Ported from the original StarkEx Users.sol contract.
     */
    function registerEthAddress(address ethKey, uint256 starkKey, bytes calldata starkSignature) public {
        require(starkKey != 0, "INVALID_STARK_KEY");
        require(starkKey < K_MODULUS, "INVALID_STARK_KEY");
        require(ethKey != address(0), "INVALID_ETH_ADDRESS");
        require(ethKeys[starkKey] == address(0), "STARK_KEY_UNAVAILABLE");
        require(_isOnCurve(starkKey), "INVALID_STARK_KEY");
        require(starkSignature.length == 32 * 3, "INVALID_STARK_SIGNATURE_LENGTH");

        bytes memory sig = starkSignature;
        (uint256 r, uint256 s, uint256 starkKeyY) = abi.decode(sig, (uint256, uint256, uint256));

        uint256 msgHash =
            uint256(keccak256(abi.encodePacked("UserRegistration:", ethKey, starkKey))) % StarkCurveECDSA.EC_ORDER;

        StarkCurveECDSA.verify(msgHash, r, s, starkKey, starkKeyY);

        ethKeys[starkKey] = ethKey;

        emit LogUserRegistered(ethKey, starkKey, msg.sender);
    }

    /**
     * @notice Checks if a Stark key x-coordinate lies on the Stark curve.
     * @dev Verifies that x^3 + alpha*x + beta is a quadratic residue mod p (alpha = 1).
     */
    function _isOnCurve(uint256 starkKey) private view returns (bool) {
        uint256 xCubed = mulmod(mulmod(starkKey, starkKey, K_MODULUS), starkKey, K_MODULUS);
        return _isQuadraticResidue(addmod(addmod(xCubed, starkKey, K_MODULUS), K_BETA, K_MODULUS));
    }

    /**
     * @notice Checks if a field element is a quadratic residue using Euler's criterion.
     */
    function _isQuadraticResidue(uint256 fieldElement) private view returns (bool) {
        return 1 == _fieldPow(fieldElement, ((K_MODULUS - 1) / 2));
    }

    /**
     * @notice Modular exponentiation using the modexp precompile (address 0x05).
     */
    function _fieldPow(uint256 base, uint256 exponent) private view returns (uint256) {
        (bool success, bytes memory returndata) =
            address(5).staticcall(abi.encode(0x20, 0x20, 0x20, base, exponent, K_MODULUS));
        require(success, "FIELD_POW_FAILED");
        return abi.decode(returndata, (uint256));
    }
```

- [ ] **Step 2: Verify compilation**

Run: `forge build`
Expected: Compiles successfully.

- [ ] **Step 3: Run existing tests to verify no regression**

Run: `forge test --match-path test/unit/bridge/starkex/StarkExchangeVCODistribution.t.sol -v`
Expected: All 11 existing tests PASS.

- [ ] **Step 4: Commit**

```bash
git add src/bridge/starkex/StarkExchangeVCODistribution.sol
git commit -m "feat: add registerEthAddress with STARK signature verification"
```

---

### Task 4: Unit tests for valid registration

**Files:**
- Modify: `test/unit/bridge/starkex/StarkExchangeVCODistribution.t.sol`

Tests generate STARK key pairs and signatures in Solidity using the ported libraries, making them fully self-contained.

- [ ] **Step 1: Add imports and test helper functions**

Add these imports to the top of the test file, after the existing imports:

```solidity
import {EllipticCurve} from "@src/bridge/starkex/libraries/EllipticCurve.sol";
import {StarkCurveECDSA} from "@src/bridge/starkex/libraries/StarkCurveECDSA.sol";
```

Add these helper functions and constants to the `StarkExchangeVCODistributionTest` contract:

```solidity
    // -----------------------------------------------------------------------
    // STARK key test helpers
    // -----------------------------------------------------------------------

    uint256 constant TEST_STARK_PRIVATE_KEY = 0x1234567890abcdef;
    uint256 constant TEST_NONCE = 0xfedcba9876543210;

    function _generateStarkKeyPair(uint256 privateKey) internal pure returns (uint256 pubX, uint256 pubY) {
        (pubX, pubY) = EllipticCurve.ecMul(
            privateKey,
            StarkCurveECDSA.EC_GEN_X,
            StarkCurveECDSA.EC_GEN_Y,
            StarkCurveECDSA.ALPHA,
            StarkCurveECDSA.FIELD_PRIME
        );
    }

    function _signRegistration(uint256 privateKey, uint256 nonce, address ethKey, uint256 starkKey, uint256 starkKeyY)
        internal
        pure
        returns (bytes memory)
    {
        uint256 msgHash =
            uint256(keccak256(abi.encodePacked("UserRegistration:", ethKey, starkKey))) % StarkCurveECDSA.EC_ORDER;

        // r = (nonce * G).x
        (uint256 r,) = EllipticCurve.ecMul(
            nonce, StarkCurveECDSA.EC_GEN_X, StarkCurveECDSA.EC_GEN_Y, StarkCurveECDSA.ALPHA, StarkCurveECDSA.FIELD_PRIME
        );

        // s = nonce^(-1) * (msgHash + r * privateKey) mod EC_ORDER
        uint256 rk = mulmod(r, privateKey, StarkCurveECDSA.EC_ORDER);
        uint256 sum = addmod(msgHash, rk, StarkCurveECDSA.EC_ORDER);
        uint256 nonceInv = EllipticCurve.invMod(nonce, StarkCurveECDSA.EC_ORDER);
        uint256 s = mulmod(nonceInv, sum, StarkCurveECDSA.EC_ORDER);

        return abi.encode(r, s, starkKeyY);
    }
```

- [ ] **Step 2: Add test for valid `registerEthAddress`**

Add to the test contract:

```solidity
    // -----------------------------------------------------------------------
    // registerEthAddress tests
    // -----------------------------------------------------------------------

    function test_RegisterEthAddress_Valid() public {
        (uint256 starkKey, uint256 starkKeyY) = _generateStarkKeyPair(TEST_STARK_PRIVATE_KEY);
        address ethKey = address(0x9876543210987654321098765432109876543210);

        bytes memory sig = _signRegistration(TEST_STARK_PRIVATE_KEY, TEST_NONCE, ethKey, starkKey, starkKeyY);

        bridge.registerEthAddress(ethKey, starkKey, sig);

        assertEq(bridge.getEthKey(starkKey), ethKey, "Registered eth key should match");
    }
```

- [ ] **Step 3: Add test for `registerSender` convenience function**

```solidity
    function test_RegisterSender_Valid() public {
        (uint256 starkKey, uint256 starkKeyY) = _generateStarkKeyPair(TEST_STARK_PRIVATE_KEY);
        address sender = address(0xABCDABCDABCDABCDABCDABCDABCDABCDABCDABCD);

        bytes memory sig = _signRegistration(TEST_STARK_PRIVATE_KEY, TEST_NONCE, sender, starkKey, starkKeyY);

        vm.prank(sender);
        bridge.registerSender(starkKey, sig);

        assertEq(bridge.getEthKey(starkKey), sender, "Registered eth key should be msg.sender");
    }
```

- [ ] **Step 4: Add test for `LogUserRegistered` event emission**

```solidity
    function test_RegisterEthAddress_EmitsLogUserRegistered() public {
        (uint256 starkKey, uint256 starkKeyY) = _generateStarkKeyPair(TEST_STARK_PRIVATE_KEY);
        address ethKey = address(0x9876543210987654321098765432109876543210);
        address caller = address(0x1111111111111111111111111111111111111111);

        bytes memory sig = _signRegistration(TEST_STARK_PRIVATE_KEY, TEST_NONCE, ethKey, starkKey, starkKeyY);

        vm.expectEmit(true, true, true, true);
        emit StarkExchangeVCODistribution.LogUserRegistered(ethKey, starkKey, caller);

        vm.prank(caller);
        bridge.registerEthAddress(ethKey, starkKey, sig);
    }
```

- [ ] **Step 5: Run tests — expect pass**

Run: `forge test --match-test "test_Register" -v`
Expected: All 3 registration tests PASS.

- [ ] **Step 6: Commit**

```bash
git add test/unit/bridge/starkex/StarkExchangeVCODistribution.t.sol
git commit -m "test: add valid registration tests with STARK signature generation"
```

---

### Task 5: Unit tests for registration error cases

**Files:**
- Modify: `test/unit/bridge/starkex/StarkExchangeVCODistribution.t.sol`

- [ ] **Step 1: Add test for zero Stark key**

```solidity
    function test_RevertIf_RegisterEthAddress_ZeroStarkKey() public {
        vm.expectRevert("INVALID_STARK_KEY");
        bridge.registerEthAddress(address(0x1234), 0, bytes(new bytes(96)));
    }
```

- [ ] **Step 2: Add test for Stark key >= K_MODULUS**

```solidity
    function test_RevertIf_RegisterEthAddress_StarkKeyTooLarge() public {
        uint256 kModulus = 0x800000000000011000000000000000000000000000000000000000000000001;
        vm.expectRevert("INVALID_STARK_KEY");
        bridge.registerEthAddress(address(0x1234), kModulus, bytes(new bytes(96)));
    }
```

- [ ] **Step 3: Add test for zero Ethereum address**

```solidity
    function test_RevertIf_RegisterEthAddress_ZeroEthAddress() public {
        (uint256 starkKey,) = _generateStarkKeyPair(TEST_STARK_PRIVATE_KEY);
        vm.expectRevert("INVALID_ETH_ADDRESS");
        bridge.registerEthAddress(address(0), starkKey, bytes(new bytes(96)));
    }
```

- [ ] **Step 4: Add test for duplicate registration**

```solidity
    function test_RevertIf_RegisterEthAddress_DuplicateRegistration() public {
        (uint256 starkKey, uint256 starkKeyY) = _generateStarkKeyPair(TEST_STARK_PRIVATE_KEY);
        address ethKey = address(0x9876543210987654321098765432109876543210);

        bytes memory sig = _signRegistration(TEST_STARK_PRIVATE_KEY, TEST_NONCE, ethKey, starkKey, starkKeyY);
        bridge.registerEthAddress(ethKey, starkKey, sig);

        // Second registration with same stark key should fail
        address ethKey2 = address(0x1111111111111111111111111111111111111111);
        bytes memory sig2 = _signRegistration(TEST_STARK_PRIVATE_KEY, TEST_NONCE, ethKey2, starkKey, starkKeyY);

        vm.expectRevert("STARK_KEY_UNAVAILABLE");
        bridge.registerEthAddress(ethKey2, starkKey, sig2);
    }
```

- [ ] **Step 5: Add test for invalid signature length**

```solidity
    function test_RevertIf_RegisterEthAddress_InvalidSignatureLength() public {
        (uint256 starkKey,) = _generateStarkKeyPair(TEST_STARK_PRIVATE_KEY);
        vm.expectRevert("INVALID_STARK_SIGNATURE_LENGTH");
        bridge.registerEthAddress(address(0x1234), starkKey, bytes(new bytes(64)));
    }
```

- [ ] **Step 6: Add test for invalid signature (wrong eth address)**

```solidity
    function test_RevertIf_RegisterEthAddress_InvalidSignature() public {
        (uint256 starkKey, uint256 starkKeyY) = _generateStarkKeyPair(TEST_STARK_PRIVATE_KEY);
        address ethKey = address(0x9876543210987654321098765432109876543210);
        address wrongEthKey = address(0x1111111111111111111111111111111111111111);

        // Sign for ethKey but try to register wrongEthKey
        bytes memory sig = _signRegistration(TEST_STARK_PRIVATE_KEY, TEST_NONCE, ethKey, starkKey, starkKeyY);

        vm.expectRevert("INVALID_STARK_SIGNATURE");
        bridge.registerEthAddress(wrongEthKey, starkKey, sig);
    }
```

- [ ] **Step 7: Run tests — expect pass**

Run: `forge test --match-path test/unit/bridge/starkex/StarkExchangeVCODistribution.t.sol -v`
Expected: All tests PASS (11 existing + 3 valid registration + 6 error cases = 20 total).

- [ ] **Step 8: Commit**

```bash
git add test/unit/bridge/starkex/StarkExchangeVCODistribution.t.sol
git commit -m "test: add registration error case tests"
```

---

### Task 6: Register-then-withdraw end-to-end test

**Files:**
- Modify: `test/unit/bridge/starkex/StarkExchangeVCODistribution.t.sol`

This test proves the full flow: register a >160-bit Stark key, then withdraw VCO tokens to the registered address.

- [ ] **Step 1: Add end-to-end test**

Add to the test contract:

```solidity
    function test_RegisterThenWithdraw_FullFlow() public {
        // Generate a STARK key pair (the public key x-coordinate is >160 bits)
        (uint256 starkKey, uint256 starkKeyY) = _generateStarkKeyPair(TEST_STARK_PRIVATE_KEY);
        address ethKey = address(0x9876543210987654321098765432109876543210);

        // Verify this key is actually >160 bits (would fail getEthKey without registration)
        assertGt(starkKey, type(uint160).max, "Stark key should be >160 bits for this test");
        assertEq(bridge.getEthKey(starkKey), address(0), "Key should not be registered yet");

        // Register the Stark key -> Ethereum address
        bytes memory sig = _signRegistration(TEST_STARK_PRIVATE_KEY, TEST_NONCE, ethKey, starkKey, starkKeyY);
        bridge.registerEthAddress(ethKey, starkKey, sig);
        assertEq(bridge.getEthKey(starkKey), ethKey, "Key should now be registered");

        // Set up a pending withdrawal for this stark key
        bridge.setupEthKey(starkKey, ethKey); // Already set by registerEthAddress, but setupEthKey is idempotent
        uint256 vcoAssetType = bridge.VCO_ASSET_TYPE();
        uint256 withdrawAmount = 1000;

        // Use vm.store to write directly to pendingWithdrawals[starkKey][vcoAssetType]
        // pendingWithdrawals is at storage slot 7 in MainStorage
        // slot = keccak256(abi.encode(vcoAssetType, keccak256(abi.encode(starkKey, 7))))
        bytes32 innerSlot = keccak256(abi.encode(starkKey, uint256(7)));
        bytes32 slot = keccak256(abi.encode(vcoAssetType, innerSlot));
        vm.store(address(bridge), slot, bytes32(withdrawAmount));

        // Fund bridge with VCO tokens
        uint256 nonQuantizedAmount = withdrawAmount * VCO_QUANTUM;
        vcoToken.mint(address(bridge), nonQuantizedAmount);

        // Withdraw — should succeed because the key is now registered
        bridge.withdraw(starkKey, vcoAssetType);

        // Verify recipient received tokens
        assertEq(vcoToken.balanceOf(ethKey), nonQuantizedAmount, "Recipient should receive VCO tokens");
    }
```

- [ ] **Step 2: Run test — expect pass**

Run: `forge test --match-test test_RegisterThenWithdraw_FullFlow -v`
Expected: PASS.

Note: If the `pendingWithdrawals` storage slot computation is wrong (slot 7 may vary), adjust the slot number. The slot for `pendingWithdrawals` in MainStorage can be verified by checking the storage layout. Count the variables: GovernanceStorage has 1 struct (slot 0-1), ProxyStorage has 3 mappings (slots 2-4), MainStorage starts at: escapeVerifierAddress (5), stateFrozen (6), unFreezeTime (7)... Actually, `pendingWithdrawals` is the 7th state variable. But mappings don't occupy sequential slots — they each take one slot for the base. Let me count more carefully:

Storage slots in MainStorage (inheriting ProxyStorage → GovernanceStorage):
- GovernanceStorage: `GovernanceInfoStruct` is a struct containing 1 address → slot 0
- ProxyStorage: `initializationHash_DEPRECATED` (mapping) → slot 1, `enabledTime` (mapping) → slot 2, `initialized` (mapping) → slot 3
- MainStorage: `escapeVerifierAddress` → slot 4, `stateFrozen` → slot 5, `unFreezeTime` → slot 6, `pendingDeposits` (mapping) → slot 7, `cancellationRequests` (mapping) → slot 8, `pendingWithdrawals` (mapping) → slot 9

If the slot is wrong, the test will fail and the implementer should use `forge inspect StarkExchangeVCODistribution storage-layout` to find the correct slot.

- [ ] **Step 3: Commit**

```bash
git add test/unit/bridge/starkex/StarkExchangeVCODistribution.t.sol
git commit -m "test: add register-then-withdraw end-to-end test"
```

---

### Task 7: Final verification

- [ ] **Step 1: Run the full unit test suite**

Run: `forge test --no-match-path "test/integration/*" -v`
Expected: All tests PASS. The 2 pre-existing failures requiring `ZKEVM_RPC_URL` are unrelated.

- [ ] **Step 2: Run existing StarkExchangeMigration tests to confirm no regressions**

Run: `forge test --match-path test/unit/bridge/starkex/StarkExchangeMigration.t.sol -v`
Expected: All 21 original tests PASS.

- [ ] **Step 3: Verify the VCO distribution tests still pass**

Run: `forge test --match-path test/unit/bridge/starkex/StarkExchangeVCODistribution.t.sol -v`
Expected: All ~20 tests PASS (11 original + ~9 registration tests).

- [ ] **Step 4: Final commit if any adjustments were needed**

```bash
git add -A
git commit -m "chore: final adjustments from full test suite run"
```
