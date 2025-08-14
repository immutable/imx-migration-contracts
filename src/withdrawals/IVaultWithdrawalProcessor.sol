// Copyright Immutable Pty Ltd 2018 - 2025
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/**
 * @title IVaultWithdrawalProcessor
 * @notice This interface defines the functions and events for processing vault escape claims and disbursing funds.
 * @dev It includes functions for verifying account proofs, processing claims, and handling errors.
 */
abstract contract IVaultWithdrawalProcessor {
    /**
     * @notice Emitted when a withdrawal is successfully processed
     * @param starkKey The Stark key of the account making the withdrawal
     * @param assetId The identifier of the asset being withdrawn
     * @param recipient The address receiving the withdrawn funds
     * @param amount The amount of tokens withdrawn
     * @param assetAddress The address of the asset contract on zkEVM
     */
    event WithdrawalProcessed(
        uint256 indexed starkKey, uint256 indexed assetId, address recipient, uint256 amount, address assetAddress
    );

    /// @notice Thrown when a zero address is provided where a valid address is required
    error ZeroAddress();

    /**
     * @notice Emitted when a withdrawal claim is processed
     * @param starkKey The Stark key of the user
     * @param assetId The identifier of the asset in the vault
     * @param claimHash The hash of the claim, which is the keccak256 of the starkKey and assetId
     */
    event WithdrawalProcessed(uint256 indexed starkKey, uint256 indexed assetId, bytes32 claimHash);

    /// @notice Thrown when attempting to process a withdrawal that has already been processed
    /// @param starkKey The Stark key of the user
    /// @param assetId The identifier of the asset in the vault
    error WithdrawalAlreadyProcessed(uint256 starkKey, uint256 assetId);

    /// @notice Mapping that keeps track of processed withdrawal claims
    /// @dev The key is the keccak256 hash of (starkKey, assetId)
    mapping(bytes32 => bool) public processedWithdrawals;

    function verifyAndProcessWithdrawal(
        address receiverAddress,
        bytes32[] calldata accountProof,
        uint256[] calldata vaultProof
    ) external virtual;

    /**
     * @notice Checks if a withdrawal claim has been processed
     * @param starkKey The Stark key of the user
     * @param assetId The identifier of the asset in the vault
     * @return True if the claim has been processed, false otherwise
     */
    function isWithdrawalProcessed(uint256 starkKey, uint256 assetId) public view returns (bool) {
        bytes32 claimHash = keccak256(abi.encode(starkKey, assetId));
        return processedWithdrawals[claimHash];
    }

    /**
     * @notice Internal function to register a processed withdrawal claim
     * @dev The claim hash is computed as keccak256(starkKey, assetId)
     * @param starkKey The Stark key of the user
     * @param assetId The identifier of the asset in the vault
     */
    function _registerProcessedWithdrawal(uint256 starkKey, uint256 assetId) internal {
        bytes32 claimHash = keccak256(abi.encode(starkKey, assetId));
        require(!processedWithdrawals[claimHash], WithdrawalAlreadyProcessed(starkKey, assetId));
        processedWithdrawals[claimHash] = true;
        emit WithdrawalProcessed(starkKey, assetId, claimHash);
    }
}
