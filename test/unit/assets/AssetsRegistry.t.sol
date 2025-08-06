// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "@src/assets/TokenMappings.sol";
import "forge-std/Test.sol";

contract MockAssetsRegistry is TokenMappings {
    function registerAssetMapping(TokenMappings.AssetMapping memory assetInfo) public {
        _registerAssetMapping(assetInfo);
    }

    function registerAssetMapping(TokenMappings.AssetMapping[] memory assetInfos) public {
        _registerTokenMappings(assetInfos);
    }
}

contract AssetsMappingRegistryTest is Test {
    uint256 public constant TEST_ASSET_ID = 1;
    address public constant TEST_ASSET_ADDRESS = address(0xBEEF);
    uint256 public constant TEST_QUANTUM = 11;

    MockAssetsRegistry public mockRegistry;

    function setUp() public {
        mockRegistry = new MockAssetsRegistry();
    }

    function test_RegisterAssetMapping() public {
        TokenMappings.AssetMapping memory assetInfo =
            _createAssetDetails(TEST_ASSET_ID, TEST_QUANTUM, TEST_ASSET_ADDRESS);

        assertEq(mockRegistry.getZKEVMAddress(TEST_ASSET_ID), address(0));
        assertEq(mockRegistry.getAssetQuantum(TEST_ASSET_ID), 0);
        assertFalse(mockRegistry.isMapped(TEST_ASSET_ID));

        vm.expectEmit(true, true, true, true);
        emit TokenMappings.AssetMapped(TEST_ASSET_ID, TEST_QUANTUM, TEST_ASSET_ADDRESS);
        mockRegistry.registerAssetMapping(assetInfo);

        assertEq(mockRegistry.getZKEVMAddress(TEST_ASSET_ID), TEST_ASSET_ADDRESS);
        assertEq(mockRegistry.getAssetQuantum(TEST_ASSET_ID), TEST_QUANTUM);
        assertTrue(mockRegistry.isMapped(TEST_ASSET_ID));
    }

    function test_RegisterTokenMappings() public {
        TokenMappings.AssetMapping[] memory assetInfos = new TokenMappings.AssetMapping[](2);

        assetInfos[0] = _createAssetDetails(1, 18, address(0xBEEF));
        assetInfos[1] = _createAssetDetails(2, 6, address(0xCAFE));

        vm.expectEmit(true, true, true, true);
        emit TokenMappings.AssetMapped(1, 18, address(0xBEEF));
        vm.expectEmit(true, true, true, true);
        emit TokenMappings.AssetMapped(2, 6, address(0xCAFE));

        mockRegistry.registerAssetMapping(assetInfos);

        assertEq(mockRegistry.getZKEVMAddress(1), address(0xBEEF));
        assertEq(mockRegistry.getAssetQuantum(1), 18);
        assertTrue(mockRegistry.isMapped(1));

        assertEq(mockRegistry.getZKEVMAddress(2), address(0xCAFE));
        assertEq(mockRegistry.getAssetQuantum(2), 6);
        assertTrue(mockRegistry.isMapped(2));
    }

    function test_RevertIf_RegisterAsset_ZeroAssetId() public {
        TokenMappings.AssetMapping memory assetInfo = _createAssetDetails(0, TEST_QUANTUM, TEST_ASSET_ADDRESS);

        vm.expectRevert(abi.encodeWithSelector(TokenMappings.InvalidAssetDetails.selector, "Asset ID cannot be zero"));
        mockRegistry.registerAssetMapping(assetInfo);
    }

    function test_RevertIf_RegisterAsset_ZeroQuantum() public {
        TokenMappings.AssetMapping memory assetInfo = _createAssetDetails(TEST_ASSET_ID, 0, TEST_ASSET_ADDRESS);

        vm.expectRevert(abi.encodeWithSelector(TokenMappings.InvalidAssetDetails.selector, "Quantum cannot be zero"));
        mockRegistry.registerAssetMapping(assetInfo);
    }

    function test_RevertIf_RegisterAsset_QuantumAboveBounds() public {
        TokenMappings.AssetMapping memory assetInfo =
            _createAssetDetails(TEST_ASSET_ID, mockRegistry.QUANTUM_UPPER_BOUND(), TEST_ASSET_ADDRESS);

        vm.expectRevert(
            abi.encodeWithSelector(TokenMappings.InvalidAssetDetails.selector, "Quantum exceeds upper bound")
        );
        mockRegistry.registerAssetMapping(assetInfo);
    }

    function test_RevertIf_RegisterAsset_ZeroAddress() public {
        TokenMappings.AssetMapping memory assetInfo = _createAssetDetails(TEST_ASSET_ID, TEST_QUANTUM, address(0));

        vm.expectRevert(
            abi.encodeWithSelector(TokenMappings.InvalidAssetDetails.selector, "Asset address cannot be zero")
        );
        mockRegistry.registerAssetMapping(assetInfo);
    }

    function test_RevertIf_RegisterAsset_AlreadyRegistered() public {
        TokenMappings.AssetMapping memory assetInfo =
            _createAssetDetails(TEST_ASSET_ID, TEST_QUANTUM, TEST_ASSET_ADDRESS);

        mockRegistry.registerAssetMapping(assetInfo);

        vm.expectRevert(abi.encodeWithSelector(TokenMappings.AssetAlreadyRegistered.selector));
        mockRegistry.registerAssetMapping(assetInfo);
    }

    function test_RevertIf_RegisterAssets_EmptyArray() public {
        TokenMappings.AssetMapping[] memory assetInfos = new TokenMappings.AssetMapping[](0);

        vm.expectRevert(abi.encodeWithSelector(TokenMappings.InvalidAssetDetails.selector, "No assets to register"));
        mockRegistry.registerAssetMapping(assetInfos);
    }

    function test_RegisterAsset_Native() public {
        TokenMappings.AssetMapping memory nativeAsset =
            _createAssetDetails(TEST_ASSET_ID, TEST_QUANTUM, mockRegistry.NATIVE_IMX_ADDRESS());
        TokenMappings.AssetMapping memory nonNativeAsset =
            _createAssetDetails(TEST_ASSET_ID + 1, TEST_QUANTUM, TEST_ASSET_ADDRESS);

        // register both assets
        mockRegistry.registerAssetMapping(nativeAsset);
        mockRegistry.registerAssetMapping(nonNativeAsset);

        address token = mockRegistry.getAssetMapping(TEST_ASSET_ID).tokenOnZKEVM;
        assertTrue(token == mockRegistry.NATIVE_IMX_ADDRESS());
    }

    // Helper functions to create structs more concisely
    function _createImmutableXAsset(uint256 id, uint256 quantum)
        private
        pure
        returns (TokenMappings.ImmutableXToken memory)
    {
        return TokenMappings.ImmutableXToken(id, quantum);
    }

    function _createAssetDetails(uint256 id, uint256 quantum, address zkAddress)
        private
        pure
        returns (TokenMappings.AssetMapping memory)
    {
        return TokenMappings.AssetMapping(_createImmutableXAsset(id, quantum), zkAddress);
    }
}
