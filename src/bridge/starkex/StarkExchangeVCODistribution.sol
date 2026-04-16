// Copyright Immutable Pty Ltd 2018 - 2025
// SPDX-License-Identifier: Apache-2.0.
pragma solidity ^0.8.27;

import {StarkExchangeMigration} from "./StarkExchangeMigration.sol";
import {StarkCurveECDSA} from "./libraries/StarkCurveECDSA.sol";

/**
 * @title StarkExchangeVCODistribution
 * @notice Upgrades the StarkEx bridge to distribute VCO tokens to 7 holders who were missed during the
 *         original migration due to a bug in the VCO token's `approve` method.
 * @dev Populates `pendingWithdrawals` entries during initialization, allowing holders to withdraw
 *      using the standard `withdraw(uint256, uint256)` function inherited from LegacyStarkExchangeBridge.
 *      All existing StarkExchangeMigration functionality is preserved.
 */
contract StarkExchangeVCODistribution is StarkExchangeMigration {
    /// @notice VCO token asset type ID from the StarkEx system
    uint256 public constant VCO_ASSET_TYPE =
        1485183671027309009439509871835489442660821279230223034298428454062208985878;

    // -----------------------------------------------------------------------
    //  Holder data: Stark keys and quantized amounts
    //  IMPORTANT: Replace these placeholder values with actual holder data
    //  before deployment. The Stark key is the ownerKey used to call withdraw().
    //  The amount is the QUANTIZED amount (actual amount = quantized * quantum).
    // -----------------------------------------------------------------------
    uint256 public constant HOLDER_1_KEY = 0x00AA00000000000000000000000000000000000001;
    uint256 public constant HOLDER_1_AMOUNT = 100;
    uint256 public constant HOLDER_2_KEY = 0x00AA00000000000000000000000000000000000002;
    uint256 public constant HOLDER_2_AMOUNT = 200;
    uint256 public constant HOLDER_3_KEY = 0x00AA00000000000000000000000000000000000003;
    uint256 public constant HOLDER_3_AMOUNT = 300;
    uint256 public constant HOLDER_4_KEY = 0x00AA00000000000000000000000000000000000004;
    uint256 public constant HOLDER_4_AMOUNT = 400;
    uint256 public constant HOLDER_5_KEY = 0x00AA00000000000000000000000000000000000005;
    uint256 public constant HOLDER_5_AMOUNT = 500;
    uint256 public constant HOLDER_6_KEY = 0x00AA00000000000000000000000000000000000006;
    uint256 public constant HOLDER_6_AMOUNT = 600;
    uint256 public constant HOLDER_7_KEY = 0x00AA00000000000000000000000000000000000007;
    uint256 public constant HOLDER_7_AMOUNT = 700;

    /**
     * @notice Populates `pendingWithdrawals` with VCO token entries for the 7 holders.
     * @param data Unused — required to match the parent function signature for StarkEx proxy compatibility.
     * @dev Uses `reinitializer(2)` because the parent's `initialize` used `initializer` (equivalent to
     *      reinitializer(1)). This ensures the function can only execute once.
     */
    function initialize(bytes calldata data) external override reinitializer(2) {
        pendingWithdrawals[HOLDER_1_KEY][VCO_ASSET_TYPE] = HOLDER_1_AMOUNT;
        pendingWithdrawals[HOLDER_2_KEY][VCO_ASSET_TYPE] = HOLDER_2_AMOUNT;
        pendingWithdrawals[HOLDER_3_KEY][VCO_ASSET_TYPE] = HOLDER_3_AMOUNT;
        pendingWithdrawals[HOLDER_4_KEY][VCO_ASSET_TYPE] = HOLDER_4_AMOUNT;
        pendingWithdrawals[HOLDER_5_KEY][VCO_ASSET_TYPE] = HOLDER_5_AMOUNT;
        pendingWithdrawals[HOLDER_6_KEY][VCO_ASSET_TYPE] = HOLDER_6_AMOUNT;
        pendingWithdrawals[HOLDER_7_KEY][VCO_ASSET_TYPE] = HOLDER_7_AMOUNT;
    }

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
}
