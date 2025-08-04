// Copyright Immutable Pty Ltd 2018 - 2025
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/**
 * @title Maps Immutable X tokens to their corresponding tokens on Immutable zkEVM
 * @notice This contract maintains a mapping of Immutable X tokens to their corresponding tokens on Immutable zkEVM (e.g. USDC on Immutable X to USDC on Immutable zkEVM).
 * @dev While a token on Immutable zkEVM is identified by an address, the token on Immutable X is represented by a token ID and a quantum.
 */
abstract contract TokenMappings {
    /**
     * @dev Associates an Immutable X asset to its corresponding address on Immutable zkEVM.
     * @param assetOnIMX Details of the asset on Immutable X.
     * @param assetAddress Address of the asset on Immutable zkEVM.
     */
    struct AssetDetails {
        ImmutableXAsset assetOnIMX;
        address assetOnZKEVM;
    }

    /**
     * @dev Details of an Immutable X asset
     * @param id The contract ID of the asset on Immutable X.
     * @param quantum The quantum used for the asset on Immutable X.
     */
    struct ImmutableXAsset {
        uint256 id;
        uint256 quantum;
    }

    /**
     * @dev Emitted when a new asset mapping is registered.
     * @param assetId The ID of the asset on Immutable X.
     * @param quantum The quantum used for the asset on Immutable X.
     * @param assetAddress The corresponding address of the asset on Immutable zkEVM.
     */
    event AssetMapped(uint256 indexed assetId, uint256 indexed quantum, address indexed assetAddress);

    /**
     * @dev Emitted when an asset registration fails, because of invalid details.
     * @param reason The reason for the failure.
     */
    error InvalidAssetDetails(string reason);
    /**
     * @dev Emitted when an asset registration fails, because it is already registered.
     */
    error AssetAlreadyRegistered();

    /// @dev The upper bound for valid quantum values.
    // TODO Consider further constraining this value given we know the set of tokens and their quanta that will be migrated. Need to carefully consider the implications of imposing such a constraint, if so.
    uint256 public constant QUANTUM_UPPER_BOUND = 2 ** 128;

    /// @dev Reference to the native asset address on Immutable zkEVM. This aligns with the value used to represent IMX on the zkEVM bridge.
    address public constant NATIVE_IMX_ADDRESS = address(0xfff);

    /// @dev Maps Immutable X asset IDs to their corresponding asset details
    mapping(uint256 assetIdOnIMX => AssetDetails) public assetMappings;

    /**
     * @dev Checks if an asset mapping is registered.
     * @param assetId The Immutable X ID of the asset to check.
     * @return True if the asset is registered, false otherwise.
     */
    function isMapped(uint256 assetId) public view returns (bool) {
        return assetMappings[assetId].assetOnZKEVM != address(0);
    }

    function isMappedToNativeAsset(uint256 assetId) public view returns (bool) {
        return assetMappings[assetId].assetOnZKEVM == NATIVE_IMX_ADDRESS;
    }

    function getMappedAssetAddress(uint256 assetId) public view returns (address) {
        return assetMappings[assetId].assetOnZKEVM;
    }

    function getMappedAssetDetails(uint256 assetId) public view returns (AssetDetails memory) {
        return assetMappings[assetId];
    }

    function getMappedAssetQuantum(uint256 assetId) public view returns (uint256) {
        return assetMappings[assetId].assetOnIMX.quantum;
    }

    function _registerAssetMapping(AssetDetails memory assetDetails) internal {
        ImmutableXAsset memory immutableXAsset = assetDetails.assetOnIMX;
        require(immutableXAsset.id != 0, InvalidAssetDetails("Asset ID cannot be zero"));
        require(immutableXAsset.quantum != 0, InvalidAssetDetails("Quantum cannot be zero"));
        require(immutableXAsset.quantum < QUANTUM_UPPER_BOUND, InvalidAssetDetails("Quantum exceeds upper bound"));

        require(assetDetails.assetOnZKEVM != address(0), InvalidAssetDetails("Asset address cannot be zero"));

        require(!isMapped(immutableXAsset.id), AssetAlreadyRegistered());

        assetMappings[immutableXAsset.id] = assetDetails;
        emit AssetMapped(immutableXAsset.id, immutableXAsset.quantum, assetDetails.assetOnZKEVM);
    }

    function _registerTokenMappings(AssetDetails[] memory assetsDetails) internal {
        require(assetsDetails.length > 0, InvalidAssetDetails("No assets to register"));

        for (uint256 i = 0; i < assetsDetails.length; i++) {
            _registerAssetMapping(assetsDetails[i]);
        }
    }
}
