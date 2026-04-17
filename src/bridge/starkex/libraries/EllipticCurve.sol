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
    function toAffine(uint256 _x, uint256 _y, uint256 _z, uint256 _pp) internal pure returns (uint256, uint256) {
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
    function jacAdd(uint256 _x1, uint256 _y1, uint256 _z1, uint256 _x2, uint256 _y2, uint256 _z2, uint256 _pp)
        internal
        pure
        returns (uint256, uint256, uint256)
    {
        if (_x1 == 0 && _y1 == 0) return (_x2, _y2, _z2);
        if (_x2 == 0 && _y2 == 0) return (_x1, _y1, _z1);

        uint256[4] memory zs;
        zs[0] = mulmod(_z1, _z1, _pp);
        zs[1] = mulmod(_z1, zs[0], _pp);
        zs[2] = mulmod(_z2, _z2, _pp);
        zs[3] = mulmod(_z2, zs[2], _pp);

        zs = [mulmod(_x1, zs[2], _pp), mulmod(_y1, zs[3], _pp), mulmod(_x2, zs[0], _pp), mulmod(_y2, zs[1], _pp)];

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
