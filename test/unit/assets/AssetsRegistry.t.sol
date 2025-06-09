// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "@src/assets/AssetMappingRegistry.sol";
import "forge-std/Test.sol";

contract MockAssetsRegistry is AssetMappingRegistry {
    function registerAssetMapping(AssetMappingRegistry.AssetDetails memory assetInfo) public {
        _registerAssetMapping(assetInfo);
    }

    function registerAssetMapping(AssetMappingRegistry.AssetDetails[] memory assetInfos) public {
        _registerAssetMappings(assetInfos);
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
        AssetMappingRegistry.AssetDetails memory assetInfo =
            _createAssetDetails(TEST_ASSET_ID, TEST_QUANTUM, TEST_ASSET_ADDRESS);

        assertEq(mockRegistry.getMappedAssetAddress(TEST_ASSET_ID), address(0));
        assertEq(mockRegistry.getMappedAssetQuantum(TEST_ASSET_ID), 0);
        assertFalse(mockRegistry.isMapped(TEST_ASSET_ID));

        vm.expectEmit(true, true, true, true);
        emit AssetMappingRegistry.AssetMapped(TEST_ASSET_ID, TEST_QUANTUM, TEST_ASSET_ADDRESS);
        mockRegistry.registerAssetMapping(assetInfo);

        assertEq(mockRegistry.getMappedAssetAddress(TEST_ASSET_ID), TEST_ASSET_ADDRESS);
        assertEq(mockRegistry.getMappedAssetQuantum(TEST_ASSET_ID), TEST_QUANTUM);
        assertTrue(mockRegistry.isMapped(TEST_ASSET_ID));
    }

    function test_RegisterAssetMappings() public {
        AssetMappingRegistry.AssetDetails[] memory assetInfos = new AssetMappingRegistry.AssetDetails[](2);

        assetInfos[0] = _createAssetDetails(1, 18, address(0xBEEF));
        assetInfos[1] = _createAssetDetails(2, 6, address(0xCAFE));

        vm.expectEmit(true, true, true, true);
        emit AssetMappingRegistry.AssetMapped(1, 18, address(0xBEEF));
        vm.expectEmit(true, true, true, true);
        emit AssetMappingRegistry.AssetMapped(2, 6, address(0xCAFE));

        mockRegistry.registerAssetMapping(assetInfos);

        assertEq(mockRegistry.getMappedAssetAddress(1), address(0xBEEF));
        assertEq(mockRegistry.getMappedAssetQuantum(1), 18);
        assertTrue(mockRegistry.isMapped(1));

        assertEq(mockRegistry.getMappedAssetAddress(2), address(0xCAFE));
        assertEq(mockRegistry.getMappedAssetQuantum(2), 6);
        assertTrue(mockRegistry.isMapped(2));
    }

    function test_RevertIf_RegisterAsset_ZeroAssetId() public {
        AssetMappingRegistry.AssetDetails memory assetInfo = _createAssetDetails(0, TEST_QUANTUM, TEST_ASSET_ADDRESS);

        vm.expectRevert(
            abi.encodeWithSelector(AssetMappingRegistry.InvalidAssetDetails.selector, "Asset ID cannot be zero")
        );
        mockRegistry.registerAssetMapping(assetInfo);
    }

    function test_RevertIf_RegisterAsset_ZeroQuantum() public {
        AssetMappingRegistry.AssetDetails memory assetInfo = _createAssetDetails(TEST_ASSET_ID, 0, TEST_ASSET_ADDRESS);

        vm.expectRevert(
            abi.encodeWithSelector(AssetMappingRegistry.InvalidAssetDetails.selector, "Quantum cannot be zero")
        );
        mockRegistry.registerAssetMapping(assetInfo);
    }

    function test_RevertIf_RegisterAsset_QuantumAboveBounds() public {
        AssetMappingRegistry.AssetDetails memory assetInfo =
            _createAssetDetails(TEST_ASSET_ID, mockRegistry.QUANTUM_UPPER_BOUND(), TEST_ASSET_ADDRESS);

        vm.expectRevert(
            abi.encodeWithSelector(AssetMappingRegistry.InvalidAssetDetails.selector, "Quantum exceeds upper bound")
        );
        mockRegistry.registerAssetMapping(assetInfo);
    }

    function test_RevertIf_RegisterAsset_ZeroAddress() public {
        AssetMappingRegistry.AssetDetails memory assetInfo =
            _createAssetDetails(TEST_ASSET_ID, TEST_QUANTUM, address(0));

        vm.expectRevert(
            abi.encodeWithSelector(AssetMappingRegistry.InvalidAssetDetails.selector, "Asset address cannot be zero")
        );
        mockRegistry.registerAssetMapping(assetInfo);
    }

    function test_RevertIf_RegisterAsset_AlreadyRegistered() public {
        AssetMappingRegistry.AssetDetails memory assetInfo =
            _createAssetDetails(TEST_ASSET_ID, TEST_QUANTUM, TEST_ASSET_ADDRESS);

        mockRegistry.registerAssetMapping(assetInfo);

        vm.expectRevert(abi.encodeWithSelector(AssetMappingRegistry.AssetAlreadyRegistered.selector));
        mockRegistry.registerAssetMapping(assetInfo);
    }

    function test_RevertIf_RegisterAssets_EmptyArray() public {
        AssetMappingRegistry.AssetDetails[] memory assetInfos = new AssetMappingRegistry.AssetDetails[](0);

        vm.expectRevert(
            abi.encodeWithSelector(AssetMappingRegistry.InvalidAssetDetails.selector, "No assets to register")
        );
        mockRegistry.registerAssetMapping(assetInfos);
    }

    function test_RegisterAsset_Native() public {
        AssetMappingRegistry.AssetDetails memory nativeAsset =
            _createAssetDetails(TEST_ASSET_ID, TEST_QUANTUM, mockRegistry.NATIVE_IMX_ADDRESS());
        AssetMappingRegistry.AssetDetails memory nonNativeAsset =
            _createAssetDetails(TEST_ASSET_ID + 1, TEST_QUANTUM, TEST_ASSET_ADDRESS);

        // register both assets
        mockRegistry.registerAssetMapping(nativeAsset);
        mockRegistry.registerAssetMapping(nonNativeAsset);

        assertTrue(mockRegistry.isMappedToNativeAsset(TEST_ASSET_ID));
        assertFalse(mockRegistry.isMappedToNativeAsset(TEST_ASSET_ID + 1));
    }

    // Helper functions to create structs more concisely
    function _createImmutableXAsset(uint256 id, uint256 quantum)
        private
        pure
        returns (AssetMappingRegistry.ImmutableXAsset memory)
    {
        return AssetMappingRegistry.ImmutableXAsset(id, quantum);
    }

    function _createAssetDetails(uint256 id, uint256 quantum, address zkAddress)
        private
        pure
        returns (AssetMappingRegistry.AssetDetails memory)
    {
        return AssetMappingRegistry.AssetDetails(_createImmutableXAsset(id, quantum), zkAddress);
    }
}
