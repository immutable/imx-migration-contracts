// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import "@src/withdrawals/VaultRootReceiver.sol";

/**
 * @title TestVaultRootReceiver
 * @notice Concrete implementation of VaultRootReceiver for testing purposes
 */
contract TestVaultRootReceiver is VaultRootReceiver {
    bool public overrideAllowed;

    constructor(bool _overrideAllowed) {
        overrideAllowed = _overrideAllowed;
    }

    /**
     * @notice External function to set the vault root hash
     */
    function setVaultRoot(uint256 _vaultRoot) external override {
        _setVaultRoot(_vaultRoot, overrideAllowed);
    }

    /**
     * @notice Function to set vault root with override control
     */
    function setVaultRootWithOverride(uint256 _vaultRoot, bool _override) external {
        _setVaultRoot(_vaultRoot, _override);
    }

    /**
     * @notice Function to change override setting
     */
    function setOverrideAllowed(bool _overrideAllowed) external {
        overrideAllowed = _overrideAllowed;
    }
}

contract VaultRootReceiverTest is Test {
    TestVaultRootReceiver public receiver;
    TestVaultRootReceiver public receiverWithOverride;

    uint256 constant VALID_ROOT = 0x1234567890123456789012345678901234567890123456789012345678901234;
    uint256 constant ZERO_ROOT = 0;

    function setUp() public {
        receiver = new TestVaultRootReceiver(false);
        receiverWithOverride = new TestVaultRootReceiver(true);
    }

    function test_SetVaultRoot_Initial() public {
        uint256 newRoot = VALID_ROOT;

        vm.expectEmit(true, true, true, true);
        emit VaultRootReceiver.VaultRootSet(0, newRoot);

        receiver.setVaultRoot(newRoot);
        assertEq(receiver.vaultRoot(), newRoot, "Vault root should be set correctly");
    }

    function test_SetVaultRoot_Override() public {
        uint256 firstRoot = VALID_ROOT;
        uint256 secondRoot = 0x9999999999999999999999999999999999999999999999999999999999999999;

        // Set initial root
        receiverWithOverride.setVaultRoot(firstRoot);
        assertEq(receiverWithOverride.vaultRoot(), firstRoot, "First root should be set");

        // Override with second root
        vm.expectEmit(true, true, true, true);
        emit VaultRootReceiver.VaultRootSet(firstRoot, secondRoot);

        receiverWithOverride.setVaultRoot(secondRoot);
        assertEq(receiverWithOverride.vaultRoot(), secondRoot, "Second root should override first");
    }

    function test_SetVaultRoot_WithOverrideControl() public {
        uint256 firstRoot = VALID_ROOT;
        uint256 secondRoot = 0x9999999999999999999999999999999999999999999999999999999999999999;

        // Set initial root
        receiver.setVaultRoot(firstRoot);
        assertEq(receiver.vaultRoot(), firstRoot, "First root should be set");

        // Try to override without override flag - should revert
        vm.expectRevert(VaultRootReceiver.VaultRootOverrideNotAllowed.selector);
        receiver.setVaultRootWithOverride(secondRoot, false);

        // Override with override flag
        vm.expectEmit(true, true, true, true);
        emit VaultRootReceiver.VaultRootSet(firstRoot, secondRoot);

        receiver.setVaultRootWithOverride(secondRoot, true);
        assertEq(receiver.vaultRoot(), secondRoot, "Root should be overridden when override is true");
    }

    function test_RevertIf_SetVaultRoot_ZeroValue() public {
        vm.expectRevert(VaultRootReceiver.InvalidVaultRoot.selector);
        receiver.setVaultRoot(ZERO_ROOT);
    }

    function test_RevertIf_SetVaultRoot_OverrideNotAllowed() public {
        uint256 firstRoot = VALID_ROOT;
        uint256 secondRoot = 0x9999999999999999999999999999999999999999999999999999999999999999;

        // Set initial root
        receiver.setVaultRoot(firstRoot);
        assertEq(receiver.vaultRoot(), firstRoot, "First root should be set");

        // Try to override without override being allowed
        vm.expectRevert(VaultRootReceiver.VaultRootOverrideNotAllowed.selector);
        receiver.setVaultRoot(secondRoot);
    }

    function test_VaultRootSet_EventEmitted() public {
        uint256 newRoot = VALID_ROOT;

        vm.expectEmit(true, true, true, true);
        emit VaultRootReceiver.VaultRootSet(0, newRoot);

        receiver.setVaultRoot(newRoot);
    }

    function test_VaultRootSet_EventEmitted_Override() public {
        uint256 firstRoot = VALID_ROOT;
        uint256 secondRoot = 0x9999999999999999999999999999999999999999999999999999999999999999;

        // Set initial root
        receiverWithOverride.setVaultRoot(firstRoot);

        // Override and check event
        vm.expectEmit(true, true, true, true);
        emit VaultRootReceiver.VaultRootSet(firstRoot, secondRoot);

        receiverWithOverride.setVaultRoot(secondRoot);
    }

    function test_InitialState() public view {
        assertEq(receiver.vaultRoot(), 0, "Initial vault root should be zero");
        assertEq(receiverWithOverride.vaultRoot(), 0, "Initial vault root should be zero");
    }

    function test_MultipleRoots_WithOverride() public {
        uint256[] memory roots = new uint256[](3);
        roots[0] = 0x1111111111111111111111111111111111111111111111111111111111111111;
        roots[1] = 0x2222222222222222222222222222222222222222222222222222222222222222;
        roots[2] = 0x3333333333333333333333333333333333333333333333333333333333333333;

        for (uint256 i = 0; i < roots.length; i++) {
            uint256 expectedOldRoot = i == 0 ? 0 : roots[i - 1];

            vm.expectEmit(true, true, true, true);
            emit VaultRootReceiver.VaultRootSet(expectedOldRoot, roots[i]);

            receiverWithOverride.setVaultRoot(roots[i]);
            assertEq(
                receiverWithOverride.vaultRoot(),
                roots[i],
                string(abi.encodePacked("Root ", vm.toString(i), " should be set"))
            );
        }
    }

    function test_OverrideSetting_Change() public {
        uint256 firstRoot = VALID_ROOT;
        uint256 secondRoot = 0x9999999999999999999999999999999999999999999999999999999999999999;

        // Initially override is disabled
        receiver.setVaultRoot(firstRoot);

        // Try to override (should fail)
        vm.expectRevert(VaultRootReceiver.VaultRootOverrideNotAllowed.selector);
        receiver.setVaultRoot(secondRoot);

        // Enable override
        receiver.setOverrideAllowed(true);

        // Now override should work
        vm.expectEmit(true, true, true, true);
        emit VaultRootReceiver.VaultRootSet(firstRoot, secondRoot);

        receiver.setVaultRoot(secondRoot);
        assertEq(receiver.vaultRoot(), secondRoot, "Root should be overridden after enabling override");
    }

    function test_ErrorSelectors() public pure {
        // Test that error selectors can be encoded
        bytes memory invalidRootError = abi.encodeWithSelector(VaultRootReceiver.InvalidVaultRoot.selector);
        assertTrue(invalidRootError.length > 0, "InvalidVaultRoot error should be encodable");

        bytes memory overrideNotAllowedError =
            abi.encodeWithSelector(VaultRootReceiver.VaultRootOverrideNotAllowed.selector);
        assertTrue(overrideNotAllowedError.length > 0, "VaultRootOverrideNotAllowed error should be encodable");

        bytes4 expectedInvalidRootSelector = VaultRootReceiver.InvalidVaultRoot.selector;
        bytes4 expectedOverrideSelector = VaultRootReceiver.VaultRootOverrideNotAllowed.selector;

        assertEq(bytes4(invalidRootError), expectedInvalidRootSelector, "InvalidVaultRoot selector should match");
        assertEq(
            bytes4(overrideNotAllowedError),
            expectedOverrideSelector,
            "VaultRootOverrideNotAllowed selector should match"
        );
    }

    function test_EdgeCases() public {
        // Test with maximum uint256 value
        uint256 maxRoot = type(uint256).max;

        vm.expectEmit(true, true, true, true);
        emit VaultRootReceiver.VaultRootSet(0, maxRoot);

        receiver.setVaultRoot(maxRoot);
        assertEq(receiver.vaultRoot(), maxRoot, "Maximum root value should be accepted");

        // Test with minimum non-zero value
        uint256 minRoot = 1;

        vm.expectEmit(true, true, true, true);
        emit VaultRootReceiver.VaultRootSet(0, minRoot);

        receiverWithOverride.setVaultRoot(minRoot);
        assertEq(receiverWithOverride.vaultRoot(), minRoot, "Minimum non-zero root value should be accepted");
    }
}
