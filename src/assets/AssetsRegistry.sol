// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/**
 * @title AssetsRegistry
 * @notice This contract maps assets on Immutable X to their corresponding version on Immutable zkEVM.
 * TODO:
 *   1. Add boundary checks to the assetId and quantum
 *   2. Consider replacing registration (or augmenting validation) with automated derivation of token ID from L1 token address, asset quantum and bridge token mapping
 */
abstract contract AssetsRegistry {
    /**
     * @dev Struct that holds the details of an asset on both Immutable X and Immutable zkEVM.
     * @param assetId The contract ID of the asset on Immutable X.
     * @param quantum The quantum used for the asset on Immutable X.
     * @param assetAddress The corresponding address of the asset on Immutable zkEVM.
     */
    struct AssetDetails {
        uint256 assetId;
        uint256 quantum;
        address assetAddress;
    }

    /**
     * @dev Emitted when a new asset association is registered.
     * @param assetId The ID of the asset on Immutable X.
     * @param quantum The quantum used for the asset on Immutable X.
     * @param assetAddress The corresponding address of the asset on Immutable zkEVM.
     */
    event AssetRegistered(uint256 indexed assetId, uint256 quantum, address indexed assetAddress);

    /**
     * @dev Emitted when an asset registration fails due to invalid details.
     * @param reason The reason for the failure.
     */
    error InvalidAssetDetails(string reason);

    // Placeholder for the native asset address on Immutable zkEVM. Address aligns with value used in zkEVM bridge.
    address public constant NATIVE_IMX_ADDRESS = address(0xfff);

    mapping(uint256 => AssetDetails) public registeredAssets;

    /**
     * @dev Checks if an asset is registered.
     * @param assetId The ID of the asset to check.
     * @return True if the asset is registered, false otherwise.
     */
    function isRegistered(uint256 assetId) public view returns (bool) {
        return registeredAssets[assetId].assetAddress != address(0);
    }

    function isNativeAsset(uint256 assetId) public view returns (bool) {
        return registeredAssets[assetId].assetAddress == NATIVE_IMX_ADDRESS;
    }

    function getAssetAddress(uint256 assetId) public view returns (address) {
        return registeredAssets[assetId].assetAddress;
    }

    function getAssetQuantum(uint256 assetId) public view returns (uint256) {
        return registeredAssets[assetId].quantum;
    }

    function getAssetDetails(uint256 assetId) public view returns (AssetDetails memory) {
        return registeredAssets[assetId];
    }

    function _registerAsset(AssetDetails memory assetDetails) internal {
        require(assetDetails.assetId != 0, InvalidAssetDetails("Asset ID cannot be zero"));
        require(assetDetails.assetAddress != address(0), InvalidAssetDetails("Asset address cannot be zero"));
        require(assetDetails.quantum != 0, InvalidAssetDetails("Quantum cannot be zero"));
        require(!isRegistered(assetDetails.assetId), InvalidAssetDetails("Asset already registered"));
        // TODO: Add further boundary checks to the assetId and quantum

        registeredAssets[assetDetails.assetId] = assetDetails;
        emit AssetRegistered(assetDetails.assetId, assetDetails.quantum, assetDetails.assetAddress);
    }

    function _registerAssets(AssetDetails[] memory assetsDetails) internal {
        require(assetsDetails.length > 0, InvalidAssetDetails("No assets to register"));

        for (uint256 i = 0; i < assetsDetails.length; i++) {
            _registerAsset(assetsDetails[i]);
        }
    }

    function _validateAssetRegistration(uint256 assetId, address assetAddress) private view {
        // TODO: Asset ID can be deterministically derived from the L1 token address and asset type (ERC20, ETH)
        // A more trustless approach could be to register an asset providing the id and L1 token address and quantum,
        // then: we can a) validate that the ID is valid according to the derivation and b) infer teh L2 token address from the bridge's rootToChildToken mapping
        // https://github.com/starkware-libs/starkex-contracts/blob/f4ed79bb04b56d587618c24312e87d81e4efc56b/scalable-dex/contracts/src/interactions/TokenAssetData.sol#L9
    }
}
