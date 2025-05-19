// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "@src/assets/AssetsRegistry.sol";
import "@src/assets/AssetsRegistry.sol";
import "forge-std/Test.sol";

// Create a concrete implementation for testing
contract TestAssetsRegistry is AssetsRegistry {
    function registerAsset(AssetsRegistry.AssetDetails memory assetInfo) public {
        _registerAsset(assetInfo);
    }

    function registerAssets(AssetsRegistry.AssetDetails[] memory assetInfos) public {
        _registerAssets(assetInfos);
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
        AssetsRegistry.AssetDetails memory assetInfo = AssetsRegistry.AssetDetails({
            assetId: TEST_ASSET_ID,
            assetAddress: TEST_ASSET_ADDRESS,
            quantum: TEST_QUANTUM
        });

        vm.expectEmit(true, true, true, true);
        emit AssetsRegistry.AssetRegistered(TEST_ASSET_ID, TEST_QUANTUM, TEST_ASSET_ADDRESS);
        registry.registerAsset(assetInfo);

        assertEq(registry.getAssetAddress(TEST_ASSET_ID), TEST_ASSET_ADDRESS);
        assertEq(registry.getAssetQuantum(TEST_ASSET_ID), TEST_QUANTUM);
        assertTrue(registry.isRegistered(TEST_ASSET_ID));
    }

    function test_RegisterAssets() public {
        AssetsRegistry.AssetDetails[] memory assetInfos = new AssetsRegistry.AssetDetails[](2);

        assetInfos[0] = AssetsRegistry.AssetDetails({assetId: 1, assetAddress: address(0xBEEF), quantum: 1e18});
        assetInfos[1] = AssetsRegistry.AssetDetails({assetId: 2, assetAddress: address(0xCAFE), quantum: 1e6});

        vm.expectEmit(true, true, true, true);
        emit AssetsRegistry.AssetRegistered(1, 1e18, address(0xBEEF));
        vm.expectEmit(true, true, true, true);
        emit AssetsRegistry.AssetRegistered(2, 1e6, address(0xCAFE));

        registry.registerAssets(assetInfos);

        assertEq(registry.getAssetAddress(1), address(0xBEEF));
        assertEq(registry.getAssetQuantum(1), 1e18);
        assertEq(registry.getAssetAddress(2), address(0xCAFE));
        assertEq(registry.getAssetQuantum(2), 1e6);
    }

    function test_RegisterAsset_ZeroAssetId() public {
        AssetsRegistry.AssetDetails memory assetInfo =
            AssetsRegistry.AssetDetails({assetId: 0, assetAddress: TEST_ASSET_ADDRESS, quantum: TEST_QUANTUM});

        vm.expectRevert(abi.encodeWithSelector(AssetsRegistry.InvalidAssetDetails.selector, "Asset ID cannot be zero"));
        registry.registerAsset(assetInfo);
    }

    function test_RegisterAsset_ZeroAddress() public {
        AssetsRegistry.AssetDetails memory assetInfo =
            AssetsRegistry.AssetDetails({assetId: TEST_ASSET_ID, assetAddress: address(0), quantum: TEST_QUANTUM});

        vm.expectRevert(
            abi.encodeWithSelector(AssetsRegistry.InvalidAssetDetails.selector, "Asset address cannot be zero")
        );
        registry.registerAsset(assetInfo);
    }

    function test_RegisterAsset_ZeroQuantum() public {
        AssetsRegistry.AssetDetails memory assetInfo =
            AssetsRegistry.AssetDetails({assetId: TEST_ASSET_ID, assetAddress: TEST_ASSET_ADDRESS, quantum: 0});

        vm.expectRevert(abi.encodeWithSelector(AssetsRegistry.InvalidAssetDetails.selector, "Quantum cannot be zero"));
        registry.registerAsset(assetInfo);
    }

    function test_RegisterAsset_DuplicateAssetId() public {
        AssetsRegistry.AssetDetails memory assetInfo = AssetsRegistry.AssetDetails({
            assetId: TEST_ASSET_ID,
            assetAddress: TEST_ASSET_ADDRESS,
            quantum: TEST_QUANTUM
        });

        registry.registerAsset(assetInfo);

        vm.expectRevert(abi.encodeWithSelector(AssetsRegistry.InvalidAssetDetails.selector, "Asset already registered"));
        registry.registerAsset(assetInfo);
    }

    function test_RegisterAssets_EmptyArrays() public {
        AssetsRegistry.AssetDetails[] memory assetInfos = new AssetsRegistry.AssetDetails[](0);

        vm.expectRevert(abi.encodeWithSelector(AssetsRegistry.InvalidAssetDetails.selector, "No assets to register"));
        registry.registerAssets(assetInfos);
    }

    function test_IsNativeAsset() public {
        AssetsRegistry.AssetDetails memory assetInfo = AssetsRegistry.AssetDetails({
            assetId: TEST_ASSET_ID,
            assetAddress: registry.NATIVE_IMX_ADDRESS(),
            quantum: TEST_QUANTUM
        });

        registry.registerAsset(assetInfo);
        assertTrue(registry.isNativeAsset(TEST_ASSET_ID));

        assetInfo = AssetsRegistry.AssetDetails({assetId: 2, assetAddress: TEST_ASSET_ADDRESS, quantum: TEST_QUANTUM});

        registry.registerAsset(assetInfo);
        assertFalse(registry.isNativeAsset(2));
    }
}
