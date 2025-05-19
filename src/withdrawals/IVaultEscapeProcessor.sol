// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "../proofs/accounts/IAccountProofVerifier.sol";
import "../proofs/vaults/IVaultEscapeProofVerifier.sol";

/**
 * @title IVaultEscapeProcessor
 * @notice This interface defines the functions and events for processing vault escape claims and disbursing funds.
 * It includes functions for verifying account proofs, processing claims, and handling errors.
 */
interface IVaultEscapeProcessor {
    // @notice InvalidVaultRoot is an error thrown when the provided vault root is invalid.
    // @param root The root of the vault.
    // @param reason The reason why the vault root is invalid.
    error InvalidVaultRoot(uint256 root, string reason);

    // @notice AssetNotRegistered is an error thrown when an the asset is not registered in the system.
    // @param assetId The identifier of the asset on Immutable X.
    // @dev This error is thrown when the Immutable X asset ID provided, has no registered association with an asset on zkEVM.
    error AssetNotRegistered(uint256 assetId);

    // @notice FundAlreadyDisbursedForVault is an error thrown if an escape claim is attempted for a vault that has already been disbursed.
    // @param starkKey The Stark key of the user.
    // @param assetId The identifier of the asset in the vault.
    error FundAlreadyDisbursedForVault(uint256 starkKey, uint256 assetId);

    // @notice InsufficientContractBalance is an error thrown when the contract does not have enough balance to process the disbursal.
    error InsufficientContractBalance(address asset, uint256 required, uint256 available);

    // @notice TransferFailed is an error thrown when the transfer of funds to the recipient fails.
    error TransferFailed(address recipient, address asset, uint256 amount);

    // @notice InvalidVaultProof is an error thrown when the provided vault proof is invalid.
    // @param reason The reason why the vault proof is invalid.
    // TODO: Consider adding specific error types for common failure scenarios
    error InvalidVaultProof(string reason);

    // @notice InvalidAccountProof is an error thrown when the provided account proof is invalid.
    // @param starkKey The Stark key of the user.
    // @param ethAddress The associated Ethereum address of the user.
    error InvalidAccountProof(uint256 starkKey, address ethAddress);
}
