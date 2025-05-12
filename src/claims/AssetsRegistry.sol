// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

abstract contract AssetsRegistry {
    // Mapping from asset ID to asset address
    mapping(uint256 => address) public assetsMapping;

    // Event emitted when an asset is added
    event AssetRegistered(uint256 indexed assetId, address indexed assetAddress);

    // TODO: Handle native asset mapping

    // Function to add an asset
    function _registerAsset(uint256 assetId, address assetAddress) internal {
        require(assetAddress != address(0), "Invalid asset address");
        require(assetsMapping[assetId] == address(0), "Asset already exists");

        assetsMapping[assetId] = assetAddress;
        emit AssetRegistered(assetId, assetAddress);
    }

    function _registerAssets(uint256[] memory assetIds, address[] memory assetAddresses) internal {
        require(assetIds.length > 0 && assetAddresses.length > 0, "At least one asset must be added");
        require(assetIds.length == assetAddresses.length, "Asset IDs and addresses must have the same length");

        for (uint256 i = 0; i < assetIds.length; i++) {
            _registerAsset(assetIds[i], assetAddresses[i]);
        }
    }

    function hasMapping(uint256 assetId) public view returns (bool) {
        return assetsMapping[assetId] != address(0);
    }

    function getAssetAddress(uint256 assetId) public view returns (address) {
        return assetsMapping[assetId];
    }
}
