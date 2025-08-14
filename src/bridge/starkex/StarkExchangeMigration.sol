// Copyright Immutable Pty Ltd 2018 - 2025
// SPDX-License-Identifier: Apache-2.0.
pragma solidity ^0.8.27;

import {MainStorage} from "./MainStorage.sol";
import "forge-std/console.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {IRootERC20Bridge} from "../zkEVM/IRootERC20Bridge.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IStarkExchangeMigration} from "./IStarkExchangeMigration.sol";
import {VaultRootSender} from "../messaging/VaultRootSender.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Addresses} from "./libraries/Common.sol";

/**
 * @title StarkExchangeMigration
 * @notice This contract enables the migration of remaining funds from the Immutable X StarkExchange bridge to Immutable zkEVM.
 * @dev The contract performs the following functions:
 *      - Enables communicating the latest vaults Merkle root data to a designated contract on Immutable zkEVM, which enables the correct and trust-less disbursal of funds to the intended recipients.
 *      - Enables an authorised entity to migrate ERC-20 tokens and ETH held by the StarkExchange bridge to Immutable zkEVM, for trust-less disbursal to their intended recipients.
 *      - Continues to allow the processing of pending withdrawals.
 */
contract StarkExchangeMigration is MainStorage, Initializable, IStarkExchangeMigration {
    using Addresses for address;
    using Addresses for address payable;

    /// @notice Version identifier for the contract
    string public constant VERSION = "StarkEx-IMX-Migration-1.0.0";

    /// @dev Mask for extracting address from uint256 (160 bits)
    uint256 internal constant MASK_ADDRESS = (1 << 160) - 1;
    /// @notice Constant representing native ETH
    address public constant NATIVE_ETH = address(0xeee);

    /// @dev Selector for ERC20 token type
    bytes4 internal constant ERC20_SELECTOR = bytes4(keccak256("ERC20Token(address)"));
    /// @dev Selector for ETH token type
    bytes4 internal constant ETH_SELECTOR = bytes4(keccak256("ETH()"));

    /// @dev Offset for selector in asset info
    uint256 internal constant SELECTOR_OFFSET = 0x20;
    /// @dev Size of selector in bytes
    uint256 internal constant SELECTOR_SIZE = 4;
    /// @dev Offset for token contract address in asset info
    uint256 internal constant TOKEN_CONTRACT_ADDRESS_OFFSET = SELECTOR_OFFSET + SELECTOR_SIZE;

    /**
     * @notice Modifier to restrict access to only the migration initiator
     * @dev Reverts with UnauthorizedMigrationInitiator if caller is not the migration initiator
     */
    modifier onlyMigrationManager() {
        require(msg.sender == migrationInitiator, UnauthorizedMigrationInitiator());
        _;
    }

    /**
     * @notice Initializes the contract with migration configuration
     * @param data Encoded initialization data containing addresses
     * @dev Can only be called once due to initializer modifier
     */
    function initialize(bytes calldata data) external initializer {
        (address _migrationInitiator, address _zkEVMBridge, address _vaultRootSender, address _l2VaultProcessor) =
            abi.decode(data, (address, address, address, address));

        require(_migrationInitiator != address(0), ZeroAddress());
        require(_zkEVMBridge != address(0), ZeroAddress());
        require(_vaultRootSender != address(0), ZeroAddress());
        require(_l2VaultProcessor != address(0), ZeroAddress());

        migrationInitiator = _migrationInitiator;
        zkEVMBridge = _zkEVMBridge;
        zkEVMVaultProcessor = _l2VaultProcessor;
        vaultRootSender = VaultRootSender(_vaultRootSender);
    }

    /**
     * @notice Returns whether the contract is frozen
     * @return Always returns false as this contract is never frozen
     */
    function isFrozen() external pure returns (bool) {
        return false;
    }

    /**
     * @notice Migrates the vault state to zkEVM by sending the vault root
     * @dev Only the migration initiator can call this function
     * @dev Requires a bridge fee to be sent with the transaction
     */
    function migrateVaultState() external payable override onlyMigrationManager {
        require(msg.value > 0, ZeroBridgeFee());
        vaultRootSender.sendVaultRoot{value: msg.value}(vaultRoot, msg.sender);
        emit VaultStateMigrationInitiated(vaultRoot, msg.sender);
    }

    /**
     * @notice Migrates ERC20 token holdings to zkEVM
     * @param token The ERC20 token to migrate
     * @param amount The amount of tokens to migrate
     * @dev Only the migration initiator can call this function
     * @dev Requires a bridge fee to be sent with the transaction
     */
    function migrateERC20Holdings(IERC20Metadata token, uint256 amount)
        external
        payable
        override
        onlyMigrationManager
    {
        _depositERC20ToZKEVMBridge(token, amount);
        emit ERC20HoldingMigrationInitiated(address(token), amount);
    }

    /**
     * @notice Migrates ETH holdings to zkEVM
     * @param amount The amount of ETH to migrate
     * @dev Only the migration initiator can call this function
     * @dev Requires a bridge fee to be sent with the transaction
     */
    function migrateETHHoldings(uint256 amount) external payable override onlyMigrationManager {
        _depositETHToZKEVMBridge(amount);
        emit ETHHoldingMigrationInitiated(amount);
    }

    /**
     * @notice Internal function to deposit ERC20 tokens to the zkEVM bridge
     * @param token The ERC20 token to deposit
     * @param amount The amount of tokens to deposit
     * @dev Validates inputs and transfers tokens to the zkEVM bridge
     */
    function _depositERC20ToZKEVMBridge(IERC20Metadata token, uint256 amount) private {
        require(address(token) != address(0), ZeroAddress());
        require(amount > 0, ZeroAmount());
        require(msg.value > 0, ZeroBridgeFee());

        uint256 balance = token.balanceOf(address(this));
        require(balance >= amount, InsufficientBalance());
        // Transfer the specified amount of tokens to the recipient
        token.approve(zkEVMBridge, amount);
        IRootERC20Bridge(zkEVMBridge).depositTo{value: msg.value}(token, zkEVMVaultProcessor, amount);
    }

    /**
     * @notice Internal function to deposit ETH to the zkEVM bridge
     * @param amount The amount of ETH to deposit
     * @dev Validates inputs and transfers ETH to the zkEVM bridge
     */
    function _depositETHToZKEVMBridge(uint256 amount) private {
        require(amount > 0, ZeroAmount());
        require(msg.value > 0, ZeroBridgeFee());

        uint256 balance = address(this).balance;
        require(balance >= amount, InsufficientBalance());

        IRootERC20Bridge(zkEVMBridge).depositToETH{value: amount + msg.value}(zkEVMVaultProcessor, amount);
    }

    /**
     * @notice Gets the withdrawal balance for a specific owner and asset
     * @param ownerKey The Stark key of the owner
     * @param assetId The asset ID to check
     * @return The withdrawal balance in non-quantized units
     */
    function getWithdrawalBalance(uint256 ownerKey, uint256 assetId) external view returns (uint256) {
        uint256 presumedAssetType = assetId;
        return _fromQuantized(presumedAssetType, pendingWithdrawals[ownerKey][assetId]);
    }

    /**
     * @notice Moves funds from the pending withdrawal account to the owner address
     * @dev This function can be called by anyone
     * @dev Can be called normally while frozen
     * @param ownerKey The Stark key of the owner
     * @param assetType The asset type to withdraw
     */
    function withdraw(uint256 ownerKey, uint256 assetType) external {
        address payable recipient = payable(strictGetEthKey(ownerKey));
        require(isFungibleAssetType(assetType), "NON_FUNGIBLE_ASSET_TYPE");
        uint256 assetId = assetType;
        // Fetch and clear quantized amount.
        uint256 quantizedAmount = pendingWithdrawals[ownerKey][assetId];
        pendingWithdrawals[ownerKey][assetId] = 0;

        // Transfer funds.
        _transferOut(recipient, assetType, quantizedAmount);
        emit LogWithdrawalPerformed(
            ownerKey, assetType, _fromQuantized(assetType, quantizedAmount), quantizedAmount, recipient
        );
    }

    /**
     * @notice Returns the Ethereum public key (address) that owns the given ownerKey
     * @dev If the ownerKey size is within the range of an Ethereum address (i.e. < 2**160)
     *      it returns the owner key itself. If the ownerKey is larger than a potential eth address,
     *      the eth address for which the starkKey was registered is returned, and 0 if the starkKey is not registered.
     * @dev Note - prior to version 4.0 this function reverted on an unregistered starkKey.
     *      For a variant of this function that reverts on an unregistered starkKey, use strictGetEthKey.
     * @param ownerKey The Stark key to look up
     * @return The Ethereum address associated with the Stark key
     */
    function getEthKey(uint256 ownerKey) public view returns (address) {
        address registeredEth = ethKeys[ownerKey];

        if (registeredEth != address(0x0)) {
            return registeredEth;
        }

        return ownerKey == (ownerKey & MASK_ADDRESS) ? address(uint160(ownerKey)) : address(0x0);
    }

    /**
     * @notice Same as getEthKey, but fails when a stark key is not registered
     * @param ownerKey The Stark key to look up
     * @return ethKey The Ethereum address associated with the Stark key
     * @dev Reverts if the Stark key is not registered
     */
    function strictGetEthKey(uint256 ownerKey) internal view returns (address ethKey) {
        ethKey = getEthKey(ownerKey);
        require(ethKey != address(0x0), "USER_UNREGISTERED");
    }

    /**
     * @notice Checks if the message sender is the owner of the given Stark key
     * @param ownerKey The Stark key to check
     * @return True if the message sender owns the Stark key
     */
    function isMsgSenderKeyOwner(uint256 ownerKey) internal view returns (bool) {
        return msg.sender == getEthKey(ownerKey);
    }

    /**
     * @notice Transfers funds from the exchange to recipient
     * @param recipient The address to receive the funds
     * @param assetType The type of asset to transfer
     * @param quantizedAmount The quantized amount to transfer
     * @dev Handles both ERC20 tokens and ETH transfers
     */
    function _transferOut(address payable recipient, uint256 assetType, uint256 quantizedAmount) internal {
        // Make sure we don't accidentally burn funds.
        require(recipient != address(0x0), "INVALID_RECIPIENT");
        uint256 amount = _fromQuantized(assetType, quantizedAmount);
        if (isERC20(assetType)) {
            if (quantizedAmount == 0) return;
            address tokenAddress = _extractContractAddress(assetType);
            IERC20 token = IERC20(tokenAddress);
            uint256 exchangeBalanceBefore = token.balanceOf(address(this));
            bytes memory callData = abi.encodeWithSelector(token.transfer.selector, recipient, amount);
            tokenAddress.safeTokenContractCall(callData);
            uint256 exchangeBalanceAfter = token.balanceOf(address(this));
            require(exchangeBalanceAfter <= exchangeBalanceBefore, "UNDERFLOW");
            // NOLINTNEXTLINE(incorrect-equality): strict equality needed.
            require(exchangeBalanceAfter == exchangeBalanceBefore - amount, "INCORRECT_AMOUNT_TRANSFERRED");
        } else if (isEther(assetType)) {
            if (quantizedAmount == 0) return;
            recipient.performEthTransfer(amount);
        } else {
            revert("UNSUPPORTED_TOKEN_TYPE");
        }
    }

    /**
     * @notice Extract the tokenSelector from assetInfo
     * @dev Works like bytes4 tokenSelector = abi.decode(assetInfo, (bytes4))
     *      but does not revert when assetInfo.length < SELECTOR_OFFSET
     * @param assetInfo The asset info bytes to extract selector from
     * @return selector The extracted token selector
     */
    function _extractTokenSelectorFromAssetInfo(bytes memory assetInfo) private pure returns (bytes4 selector) {
        assembly {
            selector :=
                and(
                    0xffffffff00000000000000000000000000000000000000000000000000000000,
                    mload(add(assetInfo, SELECTOR_OFFSET))
                )
        }
    }

    /**
     * @notice Gets the asset info for a given asset type
     * @param assetType The asset type to get info for
     * @return assetInfo The asset info bytes
     * @dev Reverts if the asset type is not registered
     */
    function getAssetInfo(uint256 assetType) public view returns (bytes memory assetInfo) {
        // Verify that the registration is set and valid.
        require(registeredAssetType[assetType], "ASSET_TYPE_NOT_REGISTERED");

        // Retrieve registration.
        assetInfo = assetTypeToAssetInfo[assetType];
    }

    /**
     * @notice Extracts the token selector from an asset type
     * @param assetType The asset type to extract selector from
     * @return The token selector
     */
    function _extractTokenSelectorFromAssetType(uint256 assetType) private view returns (bytes4) {
        return _extractTokenSelectorFromAssetInfo(getAssetInfo(assetType));
    }

    /**
     * @notice Checks if an asset type represents ETH
     * @param assetType The asset type to check
     * @return True if the asset type is ETH
     */
    function isEther(uint256 assetType) internal view returns (bool) {
        return _extractTokenSelectorFromAssetType(assetType) == ETH_SELECTOR;
    }

    /**
     * @notice Checks if an asset type represents an ERC20 token
     * @param assetType The asset type to check
     * @return True if the asset type is an ERC20 token
     */
    function isERC20(uint256 assetType) internal view returns (bool) {
        return _extractTokenSelectorFromAssetType(assetType) == ERC20_SELECTOR;
    }

    /**
     * @notice Extracts the contract address from asset info
     * @param assetInfo The asset info bytes
     * @return The contract address
     */
    function _extractContractAddressFromAssetInfo(bytes memory assetInfo) private pure returns (address) {
        uint256 offset = TOKEN_CONTRACT_ADDRESS_OFFSET;
        uint256 res;
        assembly {
            res := mload(add(assetInfo, offset))
        }
        return address(uint160(res));
    }

    /**
     * @notice Extracts the contract address from an asset type
     * @param assetType The asset type to extract address from
     * @return The contract address
     */
    function _extractContractAddress(uint256 assetType) internal view returns (address) {
        return _extractContractAddressFromAssetInfo(getAssetInfo(assetType));
    }

    /**
     * @notice Converts a quantized amount to a non-quantized amount
     * @param presumedAssetType The asset type for quantization
     * @param quantizedAmount The quantized amount to convert
     * @return amount The non-quantized amount
     * @dev Reverts if dequantization would overflow
     */
    function _fromQuantized(uint256 presumedAssetType, uint256 quantizedAmount)
        internal
        view
        returns (uint256 amount)
    {
        uint256 quantum = getQuantum(presumedAssetType);
        amount = quantizedAmount * quantum;
        require(amount / quantum == quantizedAmount, "DEQUANTIZATION_OVERFLOW");
    }

    /**
     * @notice Gets the quantum for an asset type
     * @param presumedAssetType The asset type to get quantum for
     * @return quantum The quantum value for the asset type
     * @dev Returns 1 as default quantum for unregistered asset types (e.g., NFTs)
     */
    function getQuantum(uint256 presumedAssetType) public view returns (uint256 quantum) {
        if (!registeredAssetType[presumedAssetType]) {
            // Default quantization, for NFTs etc.
            quantum = 1;
        } else {
            // Retrieve registration.
            quantum = assetTypeToQuantum[presumedAssetType];
        }
    }

    /**
     * @notice Checks if an asset type is fungible
     * @param assetType The asset type to check
     * @return True if the asset type is fungible (ETH or ERC20)
     */
    function isFungibleAssetType(uint256 assetType) internal view returns (bool) {
        bytes4 tokenSelector = _extractTokenSelectorFromAssetType(assetType);
        return tokenSelector == ETH_SELECTOR || tokenSelector == ERC20_SELECTOR;
    }
}
