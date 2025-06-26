// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/**
 * @title IVaultEscapeProcessor
 * @notice This interface defines the functions and events for processing vault escape claims and disbursing funds.
 * It includes functions for verifying account proofs, processing claims, and handling errors.
 */
interface IVaultWithdrawalProcessor {
    event WithdrawalProcessed(
        uint256 indexed starkKey, uint256 indexed assetId, address recipient, uint256 amount, address assetAddress
    );

    error VaultRootOverrideNotAllowed();

    // @notice AssetNotRegistered is an error thrown when an the asset is not registered in the system.
    // @param assetId The identifier of the asset on Immutable X.
    // @dev This error is thrown when the Immutable X asset ID provided, has no registered association with an asset on zkEVM.
    error AssetNotRegistered(uint256 assetId);

    error ZeroAddress();
}
