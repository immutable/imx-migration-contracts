// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {TokenRegistry} from "@src/assets/TokenRegistry.sol";
import "forge-std/Test.sol";

contract MockAssetsRegistry is TokenRegistry {
    function registerTokenMappings(TokenAssociation[] memory assetInfos) public override {
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

    function test_registerTokenMappings() public {
        TokenRegistry.TokenAssociation[] memory assetInfos =
            _createTokenAssociationArray(TEST_ASSET_ID, TEST_QUANTUM, TEST_ASSET_ADDRESS);

        assertEq(mockRegistry.getZKEVMToken(TEST_ASSET_ID), address(0));
        assertEq(mockRegistry.getTokenQuantum(TEST_ASSET_ID), 0);
        assertFalse(mockRegistry.isMapped(TEST_ASSET_ID));

        vm.expectEmit(true, true, true, true);
        emit TokenRegistry.AssetMapped(TEST_ASSET_ID, TEST_QUANTUM, TEST_ASSET_ADDRESS);
        mockRegistry.registerTokenMappings(assetInfos);

        assertEq(mockRegistry.getZKEVMToken(TEST_ASSET_ID), TEST_ASSET_ADDRESS);
        assertEq(mockRegistry.getTokenQuantum(TEST_ASSET_ID), TEST_QUANTUM);
        assertTrue(mockRegistry.isMapped(TEST_ASSET_ID));
    }

    function test_RegisterTokenMappings() public {
        TokenRegistry.TokenAssociation[] memory assetInfos = new TokenRegistry.TokenAssociation[](2);

        assetInfos[0] = _createTokenAssociation(1, 18, address(0xBEEF));
        assetInfos[1] = _createTokenAssociation(2, 6, address(0xCAFE));

        vm.expectEmit(true, true, true, true);
        emit TokenRegistry.AssetMapped(1, 18, address(0xBEEF));
        vm.expectEmit(true, true, true, true);
        emit TokenRegistry.AssetMapped(2, 6, address(0xCAFE));

        mockRegistry.registerTokenMappings(assetInfos);

        assertEq(mockRegistry.getZKEVMToken(1), address(0xBEEF));
        assertEq(mockRegistry.getTokenQuantum(1), 18);
        assertTrue(mockRegistry.isMapped(1));

        assertEq(mockRegistry.getZKEVMToken(2), address(0xCAFE));
        assertEq(mockRegistry.getTokenQuantum(2), 6);
        assertTrue(mockRegistry.isMapped(2));
    }

    function test_RevertIf_RegisterAsset_ZeroAssetId() public {
        TokenRegistry.TokenAssociation[] memory assetInfos =
            _createTokenAssociationArray(0, TEST_QUANTUM, TEST_ASSET_ADDRESS);

        vm.expectRevert(abi.encodeWithSelector(TokenRegistry.InvalidAssetDetails.selector, "Asset ID cannot be zero"));
        mockRegistry.registerTokenMappings(assetInfos);
    }

    function test_RevertIf_RegisterAsset_ZeroQuantum() public {
        TokenRegistry.TokenAssociation[] memory assetInfos =
            _createTokenAssociationArray(TEST_ASSET_ID, 0, TEST_ASSET_ADDRESS);

        vm.expectRevert(abi.encodeWithSelector(TokenRegistry.InvalidAssetDetails.selector, "Invalid quantum"));
        mockRegistry.registerTokenMappings(assetInfos);
    }

    function test_RevertIf_RegisterAsset_QuantumAboveBounds() public {
        TokenRegistry.TokenAssociation[] memory assetInfos =
            _createTokenAssociationArray(TEST_ASSET_ID, mockRegistry.QUANTUM_UPPER_BOUND(), TEST_ASSET_ADDRESS);

        vm.expectRevert(abi.encodeWithSelector(TokenRegistry.InvalidAssetDetails.selector, "Invalid quantum"));
        mockRegistry.registerTokenMappings(assetInfos);
    }

    function test_RevertIf_RegisterAsset_ZeroAddress() public {
        TokenRegistry.TokenAssociation[] memory assetInfos =
            _createTokenAssociationArray(TEST_ASSET_ID, TEST_QUANTUM, address(0));

        vm.expectRevert(
            abi.encodeWithSelector(TokenRegistry.InvalidAssetDetails.selector, "Asset address cannot be zero")
        );
        mockRegistry.registerTokenMappings(assetInfos);
    }

    function test_RevertIf_RegisterAsset_AlreadyRegistered() public {
        TokenRegistry.TokenAssociation[] memory assetInfos =
            _createTokenAssociationArray(TEST_ASSET_ID, TEST_QUANTUM, TEST_ASSET_ADDRESS);

        mockRegistry.registerTokenMappings(assetInfos);

        vm.expectRevert(abi.encodeWithSelector(TokenRegistry.AssetAlreadyRegistered.selector));
        mockRegistry.registerTokenMappings(assetInfos);
    }

    function test_RevertIf_RegisterAssets_EmptyArray() public {
        TokenRegistry.TokenAssociation[] memory assetInfos = new TokenRegistry.TokenAssociation[](0);

        vm.expectRevert(abi.encodeWithSelector(TokenRegistry.InvalidAssetDetails.selector, "No assets to register"));
        mockRegistry.registerTokenMappings(assetInfos);
    }

    function test_RegisterAsset_Native() public {
        TokenRegistry.TokenAssociation[] memory nativeAsset =
            _createTokenAssociationArray(TEST_ASSET_ID, TEST_QUANTUM, mockRegistry.NATIVE_IMX_ADDRESS());
        TokenRegistry.TokenAssociation[] memory nonNativeAsset =
            _createTokenAssociationArray(TEST_ASSET_ID + 1, TEST_QUANTUM, TEST_ASSET_ADDRESS);

        // register both assets
        mockRegistry.registerTokenMappings(nativeAsset);
        mockRegistry.registerTokenMappings(nonNativeAsset);

        address token = mockRegistry.getTokenMapping(TEST_ASSET_ID).tokenOnZKEVM;
        assertTrue(token == mockRegistry.NATIVE_IMX_ADDRESS());
    }

    // Helper functions to create structs more concisely
    function _createImmutableXAsset(uint256 id, uint256 quantum)
        private
        pure
        returns (TokenRegistry.ImmutableXToken memory)
    {
        return TokenRegistry.ImmutableXToken(id, quantum);
    }

    function _createTokenAssociationArray(uint256 id, uint256 quantum, address zkAddress)
        private
        pure
        returns (TokenRegistry.TokenAssociation[] memory)
    {
        TokenRegistry.TokenAssociation[] memory assetInfos = new TokenRegistry.TokenAssociation[](1);
        assetInfos[0] = _createTokenAssociation(id, quantum, zkAddress);
        return assetInfos;
    }

    function _createTokenAssociation(uint256 id, uint256 quantum, address zkAddress)
        private
        pure
        returns (TokenRegistry.TokenAssociation memory)
    {
        return TokenRegistry.TokenAssociation(_createImmutableXAsset(id, quantum), zkAddress);
    }
}
