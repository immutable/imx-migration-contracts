// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "../accounts/IAccountVerifier.sol";
import "../vaults/IVaultProofVerifier.sol";
import {IAccountVerifier} from "../accounts/IAccountVerifier.sol";
import {AssetsRegistry} from "./AssetsRegistry.sol";
import {ClaimsRegistry} from "./ClaimsRegistry.sol";

abstract contract VaultFundDisburser is AssetsRegistry, ClaimsRegistry {
    error InvalidAccountProof();
    error InvalidVaultProof();
    error FundAlreadyDisbursedForVault(uint256 starkKey, uint256 assetId);

    IAccountVerifier public immutable accountVerifier;
    IVaultProofVerifier public immutable vaultVerifier;

    constructor(address _accountVerifier, address _vaultVerifier, uint256[] memory assetIds, address[] memory assets) {
        accountVerifier = IAccountVerifier(_accountVerifier);
        vaultVerifier = IVaultProofVerifier(_vaultVerifier);
        _registerAssetMapping(assetIds, assets);

        _registerAssets(assetIds, assets);
    }

    function _registerAssetMapping(uint256[] memory assetIds, address[] memory assets) private {
        require(assetIds.length > 0 && assets.length > 0, "At least one asset must be registered");
        require(assetIds.length == assets.length, "Asset IDs and asset addresses must have the same length");
    }

    function verifyAndProcessVaultProof(
        uint256 starkKey,
        address ethAddress,
        uint256 assetId,
        bytes32[] calldata accountProof,
        uint256[] calldata vaultProof
    ) external returns (bool) {
        require(!isClaimed(starkKey, assetId), FundAlreadyDisbursedForVault(starkKey, assetId));
        require(_verifyAccountProof(starkKey, ethAddress, accountProof), InvalidAccountProof());
        require(_verifyVaultProof(vaultProof), InvalidVaultProof());

        // TODO: Register the claim
        // TODO: Process fund transfer

        return true;
    }

    function _verifyAccountProof(uint256 starkKey, address ethAddress, bytes32[] calldata proof)
        private
        returns (bool)
    {
        return accountVerifier.verify(starkKey, ethAddress, proof);
    }

    function _verifyVaultProof(uint256[] calldata proof) private returns (bool) {
        return vaultVerifier.verify(proof);
    }

    // TODO: Consider externalising funds management
    receive() external payable {}
}
