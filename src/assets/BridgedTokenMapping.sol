// Copyright Immutable Pty Ltd 2018 - 2025
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/**
 * @title Map Immutable X and Immutable zkEVM Tokens
 * @notice This contract maintains a mappings of Immutable X tokens to their corresponding Immutable zkEVM tokens (e.g. USDC on Immutable X to USDC on Immutable zkEVM).
 * @dev The tokens on both networks are bridged versions of the same original asset on Ethereum.
 * @dev While a token on Immutable zkEVM is identified by an address, the token on Immutable X is represented by a token ID and a quantum.
 * @dev The same token on Ethereum, could have multiple bridged versions with different IDs and quanta on Immutable X.
 *      This is not the case on Immutable zkEVM, where each token is represented by a single address.
 *      Hence, multiple Immutable X assets can be mapped to a single Immutable zkEVM token address.
 * @dev An asset can only be registered once, and the contract will throw an error if an attempt is made to register an already registered asset.
 */
abstract contract BridgedTokenMapping {
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
    struct TokenMapping {
        ImmutableXToken tokenOnIMX;
        address tokenOnZKEVM;
    }

    /**
     * @dev Emitted when a new token mapping is registered.
     * @param idOnX The token ID of the asset on Immutable X.
     * @param quantumOnX The quantum of the asset on Immutable X.
     * @param addressOnZKEVM The corresponding address of the asset on Immutable zkEVM.
     */
    event TokenMappingAdded(uint256 indexed idOnX, uint256 indexed quantumOnX, address indexed addressOnZKEVM);

    /**
     * @notice Thrown when the details provided when registering an asset are invalid.
     * @param reason The specific reason for the failure.
     */
    error InvalidTokenDetails(string reason);

    /**
     * @notice Thrown when an asset, as identified by its token ID on Immutable X, is already registered.
     * @dev An Immutable X asset can only be registered once. However, a token on Immutable zkEVM can correspond to multiple Immutable X assets, as long as they have different IDs.
     */
    error TokenAlreadyMapped();

    /// @notice Thrown when an asset is not registered in the system
    /// @param assetId The identifier of the asset on Immutable X
    /// @dev This error is thrown when the Immutable X asset ID provided has no registered association with an asset on zkEVM
    error AssetNotRegistered(uint256 assetId);

    /// @dev The upper bound for valid quantum values.
    uint256 public constant QUANTUM_UPPER_BOUND = 2 ** 128;

    /// @dev Reference to the native asset on Immutable zkEVM, based on the value used to represent IMX on the zkEVM bridge on L2.
    address public constant NATIVE_IMX_ADDRESS = address(0xfff);

    /// @notice Mapping of Immutable X asset IDs to their corresponding asset details
    mapping(uint256 idOnX => TokenMapping) public assetMappings;

    /**
     * @notice Checks if a given Immutable X asset ID is mapped to an asset on Immutable zkEVM.
     * @param assetId The Immutable X ID of the asset to check.
     * @return True if the asset is registered, false otherwise.
     */
    function isMapped(uint256 assetId) external view returns (bool) {
        return assetMappings[assetId].tokenOnZKEVM != address(0);
    }

    /**
     * @notice For a given Immutable X asset ID, retrieve the details of the asset mapping, if registered.
     * @param assetId The Immutable X ID of the asset.
     * @return The details of the asset association if it exists; otherwise, returns an empty TokenAssociation struct.
     */
    function getTokenMapping(uint256 assetId) external view returns (TokenMapping memory) {
        return assetMappings[assetId];
    }

    /**
     * @notice For a given Immutable X asset ID, get the corresponding token address on Immutable zkEVM.
     * @param assetId The Immutable X ID of the asset.
     * @return The address of the asset on Immutable zkEVM, if it exists; otherwise, returns the zero address.
     */
    function getZKEVMAddress(uint256 assetId) external view returns (address) {
        return assetMappings[assetId].tokenOnZKEVM;
    }

    /**
     * @notice For a given Immutable X asset ID, get the quantum of the asset on Immutable X.
     * @param assetId The Immutable X ID of the asset.
     * @return The quantum of the asset on Immutable X, if it exists; otherwise, returns zero.
     */
    function getQuantum(uint256 assetId) external view returns (uint256) {
        return assetMappings[assetId].tokenOnIMX.quantum;
    }

    /**
     * @notice Registers a new asset mapping.
     * @dev This function is internal and can be called by derived contracts to register a new asset mapping.
     * @param tokenMapping The details of the asset to register, including its Immutable X ID, quantum, and corresponding zkEVM address.
     */
    function _registerTokenMapping(TokenMapping memory tokenMapping) internal {
        ImmutableXToken memory tokenOnX = tokenMapping.tokenOnIMX;

        require(tokenOnX.id != 0, InvalidTokenDetails("Asset ID cannot be zero"));
        require(tokenOnX.quantum != 0 && tokenOnX.quantum < QUANTUM_UPPER_BOUND, InvalidTokenDetails("Invalid quantum"));
        require(tokenMapping.tokenOnZKEVM != address(0), InvalidTokenDetails("Asset address cannot be zero"));
        require(assetMappings[tokenOnX.id].tokenOnZKEVM == address(0), TokenAlreadyMapped());

        assetMappings[tokenOnX.id] = tokenMapping;
        emit TokenMappingAdded(tokenOnX.id, tokenOnX.quantum, tokenMapping.tokenOnZKEVM);
    }

    /**
     * @notice Registers multiple asset mappings.
     * @dev This function is internal and can be called by derived contracts to register multiple asset mappings at once.
     * @param assets An array of TokenAssociation structs containing the details of the assets to register.
     */
    function _registerTokenMappings(TokenMapping[] memory assets) internal {
        require(assets.length > 0, InvalidTokenDetails("No assets to register"));

        for (uint256 i = 0; i < assets.length; i++) {
            _registerTokenMapping(assets[i]);
        }
    }

    function registerTokenMappings(TokenMapping[] memory assetsDetails) external virtual;
}
