// Copyright Immutable Pty Ltd 2018 - 2025
// SPDX-License-Identifier: Apache-2.0.
pragma solidity ^0.8.27;

import {GovernanceStorage} from "./GovernanceStorage.sol";

/*
 * NOTE: This code is imported as is from starkex-contracts repository:
 * https://github.com/starkware-libs/starkex-contracts/blob/f4ed79bb04b56d587618c24312e87d81e4efc56b/scalable-dex/contracts/src/upgrade/ProxyStorage.sol
 */

/**
 * @title ProxyStorage
 * @notice Contract that holds Proxy-specific state variables
 * @dev This contract is inherited by the GovernanceStorage (and indirectly by MainStorage)
 *      to prevent collision hazard between different storage contracts
 */
contract ProxyStorage is GovernanceStorage {
    /// @notice DEPRECATED: Mapping of addresses to initialization hashes
    /// @dev NOLINTNEXTLINE: naming-convention uninitialized-state - this is intentional as it's a storage contract
    mapping(address => bytes32) internal initializationHash_DEPRECATED;

    /// @notice NO_LONGER_USED: Mapping of implementation hashes to their enabled time
    /// @dev The time after which we can switch to the implementation
    /// @dev Hash(implementation, data, finalize) => time
    mapping(bytes32 => uint256) internal enabledTime;

    /// @notice Central storage of flags indicating whether implementations have been initialized
    /// @dev Can be used flexibly enough to accommodate multiple levels of initialization
    ///      (i.e. using different key salting schemes for different initialization levels)
    mapping(bytes32 => bool) internal initialized;
}
