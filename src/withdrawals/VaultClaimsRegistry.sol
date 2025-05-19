// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/**
 * @title VaultClaimsRegistry
 * @notice This contract is used to register processed vault escape claims and associated fund disbursals.
 * It is used to prevent double disbursals of funds.
 */
abstract contract VaultClaimsRegistry {
    // @notice ClaimProcessed is an event emitted when a claim is processed.
    // @param starkKey The Stark key of the user.
    // @param assetId The identifier of the asset in the vault.
    // @param claimHash The hash of the claim, which is the keccak256 of the starkKey and assetId.
    event ClaimProcessed(uint256 starkKey, uint256 assetId, bytes32 indexed claimHash);

    // @notice processedClaims is a mapping that keeps track of processed claims.
    mapping(bytes32 => bool) public processedClaims;

    /*
     * @notice _registerProcessedClaim registers a processed claim.
     * @param starkKey The Stark key of the user.
     * @param assetId The identifier of the asset in the vault.
     * @dev The claim hash is the hash of the starkKey and assetId.
     */
    function _registerProcessedClaim(uint256 starkKey, uint256 assetId) internal {
        bytes32 claimHash = keccak256(abi.encode(starkKey, assetId));
        require(!processedClaims[claimHash], "Claim already exists");
        processedClaims[claimHash] = true;
        emit ClaimProcessed(starkKey, assetId, claimHash);
    }

    /*
     * @notice isClaimProcessed checks if a claim has been processed.
     * @param starkKey The Stark key of the user.
     * @param assetId The identifier of the asset in the vault.
     * @return bool Returns true if the claim has been processed, false otherwise.
     */
    function isClaimProcessed(uint256 starkKey, uint256 assetId) public view returns (bool) {
        bytes32 claimHash = keccak256(abi.encode(starkKey, assetId));
        return processedClaims[claimHash];
    }
}
