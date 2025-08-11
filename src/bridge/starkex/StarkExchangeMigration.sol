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

    string public constant VERSION = "StarkEx-IMX-Migration-1.0.0";

    uint256 internal constant MASK_ADDRESS = (1 << 160) - 1;
    address public constant NATIVE_ETH = address(0xeee);

    bytes4 internal constant ERC20_SELECTOR = bytes4(keccak256("ERC20Token(address)"));
    bytes4 internal constant ETH_SELECTOR = bytes4(keccak256("ETH()"));

    // The selector follows the 0x20 bytes assetInfo.length field.
    uint256 internal constant SELECTOR_OFFSET = 0x20;
    uint256 internal constant SELECTOR_SIZE = 4;
    uint256 internal constant TOKEN_CONTRACT_ADDRESS_OFFSET = SELECTOR_OFFSET + SELECTOR_SIZE;

    modifier onlyMigrationInitiator() {
        require(msg.sender == migrationInitiator, UnauthorizedMigrationInitiator());
        _;
    }

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

    function isFrozen() external pure returns (bool) {
        return false;
    }

    function migrateVaultState() external payable override onlyMigrationInitiator {
        require(msg.value > 0, ZeroBridgeFee());
        vaultRootSender.sendVaultRoot{value: msg.value}(vaultRoot, msg.sender);
        emit VaultStateMigrationInitiated(vaultRoot, msg.sender);
    }

    function migrateERC20Holdings(IERC20Metadata token, uint256 amount)
        external
        payable
        override
        onlyMigrationInitiator
    {
        _depositERC20ToZKEVMBridge(token, amount);
        emit ERC20HoldingMigrationInitiated(address(token), amount);
    }

    function migrateETHHoldings(uint256 amount) external payable override onlyMigrationInitiator {
        _depositETHToZKEVMBridge(amount);
        emit ETHHoldingMigrationInitiated(amount);
    }

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

    function _depositETHToZKEVMBridge(uint256 amount) private {
        require(amount > 0, ZeroAmount());
        require(msg.value > 0, ZeroBridgeFee());

        uint256 balance = address(this).balance;
        require(balance >= amount, InsufficientBalance());

        IRootERC20Bridge(zkEVMBridge).depositToETH{value: amount + msg.value}(zkEVMVaultProcessor, amount);
    }

    function getWithdrawalBalance(uint256 ownerKey, uint256 assetId) external view returns (uint256) {
        uint256 presumedAssetType = assetId;
        return _fromQuantized(presumedAssetType, pendingWithdrawals[ownerKey][assetId]);
    }

    /*
      Moves funds from the pending withdrawal account to the owner address.
      Note: this function can be called by anyone.
      Can be called normally while frozen.
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

    /*
      Returns the Ethereum public key (address) that owns the given ownerKey.
      If the ownerKey size is within the range of an Ethereum address (i.e. < 2**160)
      it returns the owner key itself.

      If the ownerKey is larger than a potential eth address, the eth address for which the starkKey
      was registered is returned, and 0 if the starkKey is not registered.

      Note - prior to version 4.0 this function reverted on an unregistered starkKey.
      For a variant of this function that reverts on an unregistered starkKey, use strictGetEthKey.
    */
    function getEthKey(uint256 ownerKey) public view returns (address) {
        address registeredEth = ethKeys[ownerKey];

        if (registeredEth != address(0x0)) {
            return registeredEth;
        }

        return ownerKey == (ownerKey & MASK_ADDRESS) ? address(uint160(ownerKey)) : address(0x0);
    }

    /*
      Same as getEthKey, but fails when a stark key is not registered.
    */
    function strictGetEthKey(uint256 ownerKey) internal view returns (address ethKey) {
        ethKey = getEthKey(ownerKey);
        require(ethKey != address(0x0), "USER_UNREGISTERED");
    }

    function isMsgSenderKeyOwner(uint256 ownerKey) internal view returns (bool) {
        return msg.sender == getEthKey(ownerKey);
    }

    /*
      Transfers funds from the exchange to recipient.
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

    /*
      Extract the tokenSelector from assetInfo.

      Works like bytes4 tokenSelector = abi.decode(assetInfo, (bytes4))
      but does not revert when assetInfo.length < SELECTOR_OFFSET.
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

    function getAssetInfo(uint256 assetType) public view returns (bytes memory assetInfo) {
        // Verify that the registration is set and valid.
        require(registeredAssetType[assetType], "ASSET_TYPE_NOT_REGISTERED");

        // Retrieve registration.
        assetInfo = assetTypeToAssetInfo[assetType];
    }

    function _extractTokenSelectorFromAssetType(uint256 assetType) private view returns (bytes4) {
        return _extractTokenSelectorFromAssetInfo(getAssetInfo(assetType));
    }

    function isEther(uint256 assetType) internal view returns (bool) {
        return _extractTokenSelectorFromAssetType(assetType) == ETH_SELECTOR;
    }

    function isERC20(uint256 assetType) internal view returns (bool) {
        return _extractTokenSelectorFromAssetType(assetType) == ERC20_SELECTOR;
    }

    function _extractContractAddressFromAssetInfo(bytes memory assetInfo) private pure returns (address) {
        uint256 offset = TOKEN_CONTRACT_ADDRESS_OFFSET;
        uint256 res;
        assembly {
            res := mload(add(assetInfo, offset))
        }
        return address(uint160(res));
    }

    function _extractContractAddress(uint256 assetType) internal view returns (address) {
        return _extractContractAddressFromAssetInfo(getAssetInfo(assetType));
    }

    function _fromQuantized(uint256 presumedAssetType, uint256 quantizedAmount)
        internal
        view
        returns (uint256 amount)
    {
        uint256 quantum = getQuantum(presumedAssetType);
        amount = quantizedAmount * quantum;
        require(amount / quantum == quantizedAmount, "DEQUANTIZATION_OVERFLOW");
    }

    function getQuantum(uint256 presumedAssetType) public view returns (uint256 quantum) {
        if (!registeredAssetType[presumedAssetType]) {
            // Default quantization, for NFTs etc.
            quantum = 1;
        } else {
            // Retrieve registration.
            quantum = assetTypeToQuantum[presumedAssetType];
        }
    }

    function isFungibleAssetType(uint256 assetType) internal view returns (bool) {
        bytes4 tokenSelector = _extractTokenSelectorFromAssetType(assetType);
        return tokenSelector == ETH_SELECTOR || tokenSelector == ERC20_SELECTOR;
    }
}
