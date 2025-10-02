// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {BridgedTokenMapping} from "@src/assets/BridgedTokenMapping.sol";
import "forge-std/Test.sol";

contract MockAssetsRegistry is BridgedTokenMapping {
    function registerTokenMappings(TokenMapping[] calldata assetInfos) public override {
        _registerTokenMappings(assetInfos);
    }
}

contract BridgedTokenMappingTest is Test {
    uint256 public constant TEST_ASSET_ID = 1;
    address public constant TEST_ASSET_ADDRESS = address(0x1234);
    uint256 public constant TEST_QUANTUM = 10000000;

    MockAssetsRegistry public mockRegistry;

    function setUp() public {
        mockRegistry = new MockAssetsRegistry();
    }

    function test_registerTokenMappings_Single() public {
        BridgedTokenMapping.TokenMapping[] memory assetInfos =
            _createTokenMappingArray(TEST_ASSET_ID, TEST_QUANTUM, TEST_ASSET_ADDRESS);

        assertEq(mockRegistry.getZKEVMAddress(TEST_ASSET_ID), address(0));
        assertEq(mockRegistry.getQuantum(TEST_ASSET_ID), 0);
        assertFalse(mockRegistry.isMapped(TEST_ASSET_ID));

        vm.expectEmit(true, true, true, true);
        emit BridgedTokenMapping.TokenMappingAdded(TEST_ASSET_ID, TEST_QUANTUM, TEST_ASSET_ADDRESS);
        mockRegistry.registerTokenMappings(assetInfos);

        assertEq(mockRegistry.getZKEVMAddress(TEST_ASSET_ID), TEST_ASSET_ADDRESS);
        assertEq(mockRegistry.getQuantum(TEST_ASSET_ID), TEST_QUANTUM);
        assertTrue(mockRegistry.isMapped(TEST_ASSET_ID));
    }

    function test_registerTokenMappings_Multiple() public {
        BridgedTokenMapping.TokenMapping[] memory tokenMappings = new BridgedTokenMapping.TokenMapping[](2);

        tokenMappings[0] = _createTokenMapping(1, 18, address(0xBEEF));
        tokenMappings[1] = _createTokenMapping(2, 6, address(0xCAFE));

        vm.expectEmit(true, true, true, true);
        emit BridgedTokenMapping.TokenMappingAdded(1, 18, address(0xBEEF));
        vm.expectEmit(true, true, true, true);
        emit BridgedTokenMapping.TokenMappingAdded(2, 6, address(0xCAFE));

        mockRegistry.registerTokenMappings(tokenMappings);

        assertEq(mockRegistry.getZKEVMAddress(1), address(0xBEEF));
        assertEq(mockRegistry.getQuantum(1), 18);
        assertTrue(mockRegistry.isMapped(1));

        assertEq(mockRegistry.getZKEVMAddress(2), address(0xCAFE));
        assertEq(mockRegistry.getQuantum(2), 6);
        assertTrue(mockRegistry.isMapped(2));
    }

    function test_RegisterToken_Native() public {
        BridgedTokenMapping.TokenMapping[] memory nativeAsset =
            _createTokenMappingArray(TEST_ASSET_ID, TEST_QUANTUM, mockRegistry.NATIVE_IMX_ADDRESS());
        BridgedTokenMapping.TokenMapping[] memory nonNativeAsset =
            _createTokenMappingArray(TEST_ASSET_ID + 1, TEST_QUANTUM, TEST_ASSET_ADDRESS);

        mockRegistry.registerTokenMappings(nativeAsset);
        mockRegistry.registerTokenMappings(nonNativeAsset);

        address token = mockRegistry.getTokenMapping(TEST_ASSET_ID).tokenOnZKEVM;
        assertTrue(token == mockRegistry.NATIVE_IMX_ADDRESS());
    }

    function test_RevertIf_RegisterToken_ZeroAssetId() public {
        BridgedTokenMapping.TokenMapping[] memory assetInfos =
            _createTokenMappingArray(0, TEST_QUANTUM, TEST_ASSET_ADDRESS);

        vm.expectRevert(
            abi.encodeWithSelector(BridgedTokenMapping.InvalidTokenDetails.selector, "Asset ID cannot be zero")
        );
        mockRegistry.registerTokenMappings(assetInfos);
    }

    function test_RevertIf_RegisterToken_ZeroQuantum() public {
        BridgedTokenMapping.TokenMapping[] memory assetInfos =
            _createTokenMappingArray(TEST_ASSET_ID, 0, TEST_ASSET_ADDRESS);

        vm.expectRevert(abi.encodeWithSelector(BridgedTokenMapping.InvalidTokenDetails.selector, "Invalid quantum"));
        mockRegistry.registerTokenMappings(assetInfos);
    }

    function test_RevertIf_RegisterToken_QuantumAboveBounds() public {
        BridgedTokenMapping.TokenMapping[] memory assetInfos =
            _createTokenMappingArray(TEST_ASSET_ID, mockRegistry.QUANTUM_UPPER_BOUND(), TEST_ASSET_ADDRESS);

        vm.expectRevert(abi.encodeWithSelector(BridgedTokenMapping.InvalidTokenDetails.selector, "Invalid quantum"));
        mockRegistry.registerTokenMappings(assetInfos);
    }

    function test_RevertIf_RegisterToken_ZeroAddress() public {
        BridgedTokenMapping.TokenMapping[] memory assetInfos =
            _createTokenMappingArray(TEST_ASSET_ID, TEST_QUANTUM, address(0));

        vm.expectRevert(
            abi.encodeWithSelector(BridgedTokenMapping.InvalidTokenDetails.selector, "Asset address cannot be zero")
        );
        mockRegistry.registerTokenMappings(assetInfos);
    }

    function test_RevertIf_RegisterToken_AlreadyRegistered() public {
        BridgedTokenMapping.TokenMapping[] memory assetInfos =
            _createTokenMappingArray(TEST_ASSET_ID, TEST_QUANTUM, TEST_ASSET_ADDRESS);

        mockRegistry.registerTokenMappings(assetInfos);

        vm.expectRevert(abi.encodeWithSelector(BridgedTokenMapping.TokenAlreadyMapped.selector));
        mockRegistry.registerTokenMappings(assetInfos);
    }

    function test_RevertIf_RegisterTokens_EmptyArray() public {
        BridgedTokenMapping.TokenMapping[] memory assetInfos = new BridgedTokenMapping.TokenMapping[](0);

        vm.expectRevert(
            abi.encodeWithSelector(BridgedTokenMapping.InvalidTokenDetails.selector, "No assets to register")
        );
        mockRegistry.registerTokenMappings(assetInfos);
    }

    function test_GetTokenMapping_UnregisteredAsset() public view {
        uint256 unregisteredAssetId = 999;

        BridgedTokenMapping.TokenMapping memory tokenMapping = mockRegistry.getTokenMapping(unregisteredAssetId);

        assertEq(tokenMapping.tokenOnIMX.id, 0, "Unregistered asset should have zero ID");
        assertEq(tokenMapping.tokenOnIMX.quantum, 0, "Unregistered asset should have zero quantum");
        assertEq(tokenMapping.tokenOnZKEVM, address(0), "Unregistered asset should have zero address");
    }

    function test_RegisterToken_MultipleAssetsSameZKEVMAddress() public {
        address sameZKEVMAddress = address(0x1234);
        uint256 assetId1 = 1;
        uint256 assetId2 = 2;
        uint256 quantum1 = 18;
        uint256 quantum2 = 6;

        BridgedTokenMapping.TokenMapping[] memory assetInfos = new BridgedTokenMapping.TokenMapping[](2);
        assetInfos[0] = _createTokenMapping(assetId1, quantum1, sameZKEVMAddress);
        assetInfos[1] = _createTokenMapping(assetId2, quantum2, sameZKEVMAddress);

        vm.expectEmit(true, true, true, true);
        emit BridgedTokenMapping.TokenMappingAdded(assetId1, quantum1, sameZKEVMAddress);
        vm.expectEmit(true, true, true, true);
        emit BridgedTokenMapping.TokenMappingAdded(assetId2, quantum2, sameZKEVMAddress);

        mockRegistry.registerTokenMappings(assetInfos);

        // Verify both assets are mapped to the same zkEVM address
        assertEq(mockRegistry.getZKEVMAddress(assetId1), sameZKEVMAddress);
        assertEq(mockRegistry.getZKEVMAddress(assetId2), sameZKEVMAddress);
        assertTrue(mockRegistry.isMapped(assetId1));
        assertTrue(mockRegistry.isMapped(assetId2));

        // Verify they have different quantums
        assertEq(mockRegistry.getQuantum(assetId1), quantum1);
        assertEq(mockRegistry.getQuantum(assetId2), quantum2);
    }

    function test_RegisterToken_QuantumAtUpperBound() public {
        uint256 validQuantum = mockRegistry.QUANTUM_UPPER_BOUND() - 1;
        BridgedTokenMapping.TokenMapping[] memory assetInfos =
            _createTokenMappingArray(TEST_ASSET_ID, validQuantum, TEST_ASSET_ADDRESS);

        vm.expectEmit(true, true, true, true);
        emit BridgedTokenMapping.TokenMappingAdded(TEST_ASSET_ID, validQuantum, TEST_ASSET_ADDRESS);
        mockRegistry.registerTokenMappings(assetInfos);

        assertEq(mockRegistry.getQuantum(TEST_ASSET_ID), validQuantum);
        assertTrue(mockRegistry.isMapped(TEST_ASSET_ID));
    }

    function test_IsMapped() public {
        uint256 unregisteredAssetId = 999;

        assertFalse(mockRegistry.isMapped(unregisteredAssetId), "Unregistered asset should not be mapped");

        BridgedTokenMapping.TokenMapping[] memory assetInfos =
            _createTokenMappingArray(TEST_ASSET_ID, TEST_QUANTUM, TEST_ASSET_ADDRESS);
        mockRegistry.registerTokenMappings(assetInfos);

        assertTrue(mockRegistry.isMapped(TEST_ASSET_ID), "Registered asset should be mapped");

        assertFalse(mockRegistry.isMapped(unregisteredAssetId), "Unregistered asset should still not be mapped");
    }

    function test_GetZKEVMAddressAndQuantum_UnregisteredAsset() public {
        uint256 unregisteredAssetId = 999;

        assertEq(
            mockRegistry.getZKEVMAddress(unregisteredAssetId),
            address(0),
            "Unregistered asset should return zero address"
        );
        assertEq(mockRegistry.getQuantum(unregisteredAssetId), 0, "Unregistered asset should return zero quantum");

        BridgedTokenMapping.TokenMapping[] memory assetInfos =
            _createTokenMappingArray(TEST_ASSET_ID, TEST_QUANTUM, TEST_ASSET_ADDRESS);
        mockRegistry.registerTokenMappings(assetInfos);

        assertEq(
            mockRegistry.getZKEVMAddress(TEST_ASSET_ID),
            TEST_ASSET_ADDRESS,
            "Registered asset should return correct address"
        );
        assertEq(mockRegistry.getQuantum(TEST_ASSET_ID), TEST_QUANTUM, "Registered asset should return correct quantum");

        assertEq(
            mockRegistry.getZKEVMAddress(unregisteredAssetId),
            address(0),
            "Unregistered asset should still return zero address"
        );
        assertEq(mockRegistry.getQuantum(unregisteredAssetId), 0, "Unregistered asset should still return zero quantum");
    }

    // Helper functions to create structs more concisely
    function _createImmutableXAsset(uint256 id, uint256 quantum)
        private
        pure
        returns (BridgedTokenMapping.ImmutableXToken memory)
    {
        return BridgedTokenMapping.ImmutableXToken(id, quantum);
    }

    function _createTokenMappingArray(uint256 id, uint256 quantum, address zkAddress)
        private
        pure
        returns (BridgedTokenMapping.TokenMapping[] memory)
    {
        BridgedTokenMapping.TokenMapping[] memory assetInfos = new BridgedTokenMapping.TokenMapping[](1);
        assetInfos[0] = _createTokenMapping(id, quantum, zkAddress);
        return assetInfos;
    }

    function _createTokenMapping(uint256 id, uint256 quantum, address zkAddress)
        private
        pure
        returns (BridgedTokenMapping.TokenMapping memory)
    {
        return BridgedTokenMapping.TokenMapping(_createImmutableXAsset(id, quantum), zkAddress);
    }
}
