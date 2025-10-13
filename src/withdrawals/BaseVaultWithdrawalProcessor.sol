// Copyright Immutable Pty Ltd 2018 - 2025
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/**
 * @title BaseVaultWithdrawalProcessor
 * @dev Mechanism for processing vault withdrawals involves the following key steps:
 *     1. Verifying a vault proof against a verified vault root from the L1 StarkExchange bridge contract on Ethereum.
 *     2. Validating an account proof to ensure the provided Ethereum address corresponds to the user's Stark key for a given vault.
 *     3. Disbursing the full quantized balance of the asset to the specified recipient address.
 */
abstract contract BaseVaultWithdrawalProcessor {
    /**
     * @notice Emitted when a withdrawal is successfully processed
     * @param starkKey The Stark key of the vault owner
     * @param recipient The zkEVM address associated with the Stark key
     * @param assetId The token identifier of the asset withdrawn
     * @param token The token address of the asset
     * @param amount The un-quantized amount of tokens withdrawn
     */
    event WithdrawalProcessed(
        uint256 indexed starkKey, address recipient, uint256 indexed assetId, address indexed token, uint256 amount
    );

    /// @notice Thrown when attempting to verify a proof without a vault root being set
    error VaultRootNotSet();

    error ZeroAddress();

    /**
     * @notice Thrown when attempting to process a withdrawal that has already been processed
     * @param starkKey The Stark key of the user
     * @param assetId The identifier of the asset in the vault
     */
    error WithdrawalAlreadyProcessed(uint256 starkKey, uint256 assetId);

    /// @notice Mapping that keeps track of processed vault withdrawals
    /// @dev The key is the keccak256 hash of (starkKey, assetId), which uniquely identify a vault
    mapping(bytes32 => bool) public processedWithdrawals;

    /**
     * @notice Verifies proofs and processes a withdrawal for a vault
     * @dev This function can only be called once the trusted vault root and account root have been set
     * @dev The function performs the following steps:
     *      1. Validates the stark key associated with the vault is associated with the receiverAddress, using the provided account proof and stored account root.
     *      2. Validates the vault escape proof is valid against the stored vault root
     *      3. Disburses the full quantized balance of the asset to the receiverAddress
     * @dev This function only disburses full amounts for a vault and not partial claims
     * @param receiver The Ethereum address of the vault owner that will receive the funds
     * @param accountProof The account proof to verify that the vault owner's stark key maps to the provided eth address
     * @param vaultProof The vault proof to verify that the vault is valid
     */
    function verifyAndProcessWithdrawal(
        address receiver,
        bytes32[] calldata accountProof,
        uint256[] calldata vaultProof
    ) external virtual;

    /**
     * @notice Checks if a vault withdrawal has already been processed
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
    }
}
