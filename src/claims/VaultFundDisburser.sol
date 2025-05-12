// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "../accounts/IAccountVerifier.sol";
import "../vaults/IVaultProofVerifier.sol";
import {IAccountVerifier} from "../accounts/IAccountVerifier.sol";

abstract contract VaultFundDisburser {
    error InvalidAccountProof();
    error InvalidVaultProof();
    error FundAlreadyDisbursedForVault(uint256 starkKey, uint256 assetId);

    IAccountVerifier public immutable accountVerifier;
    IVaultProofVerifier public immutable vaultVerifier;
    mapping(bytes32 => bool) public processedClaims;
    mapping(uint256 => address) public assetsMapping;

    constructor(address _accountVerifier, address _vaultVerifier) {
        accountVerifier = IAccountVerifier(_accountVerifier);
        vaultVerifier = IVaultProofVerifier(_vaultVerifier);
    }

    function verifyAndProcessDisbursal(
        uint256 starkKey,
        address ethAddress,
        uint256 assetId,
        bytes32[] calldata accountProof,
        uint256[] calldata vaultProof
    ) external returns (bool) {
        require(!isDisbursed(starkKey, assetId), FundAlreadyDisbursedForVault(starkKey, assetId));
        require(_verifyAccountProof(starkKey, ethAddress, accountProof), InvalidAccountProof());
        require(_verifyVaultProof(vaultProof), InvalidVaultProof());

        // TODO: Register the claim
        // TODO: Process fund transfer

        return true;
    }

    function isDisbursed(uint256 starkKey, uint256 assetId) public view returns (bool) {
        // TODO: Verify parameters
        bytes32 claimHash = keccak256(abi.encode(starkKey, assetId));
        return processedClaims[claimHash];
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
