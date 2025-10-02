// Copyright Immutable Pty Ltd 2018 - 2025
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {BridgedTokenMapping} from "@src/assets/BridgedTokenMapping.sol";
import {IVaultProofVerifier} from "@src/verifiers/vaults/IVaultProofVerifier.sol";
import {VaultRootReceiver} from "./VaultRootReceiver.sol";
import {BaseVaultWithdrawalProcessor} from "./BaseVaultWithdrawalProcessor.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {AccountProofVerifier} from "../verifiers/accounts/AccountProofVerifier.sol";
import {ProcessorAccessControl} from "./ProcessorAccessControl.sol";
import {AccountRootReceiver} from "./AccountRootReceiver.sol";

contract VaultWithdrawalProcessor is
    BaseVaultWithdrawalProcessor,
    ReentrancyGuard,
    ProcessorAccessControl,
    VaultRootReceiver,
    AccountRootReceiver,
    AccountProofVerifier,
    BridgedTokenMapping
{
    using SafeERC20 for IERC20;

    /// @dev Upper bound for valid Stark keys (2^251 + 17 * 2^192 + 1)
    uint256 internal constant STARK_KEY_UPPER_BOUND = 0x800000000000011000000000000000000000000000000000000000000000001;

    uint256 public constant VAULT_PROOF_LENGTH = 68;
    uint256 public constant ACCOUNT_PROOF_LENGTH = 27;

    /// @notice The vault proof verifier contract
    IVaultProofVerifier public immutable VAULT_PROOF_VERIFIER;

    /// @notice Flag indicating whether the vault root can be overridden after initial setting
    bool public rootOverrideAllowed = false;

    /**
     * @notice Constructs the VaultWithdrawalProcessor contract
     * @param _vaultProofVerifier The address of the vault proof verifier contract
     * @param _operators The list of addresses to be granted specific roles
     * @param _rootOverrideAllowed Whether the vault and account roots can be overridden after initial setting
     */
    constructor(address _vaultProofVerifier, RoleOperators memory _operators, bool _rootOverrideAllowed) {
        require(_vaultProofVerifier != address(0), ZeroAddress());
        _validateOperators(_operators);

        VAULT_PROOF_VERIFIER = IVaultProofVerifier(_vaultProofVerifier);
        _grantRoleOperators(_operators);
        rootOverrideAllowed = _rootOverrideAllowed;
    }

    /**
     * @inheritdoc BaseVaultWithdrawalProcessor
     */
    function verifyAndProcessWithdrawal(
        address receiver,
        bytes32[] calldata accountProof,
        uint256[] calldata vaultProof
    ) external override onlyRole(DISBURSER_ROLE) nonReentrant whenNotPaused {
        // Check that the processor is configured with valid roots, to process withdrawals
        require(vaultRoot != 0, VaultRootNotSet());
        require(accountRoot != 0, AccountRootNotSet());

        require(receiver != address(0), ZeroAddress());
        require(accountProof.length == ACCOUNT_PROOF_LENGTH, InvalidAccountProof("Invalid account proof length"));
        require(
            vaultProof.length == VAULT_PROOF_LENGTH, IVaultProofVerifier.InvalidVaultProof("Invalid vault proof length")
        );

        // Extract the vault and vault root information from the submitted proof
        (IVaultProofVerifier.Vault memory vault, uint256 _vaultRoot) =
            VAULT_PROOF_VERIFIER.extractVaultAndRootFromProof(vaultProof);

        // Basic validation of the vault structure
        _validateVaultStructure(vault);

        // the submitted proof is not a proof against the stored vault root
        require(_vaultRoot == vaultRoot, IVaultProofVerifier.InvalidVaultProof("Invalid vault root"));

        // withdrawals can only be processed for registered assets
        address token = assetMappings[vault.assetId].tokenOnZKEVM;
        require(token != address(0), AssetNotRegistered(vault.assetId));

        // Ensure that this vault hasn't already been withdrawn/processed.
        require(
            !isWithdrawalProcessed(vault.starkKey, vault.assetId),
            WithdrawalAlreadyProcessed(vault.starkKey, vault.assetId)
        );

        _verifyAccountProof(vault.starkKey, receiver, accountRoot, accountProof);

        // Verify the vault escape proof
        require(
            VAULT_PROOF_VERIFIER.verifyVaultProof(vaultProof),
            IVaultProofVerifier.InvalidVaultProof("Invalid vault proof")
        );

        _registerProcessedWithdrawal(vault.starkKey, vault.assetId);

        uint256 transferredAmount = _transferFunds(receiver, vault.assetId, token, vault.quantizedBalance);
        emit WithdrawalProcessed(vault.starkKey, receiver, vault.assetId, token, transferredAmount);
    }

    /**
     * @notice Sets the vault root hash for proof verification
     * @dev Only the vault root provider can call this function
     * @dev The vault root can only be set once unless rootOverrideAllowed is true
     * @param newRoot The new vault root hash
     */
    function setVaultRoot(uint256 newRoot) external override onlyRole(VAULT_ROOT_PROVIDER_ROLE) {
        _setVaultRoot(newRoot, rootOverrideAllowed);
    }

    /**
     * @notice Sets the account root hash for proof verification
     * @dev Only the owner can call this function
     * @dev The account root can only be set once unless rootOverrideAllowed is true
     * @param newRoot The new Merkle root hash for account associations
     */
    function setAccountRoot(bytes32 newRoot) external override onlyRole(ACCOUNT_ROOT_PROVIDER_ROLE) {
        _setAccountRoot(newRoot, rootOverrideAllowed);
    }

    function setRootOverrideAllowed(bool allowed) external onlyRole(DEFAULT_ADMIN_ROLE) {
        rootOverrideAllowed = allowed;
    }

    function registerTokenMappings(TokenMapping[] calldata assets) external override onlyRole(TOKEN_MAPPING_MANAGER) {
        _registerTokenMappings(assets);
    }

    /**
     * @notice Receive function to accept native IMX funds
     */
    receive() external payable {}

    function _transferFunds(address recipient, uint256 assetId, address asset, uint256 quantizedBalance)
        internal
        returns (uint256)
    {
        // de-quantize the amount. An overflow here would mean the funds would permanently be locked for that vault. However,
        // this should never happen in practice given sanity checks around the quantum during token registration and the balance of every vault.
        uint256 transferAmount = quantizedBalance * assetMappings[assetId].tokenOnIMX.quantum;

        if (asset == NATIVE_IMX_ADDRESS) {
            Address.sendValue(payable(recipient), transferAmount);
        } else {
            IERC20 token = IERC20(asset);
            token.safeTransfer(recipient, transferAmount);
        }

        return transferAmount;
    }

    function _validateVaultStructure(IVaultProofVerifier.Vault memory vault) internal pure {
        require(
            vault.starkKey != 0 && vault.starkKey < STARK_KEY_UPPER_BOUND,
            IVaultProofVerifier.InvalidVaultProof("Invalid stark key")
        );
        require(vault.assetId != 0, IVaultProofVerifier.InvalidVaultProof("Invalid asset ID"));
        require(vault.quantizedBalance > 0, IVaultProofVerifier.InvalidVaultProof("Invalid quantized balance"));
    }
}
