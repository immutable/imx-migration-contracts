// Copyright Immutable Pty Ltd 2018 - 2025
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/**
 * @title Token Mapping Registry
 * @notice This contract maintains a registry of token mappings of Immutable X tokens to their corresponding tokens on Immutable zkEVM (e.g. USDC on Immutable X to USDC on Immutable zkEVM).
 * @dev While a token on Immutable zkEVM is identified by an address, the token on Immutable X is represented by a token ID and a quantum.
 * @dev Note that two different assets on Immutable X, with different IDs, can be mapped to the same address on Immutable zkEVM. The OMI token is the only known example of this case, in mainnet.
 * @dev The contract is optimised for fetching asset details by Immutable X asset ID.
 * @dev An asset can only be registered once, and the contract will throw an error if an attempt is made to register an already registered asset.
 */
abstract contract TokenMappings {
    /**
     * @dev Encapsulates details of an Immutable X ERC-20 asset.
     */
    struct ImmutableXToken {
        uint256 id;
        uint256 quantum;
    }

    /**
     * @dev Encapsulates details of an asset as its represented on Immutable X and Immutable zkEVM.
     */
    struct AssetMapping {
        ImmutableXToken tokenOnIMX;
        address tokenOnZKEVM;
    }

    /**
     * @dev Emitted when a new asset mapping is registered.
     * @param idOnX The token ID of the asset on Immutable X.
     * @param quantumOnX The quantum of the asset on Immutable X.
     * @param addressOnZKEVM The corresponding address of the asset on Immutable zkEVM.
     */
    event AssetMapped(uint256 indexed idOnX, uint256 indexed quantumOnX, address indexed addressOnZKEVM);

    /**
     * @notice Thrown when provided details of an asset are invalid, during registration.
     * @param reason The specific reason for the failure.
     */
    error InvalidAssetDetails(string reason);

    /**
     * @notice Thrown when an asset is already registered. An asset can only be registered once.
     */
    error AssetAlreadyRegistered();

    /// @dev The upper bound for valid quantum values.
    uint256 public constant QUANTUM_UPPER_BOUND = 2 ** 128;

    /// @dev Reference to the native asset on Immutable zkEVM, based on the value used to represent IMX on the zkEVM bridge on L2.
    address public constant NATIVE_IMX_ADDRESS = address(0xfff);

    /// @notice Mapping of Immutable X asset IDs to their corresponding asset details
    mapping(uint256 idOnX => AssetMapping) public assetMappings;

    /**
     * @notice Checks if a given Immutable X asset ID is mapped to an asset on Immutable zkEVM.
     * @param assetId The Immutable X ID of the asset to check.
     * @return True if the asset is registered, false otherwise.
     */
    function isMapped(uint256 assetId) public view returns (bool) {
        return assetMappings[assetId].tokenOnZKEVM != address(0);
    }

    /**
     * @notice For a given Immutable X asset ID, retrieve the details of the asset mapping, if registered.
     * @param assetId The Immutable X ID of the asset.
     * @return The details of the asset association if it exists; otherwise, returns an empty AssetAssociation struct.
     */
    function getAssetMapping(uint256 assetId) public view returns (AssetMapping memory) {
        return assetMappings[assetId];
    }

    /**
     * @notice For a given Immutable X asset ID, get the corresponding token address on Immutable zkEVM.
     * @param assetId The Immutable X ID of the asset.
     * @return The address of the asset on Immutable zkEVM, if it exists; otherwise, returns the zero address.
     */
    function getZKEVMAddress(uint256 assetId) public view returns (address) {
        return assetMappings[assetId].tokenOnZKEVM;
    }

    /**
     * @notice For a given Immutable X asset ID, get the quantum of the asset on Immutable X.
     * @param assetId The Immutable X ID of the asset.
     * @return The quantum of the asset on Immutable X, if it exists; otherwise, returns zero.
     */
    function getAssetQuantum(uint256 assetId) public view returns (uint256) {
        return assetMappings[assetId].tokenOnIMX.quantum;
    }

    /**
     * @notice Registers a new asset mapping.
     * @dev This function is internal and can be called by derived contracts to register a new asset mapping.
     * @param assetDetails The details of the asset to register, including its Immutable X ID, quantum, and corresponding zkEVM address.
     */
    function _registerAssetMapping(AssetMapping memory assetDetails) internal {
        ImmutableXToken memory immutableXAsset = assetDetails.tokenOnIMX;

        require(immutableXAsset.id != 0, InvalidAssetDetails("Asset ID cannot be zero"));
        require(immutableXAsset.quantum != 0, InvalidAssetDetails("Quantum cannot be zero"));
        require(immutableXAsset.quantum < QUANTUM_UPPER_BOUND, InvalidAssetDetails("Quantum exceeds upper bound"));

        require(assetDetails.tokenOnZKEVM != address(0), InvalidAssetDetails("Asset address cannot be zero"));

        require(assetMappings[immutableXAsset.id].tokenOnZKEVM == address(0), AssetAlreadyRegistered());

        assetMappings[immutableXAsset.id] = assetDetails;
        emit AssetMapped(immutableXAsset.id, immutableXAsset.quantum, assetDetails.tokenOnZKEVM);
    }

    /**
     * @notice Registers multiple asset mappings.
     * @dev This function is internal and can be called by derived contracts to register multiple asset mappings at once.
     * @param assetsDetails An array of AssetMapping structs containing the details of the assets to register.
     */
    function _registerTokenMappings(AssetMapping[] memory assetsDetails) internal {
        require(assetsDetails.length > 0, InvalidAssetDetails("No assets to register"));

        for (uint256 i = 0; i < assetsDetails.length; i++) {
            _registerAssetMapping(assetsDetails[i]);
        }
    }
}
