// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "@src/assets/AssetsRegistry.sol";
import "@src/assets/AssetsRegistry.sol";
import "@src/assets/AssetsRegistry.sol";
import "@src/proofs/accounts/IAccountProofVerifier.sol";
import "@src/proofs/vaults/VaultEscapeProofVerifier.sol";
import "@src/withdrawals/IVaultEscapeProcessor.sol";
import "@src/withdrawals/VaultEscapeProcessor.sol";
import "../common/FixVaultEscapes.sol";
import "forge-std/Test.sol";
import {FixVaultEscapes} from "../common/FixVaultEscapes.sol";
import {FixtureAssets} from "../common/FixtureAssets.sol";
import {FixtureLookupTables} from "../common/FixtureLookupTables.sol";

contract MockAccountVerifier is IAccountProofVerifier {
    bool public shouldVerify;

    function setShouldVerify(bool _shouldVerify) external {
        shouldVerify = _shouldVerify;
    }

    function verify(uint256, address, bytes32[] calldata) external view override returns (bool) {
        return shouldVerify;
    }
}

contract MockVaultVerifier is VaultEscapeProofVerifier {
    bool public shouldVerify;

    constructor(address[63] memory lookupTables) VaultEscapeProofVerifier(lookupTables) {}

    function setShouldVerify(bool _shouldVerify) external {
        shouldVerify = _shouldVerify;
    }

    function verifyEscapeProof(uint256[] calldata) external view override returns (bool) {
        return shouldVerify;
    }
}
