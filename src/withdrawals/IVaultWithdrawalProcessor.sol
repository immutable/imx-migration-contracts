// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "@src/verifiers/accounts/IAccountProofVerifier.sol";
import "@src/verifiers/vaults/IVaultEscapeProofVerifier.sol";

/**
 * @title IVaultEscapeProcessor
 * @notice This interface defines the functions and events for processing vault escape claims and disbursing funds.
 * It includes functions for verifying account proofs, processing claims, and handling errors.
 */
interface IVaultWithdrawalProcessor {
    // @notice AssetNotRegistered is an error thrown when an the asset is not registered in the system.
    // @param assetId The identifier of the asset on Immutable X.
    // @dev This error is thrown when the Immutable X asset ID provided, has no registered association with an asset on zkEVM.
    error AssetNotRegistered(uint256 assetId);

    // @notice FundAlreadyDisbursedForVault is an error thrown if an escape claim is attempted for a vault that has already been disbursed.
    // @param starkKey The Stark key of the user.
    // @param assetId The identifier of the asset in the vault.
    error FundAlreadyDisbursedForVault(uint256 starkKey, uint256 assetId);

    // @notice InsufficientBalance is an error thrown when the contract does not have enough balance to process the disbursal.
    error InsufficientBalance(address asset, uint256 required, uint256 available);

    // @notice FundTransferFailed is an error thrown when the transfer of funds to the recipient fails.
    error FundTransferFailed(address recipient, address asset, uint256 amount);
}
