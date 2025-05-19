// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {AssetsRegistry} from "../assets/AssetsRegistry.sol";
import {IAccountProofVerifier} from "../proofs/accounts/IAccountProofVerifier.sol";
import {IVaultEscapeProofVerifier} from "../proofs/vaults/IVaultEscapeProofVerifier.sol";
import {VaultClaimsRegistry} from "./VaultClaimsRegistry.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IVaultEscapeProcessor} from "./IVaultEscapeProcessor.sol";

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
 * - Pausability and AccessControl should be added to the contract
 * - Consider having a readiness state to prevent processing claims before the bridge is ready (has funds, has root, has assets)
 */
contract VaultEscapeProcessor is IVaultEscapeProcessor, AssetsRegistry, VaultClaimsRegistry, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IAccountProofVerifier public immutable accountVerifier;
    IVaultEscapeProofVerifier public immutable vaultVerifier;
    uint256 public immutable vaultRoot;

    event WithdrawalProcessed(
        uint256 indexed starkKey, uint256 indexed assetId, uint256 amount, address recipient, address assetAddress
    );

    /*
     * @notice constructor
     * @param _accountVerifier The address of the account proof verifier contract.
     * @param _vaultVerifier The address of the vault proof verifier contract.
     * @param _vaultRoot The root of the vault to verify proofs against.
     * @param assets The mapping of assets on Immutable X to zkEVM assets.
     */
    constructor(address _accountVerifier, address _vaultVerifier, uint256 _vaultRoot, AssetDetails[] memory assets) {
        require(_vaultRoot != 0, InvalidVaultRoot(_vaultRoot, "Vault root cannot be zero"));
        vaultRoot = _vaultRoot;

        accountVerifier = IAccountProofVerifier(_accountVerifier);
        vaultVerifier = IVaultEscapeProofVerifier(_vaultVerifier);

        _registerAssets(assets);
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
    ) external returns (bool) {
        (IVaultEscapeProofVerifier.Vault memory vault, uint256 root) =
            vaultVerifier.extractLeafAndRootFromProof(vaultProof);

        // verify that stark key, asset id are really 252bit numbers cast as 256 bit numbers
        require(vault.starkKey != 0 && vault.starkKey >> 252 == 0, InvalidVaultProof("Invalid Stark key"));
        require(vault.assetId != 0 && vault.assetId >> 252 == 0, InvalidVaultProof("Invalid asset ID"));
        require(vault.quantizedAmount != 0, InvalidVaultProof("Invalid quantized amount"));

        require(root == vaultRoot, InvalidVaultProof("Invalid root"));

        address assetAddress = getAssetAddress(vault.assetId);
        require(assetAddress != address(0), AssetNotRegistered(vault.assetId));

        // Ensure that the vault funds are not already claimed
        require(
            !isClaimProcessed(vault.starkKey, vault.assetId),
            FundAlreadyDisbursedForVault(vault.starkKey, vault.assetId)
        );
        // Verify the stark key and eth address association proof
        require(
            accountVerifier.verify(vault.starkKey, ethAddress, accountProof),
            InvalidAccountProof(vault.starkKey, ethAddress)
        );

        // Verify the vault escape proof
        require(vaultVerifier.verifyEscapeProof(vaultProof), InvalidVaultProof("Invalid vault proof"));

        _registerProcessedClaim(vault.starkKey, vault.assetId);

        // de-quantize the amount
        uint256 amountToTransfer = vault.quantizedAmount * getAssetQuantum(vault.assetId);

        _processFundTransfer(ethAddress, assetAddress, amountToTransfer);
        emit WithdrawalProcessed(vault.starkKey, vault.assetId, amountToTransfer, ethAddress, assetAddress);
        return true;
    }

    function _processFundTransfer(address recipient, address assetAddress, uint256 amountToTransfer)
        internal
        nonReentrant
    {
        if (assetAddress == NATIVE_IMX_ADDRESS) {
            uint256 contractBalance = address(this).balance;
            if (contractBalance < amountToTransfer) {
                revert InsufficientContractBalance(assetAddress, amountToTransfer, contractBalance);
            }
            (bool sent,) = recipient.call{value: amountToTransfer}("");
            if (!sent) {
                revert TransferFailed(recipient, assetAddress, amountToTransfer);
            }
        } else {
            IERC20 token = IERC20(assetAddress);
            uint256 contractBalance = token.balanceOf(address(this));
            if (contractBalance < amountToTransfer) {
                revert InsufficientContractBalance(assetAddress, amountToTransfer, contractBalance);
            }
            token.safeTransfer(recipient, amountToTransfer);
        }
    }

    // TODO: Consider externalising Vault
    receive() external payable {}
}
