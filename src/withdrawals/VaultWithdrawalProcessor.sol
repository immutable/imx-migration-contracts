// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AssetMappingRegistry} from "@src/assets/AssetMappingRegistry.sol";
import {IAccountProofVerifier} from "@src/verifiers/accounts/IAccountProofVerifier.sol";
import {IVaultProofVerifier} from "@src/verifiers/vaults/IVaultProofVerifier.sol";
import {VaultRootStore} from "./VaultRootStore.sol";
import {IVaultWithdrawalProcessor} from "./IVaultWithdrawalProcessor.sol";
import {ProcessedWithdrawalsRegistry} from "./ProcessedWithdrawalsRegistry.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {AssetMappingRegistry} from "../assets/AssetMappingRegistry.sol";

/**
 * @title VaultEscapeProcessor
 * @notice This contract is used to process vault escape claims and disburse funds to the owner of the vault.
 * It performs the following steps:
 * 1. Given a vault escape proof and an account proof.
 * 2. Verify the account proof using the account proof verifier.
 * 3. Verify the vault root using the vault proof verifier.
 * 4. Register the processed claim using the vault claims registry.
 * 5. Disburse the funds to the recipient.
 * FIXME:
 * - The vault root will be set by the bridge, through a cross-chain message from the L1 contract, not during construction
 * - Pauseability and AccessControl should be added to the contract
 * - Consider having a readiness state to prevent processing claims before the bridge is ready (has funds, has root, has assets)
 */
contract VaultWithdrawalProcessor is
    IVaultWithdrawalProcessor,
    VaultRootStore,
    AssetMappingRegistry,
    ProcessedWithdrawalsRegistry,
    ReentrancyGuard,
    Pausable,
    AccessControl
{
    using SafeERC20 for IERC20;

    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant UNPAUSER_ROLE = keccak256("UNPAUSER_ROLE");
    bytes32 public constant DISBURSER_ROLE = keccak256("DISBURSER_ROLE");

    IAccountProofVerifier public immutable accountVerifier;
    IVaultProofVerifier public immutable vaultVerifier;

    event WithdrawalProcessed(
        uint256 indexed starkKey,
        uint256 indexed assetId,
        address indexed recipient,
        uint256 amount,
        address assetAddress
    );

    struct Operators {
        address pauser;
        address unpauser;
        address disburser;
        address defaultAdmin;
    }

    /*
     * @notice constructor
     * @param _accountVerifier The address of the account proof verifier contract.
     * @param _vaultVerifier The address of the vault proof verifier contract.
     * @param _vaultRoot The root of the vault to verify proofs against.
     * @param assets The mapping of assets on Immutable X to zkEVM assets.
     */
    constructor(
        IAccountProofVerifier _accountVerifier,
        IVaultProofVerifier _vaultVerifier,
        address _vaultRootProvider,
        AssetDetails[] memory assets,
        Operators memory operators
    ) VaultRootStore(_vaultRootProvider) {
        require(address(_accountVerifier) != address(0), "Invalid account verifier address");
        require(address(_vaultVerifier) != address(0), "Invalid vault verifier address");

        accountVerifier = _accountVerifier;
        vaultVerifier = _vaultVerifier;

        _registerAssetMappings(assets);

        _grantRole(PAUSER_ROLE, operators.pauser);
        _grantRole(UNPAUSER_ROLE, operators.unpauser);
        _grantRole(DISBURSER_ROLE, operators.disburser);
        _grantRole(DEFAULT_ADMIN_ROLE, operators.defaultAdmin);
    }

    /*
     * @notice verifyAndProcessWithdrawal
     * @param ethAddress The Ethereum address of the vault owner. This is the address that will receive the funds, and should be the same as the one provable in the account proof.
     * @param accountProof The account proof to verify. This is the proof that the vault owner's stark key maps to the provided eth address.
     * @param vaultProof The vault proof to verify. This is the proof that the vault is valid.
     * @return bool Returns true if the proof is valid.
     */
    function verifyAndProcessWithdrawal(
        address ethAddress,
        bytes32[] calldata accountProof,
        uint256[] calldata vaultProof
    ) external onlyRole(DISBURSER_ROLE) whenNotPaused returns (bool) {
        require(ethAddress != address(0), "Address cannot be zero");
        require(accountProof.length > 0, IAccountProofVerifier.InvalidAccountProof("Account proof is empty"));
        require(vaultProof.length > 0, IVaultProofVerifier.InvalidVaultProof("Vault proof is empty"));

        // Get the vault and vault root information from the submitted proof
        (IVaultProofVerifier.Vault memory vault, uint256 root) = vaultVerifier.extractLeafAndRootFromProof(vaultProof);

        // the submitted proof is not a proof against the known vault root
        require(root == vaultRoot, IVaultProofVerifier.InvalidVaultProof("Invalid root"));

        // withdrawals can only be processed for vaults with a non-zero balance
        require(vault.quantizedAmount != 0, IVaultProofVerifier.InvalidVaultProof("Invalid quantized amount"));

        // withdrawals can only be processed for known assets
        address assetAddress = getMappedAssetAddress(vault.assetId);
        require(assetAddress != address(0), AssetNotRegistered(vault.assetId));

        // Ensure that this vault hasn't already been withdrawn/processed.
        require(
            !isWithdrawalProcessed(vault.starkKey, vault.assetId),
            WithdrawalAlreadyProcessed(vault.starkKey, vault.assetId)
        );

        // Verify the stark key and eth address association proof
        require(
            accountVerifier.verify(vault.starkKey, ethAddress, accountProof),
            IAccountProofVerifier.InvalidAccountProof("Proof verification failed")
        );

        // Verify the vault escape proof
        require(vaultVerifier.verifyProof(vaultProof), IVaultProofVerifier.InvalidVaultProof("Invalid vault proof"));

        _registerProcessedWithdrawal(vault.starkKey, vault.assetId);

        // de-quantize the amount
        uint256 assetQuantum = getMappedAssetDetails(vault.assetId).assetOnIMX.quantum;
        uint256 amountToTransfer = vault.quantizedAmount * assetQuantum;

        _processFundTransfer(ethAddress, assetAddress, amountToTransfer);
        emit WithdrawalProcessed(vault.starkKey, vault.assetId, ethAddress, amountToTransfer, assetAddress);
        return true;
    }

    function setVaultRoot(uint256 newRoot) external override whenNotPaused {
        _setVaultRoot(newRoot);
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(UNPAUSER_ROLE) {
        _unpause();
    }

    function _processFundTransfer(address recipient, address asset, uint256 amount) internal nonReentrant {
        if (asset == NATIVE_IMX_ADDRESS) {
            uint256 currentBalance = address(this).balance;
            if (currentBalance < amount) {
                revert InsufficientBalance(asset, amount, currentBalance);
            }
            (bool sent,) = recipient.call{value: amount}("");
            if (!sent) {
                revert FundTransferFailed(recipient, asset, amount);
            }
        } else {
            IERC20 token = IERC20(asset);
            uint256 currentBalance = token.balanceOf(address(this));
            if (currentBalance < amount) {
                revert InsufficientBalance(asset, amount, currentBalance);
            }
            token.safeTransfer(recipient, amount);
        }
    }

    // TODO: Consider externalising Vault
    receive() external payable {}
}
