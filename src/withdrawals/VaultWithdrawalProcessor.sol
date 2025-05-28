// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AssetsRegistry} from "@src/assets/AssetsRegistry.sol";
import {IAccountProofVerifier} from "@src/verifiers/accounts/IAccountProofVerifier.sol";
import {IVaultProofVerifier} from "@src/verifiers/vaults/IVaultProofVerifier.sol";
import {IVaultRootManager} from "./IVaultRootManager.sol";
import {IVaultWithdrawalProcessor} from "./IVaultWithdrawalProcessor.sol";
import {VaultWithdrawalsRegistry} from "./VaultWithdrawalsRegistry.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

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
    IVaultRootManager,
    AssetsRegistry,
    VaultWithdrawalsRegistry,
    ReentrancyGuard,
    Pausable,
    AccessControl
{
    using SafeERC20 for IERC20;

    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant UNPAUSER_ROLE = keccak256("UNPAUSER_ROLE");
    bytes32 public constant DISBURSER_ROLE = keccak256("DISBURSER_ROLE");

    IAccountProofVerifier public immutable accountProofVerifier;
    IVaultProofVerifier public immutable vaultProofVerifier;
    address public immutable vaultRootProvider;
    uint256 public vaultRoot;

    event WithdrawalProcessed(
        uint256 indexed starkKey, uint256 indexed assetId, uint256 amount, address recipient, address assetAddress
    );

    struct InitializationRoles {
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
        IAccountProofVerifier _accountProofVerifier,
        IVaultProofVerifier _vaultProofVerifier,
        address _vaultRootProvider,
        AssetDetails[] memory assets,
        InitializationRoles memory roles
    ) {
        require(address(_accountProofVerifier) != address(0), "Invalid account verifier address");
        require(address(_vaultProofVerifier) != address(0), "Invalid vault verifier address");
        require(_vaultRootProvider != address(0), "Invalid vault root provider address");

        accountProofVerifier = _accountProofVerifier;
        vaultProofVerifier = _vaultProofVerifier;
        vaultRootProvider = _vaultRootProvider;

        _registerAssets(assets);

        _grantRole(PAUSER_ROLE, roles.pauser);
        _grantRole(UNPAUSER_ROLE, roles.unpauser);
        _grantRole(DISBURSER_ROLE, roles.disburser);
        _grantRole(DEFAULT_ADMIN_ROLE, roles.defaultAdmin);
    }

    /*
     * @notice verifyProofAndDisburseFunds
     * @param ethAddress The Ethereum address of the vault owner. This is the address that will receive the funds, and should be the same as the one provable in the account proof.
     * @param accountProof The account proof to verify. This is the proof that the vault owner's stark key maps to the provided eth address.
     * @param vaultProof The vault proof to verify. This is the proof that the vault is valid.
     * @return bool Returns true if the proof is valid.
     */
    function verifyProofAndDisburseFunds(
        address ethAddress,
        bytes32[] calldata accountProof,
        uint256[] calldata vaultProof
    ) external onlyRole(DISBURSER_ROLE) whenNotPaused returns (bool) {
        (IVaultProofVerifier.Vault memory vault, uint256 root) =
            vaultProofVerifier.extractLeafAndRootFromProof(vaultProof);

        // verify that stark key, asset id are really 252bit numbers cast as 256 bit numbers
        require(
            vault.starkKey != 0 && vault.starkKey >> 252 == 0,
            IVaultProofVerifier.InvalidVaultProof("Invalid Stark key")
        );
        require(
            vault.assetId != 0 && vault.assetId >> 252 == 0, IVaultProofVerifier.InvalidVaultProof("Invalid asset ID")
        );
        require(vault.quantizedAmount != 0, IVaultProofVerifier.InvalidVaultProof("Invalid quantized amount"));

        require(root == vaultRoot, IVaultProofVerifier.InvalidVaultProof("Invalid root"));

        address assetAddress = getAssetAddress(vault.assetId);
        require(assetAddress != address(0), AssetNotRegistered(vault.assetId));

        // Ensure that the vault funds are not already claimed
        require(
            !isClaimProcessed(vault.starkKey, vault.assetId),
            FundAlreadyDisbursedForVault(vault.starkKey, vault.assetId)
        );
        // Verify the stark key and eth address association proof
        require(
            accountProofVerifier.verify(vault.starkKey, ethAddress, accountProof),
            IAccountProofVerifier.InvalidAccountProof(vault.starkKey, ethAddress)
        );

        // Verify the vault escape proof
        require(
            vaultProofVerifier.verifyProof(vaultProof), IVaultProofVerifier.InvalidVaultProof("Invalid vault proof")
        );

        _registerProcessedClaim(vault.starkKey, vault.assetId);

        // de-quantize the amount
        uint256 amountToTransfer = vault.quantizedAmount * getAssetQuantum(vault.assetId);

        _processFundTransfer(ethAddress, assetAddress, amountToTransfer);
        emit WithdrawalProcessed(vault.starkKey, vault.assetId, amountToTransfer, ethAddress, assetAddress);
        return true;
    }

    function setVaultRoot(uint256 _vaultRoot) external override whenNotPaused {
        require(msg.sender == vaultRootProvider, "Unauthorized: Only vault root provider can set the root");
        require(_vaultRoot != 0, InvalidVaultRoot());

        // Vault root can only be set once
        require(vaultRoot == 0, VaultRootAlreadySet());

        vaultRoot = _vaultRoot;

        emit VaultRootSet(_vaultRoot);
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(UNPAUSER_ROLE) {
        _unpause();
    }

    function _processFundTransfer(address recipient, address assetAddress, uint256 amountToTransfer)
        internal
        nonReentrant
    {
        if (assetAddress == NATIVE_IMX_ADDRESS) {
            uint256 contractBalance = address(this).balance;
            if (contractBalance < amountToTransfer) {
                revert InsufficientBalance(assetAddress, amountToTransfer, contractBalance);
            }
            (bool sent,) = recipient.call{value: amountToTransfer}("");
            if (!sent) {
                revert FundTransferFailed(recipient, assetAddress, amountToTransfer);
            }
        } else {
            IERC20 token = IERC20(assetAddress);
            uint256 contractBalance = token.balanceOf(address(this));
            if (contractBalance < amountToTransfer) {
                revert InsufficientBalance(assetAddress, amountToTransfer, contractBalance);
            }
            token.safeTransfer(recipient, amountToTransfer);
        }
    }

    // TODO: Consider externalising Vault
    receive() external payable {}
}
