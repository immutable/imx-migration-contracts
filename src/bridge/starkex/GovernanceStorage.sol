// Copyright Immutable Pty Ltd 2018 - 2025
// SPDX-License-Identifier: Apache-2.0.
pragma solidity ^0.8.27;

/*
 * NOTE: This code is imported as is from starkex-contracts repository:
 * https://github.com/starkware-libs/starkex-contracts/blob/f4ed79bb04b56d587618c24312e87d81e4efc56b/scalable-dex/contracts/src/components/GovernanceStorage.sol
 */

/**
 * @notice Struct containing governance information for a specific entity
 * @param effectiveGovernors Mapping of addresses to their governor status
 * @param candidateGovernor Address of the candidate governor waiting to be confirmed
 * @param initialized Flag indicating whether the governance has been initialized
 */
struct GovernanceInfoStruct {
    mapping(address => bool) effectiveGovernors;
    address candidateGovernor;
    bool initialized;
}

/**
 * @title GovernanceStorage
 * @notice Contract that holds governance slots for all entities, including proxy and main contracts
 * @dev This contract provides a centralized storage for governance information across multiple entities
 */
contract GovernanceStorage {
    /// @notice Mapping from governor tag to its corresponding GovernanceInfoStruct
    /// @dev NOLINT uninitialized-state - this is intentional as it's a storage contract
    mapping(string => GovernanceInfoStruct) internal governanceInfo;
}
