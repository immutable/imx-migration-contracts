// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import "@src/withdrawals/ProcessorAccessControl.sol";
import "@openzeppelin/contracts/access/IAccessControl.sol";

/**
 * @title TestProcessorAccessControl
 * @notice Concrete implementation of ProcessorAccessControl for testing purposes
 */
contract TestProcessorAccessControl is ProcessorAccessControl {
    constructor() {
        // Initialize with default roles for testing
        ProcessorAccessControl.RoleOperators memory operators = ProcessorAccessControl.RoleOperators({
            accountRootProvider: address(this),
            vaultRootProvider: address(this),
            tokenMappingManager: address(this),
            disburser: address(this),
            pauser: address(this),
            unpauser: address(this),
            defaultAdmin: address(this)
        });

        _validateOperators(operators);
        _grantRoleOperators(operators);
    }

    /**
     * @notice Function to test operator validation
     */
    function testValidateOperators(ProcessorAccessControl.RoleOperators memory operators) external pure {
        _validateOperators(operators);
    }

    /**
     * @notice Function to test role granting
     */
    function testGrantRoleOperators(ProcessorAccessControl.RoleOperators memory operators) external {
        _grantRoleOperators(operators);
    }

    /**
     * @notice Function to test pause functionality
     */
    function testPause() external {
        _pause();
    }

    /**
     * @notice Function to test unpause functionality
     */
    function testUnpause() external {
        _unpause();
    }
}

