// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "@src/assets/AssetMappingRegistry.sol";
import "forge-std/Test.sol";

contract TestAssetsRegistry is AssetMappingRegistry {
    function registerAsset(AssetMappingRegistry.AssetDetails memory assetInfo) public {
        _registerAssetMapping(assetInfo);
    }

    function registerAssets(AssetMappingRegistry.AssetDetails[] memory assetInfos) public {
        _registerAssetMappings(assetInfos);
    }
}

contract AssetsRegistryTest is Test {
    TestAssetsRegistry public registry;

    uint256 public constant TEST_ASSET_ID = 1;
    address public constant TEST_ASSET_ADDRESS = address(0xBEEF);
    uint256 public constant TEST_QUANTUM = 1e11;

    function setUp() public {
        registry = new TestAssetsRegistry();
    }

    function test_RegisterAsset() public {
        AssetMappingRegistry.ImmutableXAsset memory imxAsset =
            AssetMappingRegistry.ImmutableXAsset({id: TEST_ASSET_ID, quantum: TEST_QUANTUM});
        AssetMappingRegistry.AssetDetails memory assetInfo =
            AssetMappingRegistry.AssetDetails({assetOnIMX: imxAsset, assetOnZKEVM: TEST_ASSET_ADDRESS});

        vm.expectEmit(true, true, true, true);
        emit AssetMappingRegistry.AssetMapped(TEST_ASSET_ID, TEST_QUANTUM, TEST_ASSET_ADDRESS);
        registry.registerAsset(assetInfo);

        assertEq(registry.getMappedAssetAddress(TEST_ASSET_ID), TEST_ASSET_ADDRESS);
        assertEq(registry.getAssetQuantum(TEST_ASSET_ID), TEST_QUANTUM);
        assertTrue(registry.isMapped(TEST_ASSET_ID));
    }

    function test_RegisterAssets() public {
        AssetMappingRegistry.AssetDetails[] memory assetInfos = new AssetMappingRegistry.AssetDetails[](2);

        assetInfos[0] =
            AssetMappingRegistry.AssetDetails(AssetMappingRegistry.ImmutableXAsset(1, 1e18), address(0xBEEF));
        assetInfos[1] = AssetMappingRegistry.AssetDetails(AssetMappingRegistry.ImmutableXAsset(2, 1e6), address(0xCAFE));

        vm.expectEmit(true, true, true, true);
        emit AssetMappingRegistry.AssetMapped(1, 1e18, address(0xBEEF));
        vm.expectEmit(true, true, true, true);
        emit AssetMappingRegistry.AssetMapped(2, 1e6, address(0xCAFE));

        registry.registerAssets(assetInfos);

        assertEq(registry.getMappedAssetAddress(1), address(0xBEEF));
        assertEq(registry.getAssetQuantum(1), 1e18);
        assertEq(registry.getMappedAssetAddress(2), address(0xCAFE));
        assertEq(registry.getAssetQuantum(2), 1e6);
    }

    function test_RegisterAsset_ZeroAssetId() public {
        AssetMappingRegistry.AssetDetails memory assetInfo =
            AssetMappingRegistry.AssetDetails(AssetMappingRegistry.ImmutableXAsset(0, TEST_QUANTUM), TEST_ASSET_ADDRESS);

        vm.expectRevert(
            abi.encodeWithSelector(AssetMappingRegistry.InvalidAssetDetails.selector, "Asset ID cannot be zero")
        );
        registry.registerAsset(assetInfo);
    }

    function test_RegisterAsset_ZeroAddress() public {
        AssetMappingRegistry.AssetDetails memory assetInfo = AssetMappingRegistry.AssetDetails(
            AssetMappingRegistry.ImmutableXAsset(TEST_ASSET_ID, TEST_QUANTUM), address(0)
        );

        vm.expectRevert(
            abi.encodeWithSelector(AssetMappingRegistry.InvalidAssetDetails.selector, "Asset address cannot be zero")
        );
        registry.registerAsset(assetInfo);
    }

    function test_RegisterAsset_ZeroQuantum() public {
        AssetMappingRegistry.AssetDetails memory assetInfo = AssetMappingRegistry.AssetDetails(
            AssetMappingRegistry.ImmutableXAsset(TEST_ASSET_ID, 0), TEST_ASSET_ADDRESS
        );

        vm.expectRevert(
            abi.encodeWithSelector(AssetMappingRegistry.InvalidAssetDetails.selector, "Quantum cannot be zero")
        );
        registry.registerAsset(assetInfo);
    }

    function test_RegisterAsset_DuplicateAssetId() public {
        AssetMappingRegistry.AssetDetails memory assetInfo = AssetMappingRegistry.AssetDetails(
            AssetMappingRegistry.ImmutableXAsset(TEST_ASSET_ID, TEST_QUANTUM), TEST_ASSET_ADDRESS
        );

        registry.registerAsset(assetInfo);

        vm.expectRevert(
            abi.encodeWithSelector(AssetMappingRegistry.InvalidAssetDetails.selector, "Asset already registered")
        );
        registry.registerAsset(assetInfo);
    }

    function test_RegisterAssets_EmptyArrays() public {
        AssetMappingRegistry.AssetDetails[] memory assetInfos = new AssetMappingRegistry.AssetDetails[](0);

        vm.expectRevert(
            abi.encodeWithSelector(AssetMappingRegistry.InvalidAssetDetails.selector, "No assets to register")
        );
        registry.registerAssets(assetInfos);
    }

    function test_IsNativeAsset() public {
        AssetMappingRegistry.AssetDetails memory assetInfo = AssetMappingRegistry.AssetDetails(
            AssetMappingRegistry.ImmutableXAsset(TEST_ASSET_ID, TEST_QUANTUM), registry.NATIVE_IMX_ADDRESS()
        );

        registry.registerAsset(assetInfo);
        assertTrue(registry.isMappedToNativeAsset(TEST_ASSET_ID));

        assetInfo =
            AssetMappingRegistry.AssetDetails(AssetMappingRegistry.ImmutableXAsset(2, TEST_QUANTUM), TEST_ASSET_ADDRESS);

        registry.registerAsset(assetInfo);
        assertFalse(registry.isMappedToNativeAsset(2));
    }
}
