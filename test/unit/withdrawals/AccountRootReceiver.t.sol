// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import "@src/withdrawals/AccountRootReceiver.sol";

/**
 * @title TestAccountRootReceiver
 * @notice Concrete implementation of AccountRootReceiver for testing purposes
 */
contract TestAccountRootReceiver is AccountRootReceiver {
    bool public overrideAllowed;

    constructor(bool _overrideAllowed) {
        overrideAllowed = _overrideAllowed;
    }

    /**
     * @notice External function to set the account root hash
     */
    function setAccountRoot(bytes32 newRoot) external override {
        _setAccountRoot(newRoot, overrideAllowed);
    }

    /**
     * @notice Function to set account root with override control
     */
    function setAccountRootWithOverride(bytes32 newRoot, bool _override) external {
        _setAccountRoot(newRoot, _override);
    }

    /**
     * @notice Function to change override setting
     */
    function setOverrideAllowed(bool _overrideAllowed) external {
        overrideAllowed = _overrideAllowed;
    }

    /**
     * @notice Function to test account root validation
     */
    function testAccountRootValidation(bytes32 testRoot) external pure returns (bool) {
        require(testRoot != bytes32(0), InvalidAccountRoot());
        return true;
    }
}

contract AccountRootReceiverTest is Test {
    TestAccountRootReceiver public receiver;
    TestAccountRootReceiver public receiverWithOverride;

    bytes32 constant VALID_ROOT = 0x1234567890123456789012345678901234567890123456789012345678901234;
    bytes32 constant ZERO_ROOT = bytes32(0);

    function setUp() public {
        receiver = new TestAccountRootReceiver(false);
        receiverWithOverride = new TestAccountRootReceiver(true);
    }

    function test_SetAccountRoot_Initial() public {
        bytes32 newRoot = VALID_ROOT;

        vm.expectEmit(true, true, true, true);
        emit AccountRootReceiver.AccountRootSet(bytes32(0), newRoot);

        receiver.setAccountRoot(newRoot);
        assertEq(receiver.accountRoot(), newRoot, "Account root should be set correctly");
    }

    function test_SetAccountRoot_Override() public {
        bytes32 firstRoot = VALID_ROOT;
        bytes32 secondRoot = 0x9999999999999999999999999999999999999999999999999999999999999999;

        // Set initial root
        receiverWithOverride.setAccountRoot(firstRoot);
        assertEq(receiverWithOverride.accountRoot(), firstRoot, "First root should be set");

        // Override with second root
        vm.expectEmit(true, true, true, true);
        emit AccountRootReceiver.AccountRootSet(firstRoot, secondRoot);

        receiverWithOverride.setAccountRoot(secondRoot);
        assertEq(receiverWithOverride.accountRoot(), secondRoot, "Second root should override first");
    }

    function test_SetAccountRoot_WithOverrideControl() public {
        bytes32 firstRoot = VALID_ROOT;
        bytes32 secondRoot = 0x9999999999999999999999999999999999999999999999999999999999999999;

        // Set initial root
        receiver.setAccountRoot(firstRoot);
        assertEq(receiver.accountRoot(), firstRoot, "First root should be set");

        // Try to override without override flag - should revert
        vm.expectRevert(AccountRootReceiver.RootOverrideNotAllowed.selector);
        receiver.setAccountRootWithOverride(secondRoot, false);

        // Override with override flag
        vm.expectEmit(true, true, true, true);
        emit AccountRootReceiver.AccountRootSet(firstRoot, secondRoot);

        receiver.setAccountRootWithOverride(secondRoot, true);
        assertEq(receiver.accountRoot(), secondRoot, "Root should be overridden when override is true");
    }

    function test_RevertIf_SetAccountRoot_ZeroValue() public {
        vm.expectRevert(AccountRootReceiver.InvalidAccountRoot.selector);
        receiver.setAccountRoot(ZERO_ROOT);
    }

    function test_RevertIf_SetAccountRoot_OverrideNotAllowed() public {
        bytes32 firstRoot = VALID_ROOT;
        bytes32 secondRoot = 0x9999999999999999999999999999999999999999999999999999999999999999;

        // Set initial root
        receiver.setAccountRoot(firstRoot);
        assertEq(receiver.accountRoot(), firstRoot, "First root should be set");

        // Try to override without override being allowed
        vm.expectRevert(AccountRootReceiver.RootOverrideNotAllowed.selector);
        receiver.setAccountRoot(secondRoot);
    }

    function test_AccountRootSet_EventEmitted() public {
        bytes32 newRoot = VALID_ROOT;

        vm.expectEmit(true, true, true, true);
        emit AccountRootReceiver.AccountRootSet(bytes32(0), newRoot);

        receiver.setAccountRoot(newRoot);
    }

    function test_AccountRootSet_EventEmitted_Override() public {
        bytes32 firstRoot = VALID_ROOT;
        bytes32 secondRoot = 0x9999999999999999999999999999999999999999999999999999999999999999;

        // Set initial root
        receiverWithOverride.setAccountRoot(firstRoot);

        // Override and check event
        vm.expectEmit(true, true, true, true);
        emit AccountRootReceiver.AccountRootSet(firstRoot, secondRoot);

        receiverWithOverride.setAccountRoot(secondRoot);
    }

    function test_InitialState() public view {
        assertEq(receiver.accountRoot(), bytes32(0), "Initial account root should be zero");
        assertEq(receiverWithOverride.accountRoot(), bytes32(0), "Initial account root should be zero");
    }

    function test_MultipleRoots_WithOverride() public {
        bytes32[] memory roots = new bytes32[](3);
        roots[0] = 0x1111111111111111111111111111111111111111111111111111111111111111;
        roots[1] = 0x2222222222222222222222222222222222222222222222222222222222222222;
        roots[2] = 0x3333333333333333333333333333333333333333333333333333333333333333;

        for (uint256 i = 0; i < roots.length; i++) {
            bytes32 expectedOldRoot = i == 0 ? bytes32(0) : roots[i - 1];

            vm.expectEmit(true, true, true, true);
            emit AccountRootReceiver.AccountRootSet(expectedOldRoot, roots[i]);

            receiverWithOverride.setAccountRoot(roots[i]);
            assertEq(
                receiverWithOverride.accountRoot(),
                roots[i],
                string(abi.encodePacked("Root ", vm.toString(i), " should be set"))
            );
        }
    }

    function test_OverrideSetting_Change() public {
        bytes32 firstRoot = VALID_ROOT;
        bytes32 secondRoot = 0x9999999999999999999999999999999999999999999999999999999999999999;

        // Initially override is disabled
        receiver.setAccountRoot(firstRoot);

        // Try to override (should fail)
        vm.expectRevert(AccountRootReceiver.RootOverrideNotAllowed.selector);
        receiver.setAccountRoot(secondRoot);

        // Enable override
        receiver.setOverrideAllowed(true);

        // Now override should work
        vm.expectEmit(true, true, true, true);
        emit AccountRootReceiver.AccountRootSet(firstRoot, secondRoot);

        receiver.setAccountRoot(secondRoot);
        assertEq(receiver.accountRoot(), secondRoot, "Root should be overridden after enabling override");
    }

    function test_ErrorSelectors() public pure {
        // Test that error selectors can be encoded
        bytes memory invalidRootError = abi.encodeWithSelector(AccountRootReceiver.InvalidAccountRoot.selector);
        assertTrue(invalidRootError.length > 0, "InvalidAccountRoot error should be encodable");

        bytes memory overrideNotAllowedError =
            abi.encodeWithSelector(AccountRootReceiver.RootOverrideNotAllowed.selector);
        assertTrue(overrideNotAllowedError.length > 0, "RootOverrideNotAllowed error should be encodable");

        bytes memory accountRootNotSetError = abi.encodeWithSelector(AccountRootReceiver.AccountRootNotSet.selector);
        assertTrue(accountRootNotSetError.length > 0, "AccountRootNotSet error should be encodable");

        bytes4 expectedInvalidRootSelector = AccountRootReceiver.InvalidAccountRoot.selector;
        bytes4 expectedOverrideSelector = AccountRootReceiver.RootOverrideNotAllowed.selector;
        bytes4 expectedAccountRootNotSetSelector = AccountRootReceiver.AccountRootNotSet.selector;

        assertEq(bytes4(invalidRootError), expectedInvalidRootSelector, "InvalidAccountRoot selector should match");
        assertEq(
            bytes4(overrideNotAllowedError), expectedOverrideSelector, "RootOverrideNotAllowed selector should match"
        );
        assertEq(
            bytes4(accountRootNotSetError), expectedAccountRootNotSetSelector, "AccountRootNotSet selector should match"
        );
    }

    function test_EdgeCases() public {
        // Test with maximum bytes32 value
        bytes32 maxRoot = bytes32(type(uint256).max);

        vm.expectEmit(true, true, true, true);
        emit AccountRootReceiver.AccountRootSet(bytes32(0), maxRoot);

        receiver.setAccountRoot(maxRoot);
        assertEq(receiver.accountRoot(), maxRoot, "Maximum root value should be accepted");

        // Test with minimum non-zero value
        bytes32 minRoot = bytes32(uint256(1));

        vm.expectEmit(true, true, true, true);
        emit AccountRootReceiver.AccountRootSet(bytes32(0), minRoot);

        receiverWithOverride.setAccountRoot(minRoot);
        assertEq(receiverWithOverride.accountRoot(), minRoot, "Minimum non-zero root value should be accepted");
    }

    function test_AccountRootValidation() public {
        // Test that zero root is rejected
        vm.expectRevert(AccountRootReceiver.InvalidAccountRoot.selector);
        receiver.testAccountRootValidation(bytes32(0));

        // Test that non-zero root is accepted
        bool result = receiver.testAccountRootValidation(VALID_ROOT);
        assertTrue(result, "Valid root should be accepted");
    }

    function test_EventParameters() public {
        bytes32 newRoot = VALID_ROOT;

        // Test that event parameters are correctly indexed
        vm.expectEmit(true, true, true, true);
        emit AccountRootReceiver.AccountRootSet(bytes32(0), newRoot);

        receiver.setAccountRoot(newRoot);

        // Verify the event was emitted with correct parameters
        // The event should have oldRoot and newRoot as indexed parameters
        // This is tested by the vm.expectEmit above
    }
}