contract ProcessorAccessControlTest is Test {
    TestProcessorAccessControl public accessControl;

    address constant VALID_ADDRESS = 0x1234567890123456789012345678901234567890;
    address constant ZERO_ADDRESS = address(0);

    function setUp() public {
        accessControl = new TestProcessorAccessControl();
    }

    function test_Constants() public view {
        assertEq(accessControl.PAUSER_ROLE(), keccak256("PAUSER_ROLE"), "PAUSER_ROLE should match expected value");
        assertEq(accessControl.UNPAUSER_ROLE(), keccak256("UNPAUSER_ROLE"), "UNPAUSER_ROLE should match expected value");
        assertEq(
            accessControl.DISBURSER_ROLE(), keccak256("DISBURSER_ROLE"), "DISBURSER_ROLE should match expected value"
        );
        assertEq(
            accessControl.ACCOUNT_ROOT_PROVIDER_ROLE(),
            keccak256("ACCOUNT_ROOT_PROVIDER_ROLE"),
            "ACCOUNT_ROOT_PROVIDER_ROLE should match expected value"
        );
        assertEq(
            accessControl.VAULT_ROOT_PROVIDER_ROLE(),
            keccak256("VAULT_ROOT_PROVIDER_ROLE"),
            "VAULT_ROOT_PROVIDER_ROLE should match expected value"
        );
        assertEq(
            accessControl.TOKEN_MAPPING_MANAGER(),
            keccak256("TOKEN_MAPPING_MANAGER"),
            "TOKEN_MAPPING_MANAGER should match expected value"
        );
    }

    function test_PauseAndUnpause() public {
        // Initially should not be paused
        assertFalse(accessControl.paused(), "Contract should not be paused initially");

        // Pause the contract
        accessControl.testPause();
        assertTrue(accessControl.paused(), "Contract should be paused after pause()");

        // Unpause the contract
        accessControl.testUnpause();
        assertFalse(accessControl.paused(), "Contract should not be paused after unpause()");
    }

    function test_RevertIf_Pause_Unauthorized() public {
        // Test that pause() function requires PAUSER_ROLE
        // This test verifies the access control is working
        address unauthorizedAddress = 0x7FA9385bE102ac3EAc297483Dd6233D62b3e1496;

        // Try to pause from unauthorized address
        vm.prank(unauthorizedAddress);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                unauthorizedAddress,
                accessControl.PAUSER_ROLE()
            )
        );
        accessControl.pause();
    }

    function test_RevertIf_Unpause_Unauthorized() public {
        // Test that unpause() function requires UNPAUSER_ROLE
        // This test verifies the access control is working
        address unauthorizedAddress = 0x7FA9385bE102ac3EAc297483Dd6233D62b3e1496;

        // Try to unpause from unauthorized address
        vm.prank(unauthorizedAddress);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                unauthorizedAddress,
                accessControl.UNPAUSER_ROLE()
            )
        );
        accessControl.unpause();
    }

    function test_ValidateOperators_Valid() public {
        TestProcessorAccessControl newAccessControl = new TestProcessorAccessControl();

        ProcessorAccessControl.RoleOperators memory validOperators = ProcessorAccessControl.RoleOperators({
            accountRootProvider: VALID_ADDRESS,
            vaultRootProvider: VALID_ADDRESS,
            tokenMappingManager: VALID_ADDRESS,
            disburser: VALID_ADDRESS,
            pauser: VALID_ADDRESS,
            unpauser: VALID_ADDRESS,
            defaultAdmin: VALID_ADDRESS
        });

        // Should not revert
        newAccessControl.testValidateOperators(validOperators);
    }

    function test_RevertIf_ValidateOperators_InvalidAddresses() public {
        TestProcessorAccessControl newAccessControl = new TestProcessorAccessControl();

        // Test each operator being zero address
        address[] memory operators = new address[](7);
        operators[0] = VALID_ADDRESS; // accountRootProvider
        operators[1] = VALID_ADDRESS; // vaultRootProvider
        operators[2] = VALID_ADDRESS; // tokenMappingManager
        operators[3] = VALID_ADDRESS; // disburser
        operators[4] = VALID_ADDRESS; // pauser
        operators[5] = VALID_ADDRESS; // unpauser
        operators[6] = VALID_ADDRESS; // defaultAdmin

        for (uint256 i = 0; i < operators.length; i++) {
            operators[i] = ZERO_ADDRESS;

            ProcessorAccessControl.RoleOperators memory invalidOperators = ProcessorAccessControl.RoleOperators({
                accountRootProvider: operators[0],
                vaultRootProvider: operators[1],
                tokenMappingManager: operators[2],
                disburser: operators[3],
                pauser: operators[4],
                unpauser: operators[5],
                defaultAdmin: operators[6]
            });

            vm.expectRevert(ProcessorAccessControl.InvalidOperatorAddress.selector);
            newAccessControl.testValidateOperators(invalidOperators);

            // Reset for next iteration
            operators[i] = VALID_ADDRESS;
        }
    }

    function test_GrantRoleOperators() public {
        TestProcessorAccessControl newAccessControl = new TestProcessorAccessControl();

        // Grant roles to a new address
        ProcessorAccessControl.RoleOperators memory operators = ProcessorAccessControl.RoleOperators({
            accountRootProvider: VALID_ADDRESS,
            vaultRootProvider: VALID_ADDRESS,
            tokenMappingManager: VALID_ADDRESS,
            disburser: VALID_ADDRESS,
            pauser: VALID_ADDRESS,
            unpauser: VALID_ADDRESS,
            defaultAdmin: VALID_ADDRESS
        });

        newAccessControl.testGrantRoleOperators(operators);

        // Verify roles were granted
        assertTrue(
            newAccessControl.hasRole(newAccessControl.ACCOUNT_ROOT_PROVIDER_ROLE(), VALID_ADDRESS),
            "ACCOUNT_ROOT_PROVIDER_ROLE should be granted"
        );
        assertTrue(
            newAccessControl.hasRole(newAccessControl.VAULT_ROOT_PROVIDER_ROLE(), VALID_ADDRESS),
            "VAULT_ROOT_PROVIDER_ROLE should be granted"
        );
        assertTrue(
            newAccessControl.hasRole(newAccessControl.TOKEN_MAPPING_MANAGER(), VALID_ADDRESS),
            "TOKEN_MAPPING_MANAGER should be granted"
        );
        assertTrue(
            newAccessControl.hasRole(newAccessControl.DISBURSER_ROLE(), VALID_ADDRESS),
            "DISBURSER_ROLE should be granted"
        );
        assertTrue(
            newAccessControl.hasRole(newAccessControl.PAUSER_ROLE(), VALID_ADDRESS), "PAUSER_ROLE should be granted"
        );
        assertTrue(
            newAccessControl.hasRole(newAccessControl.UNPAUSER_ROLE(), VALID_ADDRESS), "UNPAUSER_ROLE should be granted"
        );
        assertTrue(
            newAccessControl.hasRole(newAccessControl.DEFAULT_ADMIN_ROLE(), VALID_ADDRESS),
            "DEFAULT_ADMIN_ROLE should be granted"
        );
    }

    function test_InitialState() public view {
        // Check that contract is not paused initially
        assertFalse(accessControl.paused(), "Contract should not be paused initially");

        // Check that roles are properly defined
        assertEq(accessControl.PAUSER_ROLE(), keccak256("PAUSER_ROLE"), "PAUSER_ROLE should be defined");
        assertEq(accessControl.UNPAUSER_ROLE(), keccak256("UNPAUSER_ROLE"), "UNPAUSER_ROLE should be defined");
        assertEq(accessControl.DISBURSER_ROLE(), keccak256("DISBURSER_ROLE"), "DISBURSER_ROLE should be defined");
    }

    function test_RoleManagement() public {
        // Test that roles are properly defined and accessible
        assertEq(accessControl.PAUSER_ROLE(), keccak256("PAUSER_ROLE"), "PAUSER_ROLE should be accessible");
        assertEq(accessControl.UNPAUSER_ROLE(), keccak256("UNPAUSER_ROLE"), "UNPAUSER_ROLE should be accessible");
        assertEq(accessControl.DISBURSER_ROLE(), keccak256("DISBURSER_ROLE"), "DISBURSER_ROLE should be accessible");
    }

    function test_ErrorSelector() public pure {
        // Test that error selector can be encoded
        bytes memory invalidOperatorError =
            abi.encodeWithSelector(ProcessorAccessControl.InvalidOperatorAddress.selector);
        assertTrue(invalidOperatorError.length > 0, "InvalidOperatorAddress error should be encodable");

        bytes4 expectedSelector = ProcessorAccessControl.InvalidOperatorAddress.selector;
        assertEq(bytes4(invalidOperatorError), expectedSelector, "InvalidOperatorAddress selector should match");
    }

    function test_PauseUnpauseCycle() public {
        // Test multiple pause/unpause cycles
        for (uint256 i = 0; i < 3; i++) {
            // Pause
            accessControl.testPause();
            assertTrue(
                accessControl.paused(),
                string(abi.encodePacked("Contract should be paused after cycle ", vm.toString(i)))
            );

            // Unpause
            accessControl.testUnpause();
            assertFalse(
                accessControl.paused(),
                string(abi.encodePacked("Contract should not be paused after cycle ", vm.toString(i)))
            );
        }
    }

    function test_RoleOperatorsStruct() public pure {
        // Test that RoleOperators struct can be created and accessed
        ProcessorAccessControl.RoleOperators memory operators = ProcessorAccessControl.RoleOperators({
            accountRootProvider: VALID_ADDRESS,
            vaultRootProvider: VALID_ADDRESS,
            tokenMappingManager: VALID_ADDRESS,
            disburser: VALID_ADDRESS,
            pauser: VALID_ADDRESS,
            unpauser: VALID_ADDRESS,
            defaultAdmin: VALID_ADDRESS
        });

        assertEq(operators.accountRootProvider, VALID_ADDRESS, "accountRootProvider should be set correctly");
        assertEq(operators.vaultRootProvider, VALID_ADDRESS, "vaultRootProvider should be set correctly");
        assertEq(operators.tokenMappingManager, VALID_ADDRESS, "tokenMappingManager should be set correctly");
        assertEq(operators.disburser, VALID_ADDRESS, "disburser should be set correctly");
        assertEq(operators.pauser, VALID_ADDRESS, "pauser should be set correctly");
        assertEq(operators.unpauser, VALID_ADDRESS, "unpauser should be set correctly");
        assertEq(operators.defaultAdmin, VALID_ADDRESS, "defaultAdmin should be set correctly");
    }

    function test_AccessControlInheritance() public view {
        // Test that AccessControl functionality is properly inherited
        // Test role getter
        assertEq(
            accessControl.getRoleAdmin(accessControl.PAUSER_ROLE()),
            bytes32(0),
            "Role admin should be zero for PAUSER_ROLE"
        );
        assertEq(
            accessControl.getRoleAdmin(accessControl.UNPAUSER_ROLE()),
            bytes32(0),
            "Role admin should be zero for UNPAUSER_ROLE"
        );
    }

    function test_PausableInheritance() public {
        // Test that Pausable functionality is properly inherited
        assertFalse(accessControl.paused(), "paused() should be inherited from Pausable");

        // Test pause/unpause functionality
        accessControl.testPause();
        assertTrue(accessControl.paused(), "pause() should be inherited from Pausable");

        accessControl.testUnpause();
        assertFalse(accessControl.paused(), "unpause() should be inherited from Pausable");
    }
}
