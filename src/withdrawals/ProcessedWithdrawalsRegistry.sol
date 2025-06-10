// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

/**
 * @title ProcessedWithdrawalsRegistry
 * @notice This contract is used to register processed vault escape claims and associated fund disbursals.
 * It is used to prevent double disbursals of funds.
 */
abstract contract ProcessedWithdrawalsRegistry {
    // @notice ClaimProcessed is an event emitted when a claim is processed.
    // @param starkKey The Stark key of the user.
    // @param assetId The identifier of the asset in the vault.
    // @param claimHash The hash of the claim, which is the keccak256 of the starkKey and assetId.
    event WithdrawalProcessed(uint256 indexed starkKey, uint256 indexed assetId, bytes32 claimHash);

    // @notice WithdrawalAlreadyProcessed is an error thrown when if a claim is attempted to be processed more than once.
    error WithdrawalAlreadyProcessed(uint256 starkKey, uint256 assetId);

    // @notice processedWithdrawals is a mapping that keeps track of processed claims.
    mapping(bytes32 => bool) public processedWithdrawals;

    /*
     * @dev _registerProcessedWithdrawal registers a processed claim.
     * @param starkKey The Stark key of the user.
     * @param assetId The identifier of the asset in the vault.
     * @dev The claim hash is the hash of the starkKey and assetId.
     */
    function _registerProcessedWithdrawal(uint256 starkKey, uint256 assetId) internal {
        bytes32 claimHash = keccak256(abi.encode(starkKey, assetId));
        require(!processedWithdrawals[claimHash], WithdrawalAlreadyProcessed(starkKey, assetId));
        processedWithdrawals[claimHash] = true;
        emit WithdrawalProcessed(starkKey, assetId, claimHash);
    }

    /*
     * @dev isWithdrawalProcessed checks if a claim has been processed.
     * @param starkKey The Stark key of the user.
     * @param assetId The identifier of the asset in the vault.
     * @return bool Returns true if the claim has been processed, false otherwise.
     */
    function isWithdrawalProcessed(uint256 starkKey, uint256 assetId) public view returns (bool) {
        bytes32 claimHash = keccak256(abi.encode(starkKey, assetId));
        return processedWithdrawals[claimHash];
    }
}
