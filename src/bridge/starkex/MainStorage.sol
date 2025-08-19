// Copyright Immutable Pty Ltd 2018 - 2025
// SPDX-License-Identifier: Apache-2.0.
pragma solidity ^0.8.27;

import "./ProxyStorage.sol";
import "./libraries/Common.sol";
import {VaultRootSenderAdapter} from "../messaging/VaultRootSenderAdapter.sol";

/**
 * @title MainStorage
 * @notice Contract that holds ALL the main contract state (storage) variables
 * @dev This contract contains all the storage variables for the StarkEx migration system,
 *      including vault management, asset tracking, and migration functionality
 */
contract MainStorage is ProxyStorage {
    /// @dev Layout length constant for storage gap management
    uint256 internal constant LAYOUT_LENGTH = 2 ** 64;

    /// @notice Address of the escape verifier contract
    address escapeVerifierAddress; // NOLINT: constable-states.

    /// @notice Global flag indicating if the DEX state is frozen
    bool stateFrozen; // NOLINT: constable-states.

    /// @notice Time when unFreeze can be successfully called (UNFREEZE_DELAY after freeze)
    uint256 unFreezeTime; // NOLINT: constable-states.

    /// @notice Pending deposits mapping: STARK key => asset id => vault id => quantized amount
    mapping(uint256 => mapping(uint256 => mapping(uint256 => uint256))) pendingDeposits;

    /// @notice Cancellation requests mapping: STARK key => asset id => vault id => request timestamp
    mapping(uint256 => mapping(uint256 => mapping(uint256 => uint256))) cancellationRequests;

    /// @notice Pending withdrawals mapping: STARK key => asset id => quantized amount
    mapping(uint256 => mapping(uint256 => uint256)) pendingWithdrawals;

    /// @notice Mapping of vault_id => escape used boolean
    mapping(uint256 => bool) escapesUsed;

    /// @notice Number of escapes that were performed when frozen
    uint256 escapesUsedCount; // NOLINT: constable-states.

    /// @notice DEPRECATED: Full withdrawal requests mapping (replaced by forcedActionRequests)
    /// @dev NOLINTNEXTLINE naming-convention
    mapping(uint256 => mapping(uint256 => uint256)) fullWithdrawalRequests_DEPRECATED;

    /// @notice State sequence number
    uint256 sequenceNumber; // NOLINT: constable-states uninitialized-state.

    /// @notice Vaults Tree Root & Height
    uint256 public vaultRoot; // NOLINT: constable-states uninitialized-state.
    uint256 vaultTreeHeight; // NOLINT: constable-states uninitialized-state.

    /// @notice Order Tree Root & Height
    uint256 orderRoot; // NOLINT: constable-states uninitialized-state.
    uint256 orderTreeHeight; // NOLINT: constable-states uninitialized-state.

    /// @notice Mapping of addresses that are allowed to add tokens
    mapping(address => bool) tokenAdmins;

    /// @notice DEPRECATED: User admins mapping (no longer in use, remains for backwards compatibility)
    /// @dev NOLINTNEXTLINE naming-convention
    mapping(address => bool) userAdmins_DEPRECATED;

    /// @notice Mapping of addresses that are operators (allowed to update state)
    mapping(address => bool) operators;

    /// @notice Mapping of contract ID to asset data
    mapping(uint256 => bytes) assetTypeToAssetInfo; // NOLINT: uninitialized-state.

    /// @notice Mapping of registered contract IDs
    mapping(uint256 => bool) registeredAssetType; // NOLINT: uninitialized-state.

    /// @notice Mapping from contract ID to quantum
    mapping(uint256 => uint256) assetTypeToQuantum; // NOLINT: uninitialized-state.

    /// @notice DEPRECATED: Stark keys mapping (no longer in use, remains for backwards compatibility)
    /// @dev NOLINTNEXTLINE naming-convention
    mapping(address => uint256) starkKeys_DEPRECATED;

    /// @notice Mapping from STARK public key to the Ethereum public key of its owner
    mapping(uint256 => address) ethKeys; // NOLINT: uninitialized-state.

    /// @notice Timelocked state transition and availability verification chain
    StarkExTypes.ApprovalChainData verifiersChain;
    StarkExTypes.ApprovalChainData availabilityVerifiersChain;

    /// @notice Batch id of last accepted proof
    uint256 lastBatchId; // NOLINT: constable-states uninitialized-state.

    /// @notice Mapping between sub-contract index to sub-contract address
    mapping(uint256 => address) subContracts; // NOLINT: uninitialized-state.

    /// @notice DEPRECATED: Permissive asset type mapping (no longer in use, remains for backwards compatibility)
    /// @dev NOLINTNEXTLINE naming-convention
    mapping(uint256 => bool) permissiveAssetType_DEPRECATED;
    // ---- END OF MAIN STORAGE AS DEPLOYED IN STARKEX2.0 ----

    /// @notice Onchain-data version configured for the system
    uint256 onchainDataVersion; // NOLINT: constable-states uninitialized-state.

    /// @notice Counter of forced action request in block. The key is the block number
    mapping(uint256 => uint256) forcedRequestsInBlock;

    /// @notice ForcedAction requests: actionHash => requestTime
    mapping(bytes32 => uint256) forcedActionRequests;

    /// @notice Mapping for timelocked actions: actionKey => activation time
    mapping(bytes32 => uint256) actionsTimeLock;

    /// @notice Append only list of requested forced action hashes
    bytes32[] actionHashList;

    /// @notice Address of the zkEVM bridge contract
    address public zkEVMBridge; // NOLINT: constable-states uninitialized-state.
    /// @notice Address of the zkEVM vault processor contract
    address public zkEVMWithdrawalProcessor; // NOLINT: constable-states uninitialized-state.
    /// @notice Address of the migration initiator
    address public migrationManager; // NOLINT: constable-states uninitialized-state.
    /// @notice The vault root sender contract for cross-chain messaging
    VaultRootSenderAdapter public rootSenderAdapter; // NOLINT: constable-states uninitialized-state.

    /// @notice Reserved storage space for Extensibility
    /// @dev Every added variable MUST be added above the end gap, and the __endGap size must be reduced accordingly
    /// @dev NOLINTNEXTLINE: naming-convention
    uint256[LAYOUT_LENGTH - 41] private __endGap; // __endGap complements layout to LAYOUT_LENGTH.
}
