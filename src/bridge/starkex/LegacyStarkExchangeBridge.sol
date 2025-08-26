// Copyright Immutable Pty Ltd 2018 - 2025
// SPDX-License-Identifier: Apache-2.0.
pragma solidity ^0.8.27;

import {MainStorage} from "./MainStorage.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Addresses} from "./libraries/Common.sol";

/**
 * @title Legacy StarkExchange Bridge
 * @notice This contract maintains part of the functionality of the old StarkExchange bridge, specifically the finalisation of pending withdrawals.
 */
abstract contract LegacyStarkExchangeBridge is MainStorage {
    using Addresses for address;
    using Addresses for address payable;

    /**
     * @notice Emitted when a withdrawal of an already pending withdrawal is finalised
     * @param ownerKey The Stark key of the vault owner
     * @param assetType The type of asset being withdrawn
     * @param nonQuantizedAmount The non-quantized amount withdrawn
     * @param quantizedAmount The quantized amount withdrawn
     * @param recipient The address receiving the withdrawn funds
     */
    event LogWithdrawalPerformed(
        uint256 ownerKey, uint256 assetType, uint256 nonQuantizedAmount, uint256 quantizedAmount, address recipient
    );

    /// @notice Version identifier for the contract
    string public constant VERSION = "StarkEx-IMX-Migration-1.0.0";

    /// @dev Mask for extracting address from uint256 (160 bits)
    uint256 internal constant MASK_ADDRESS = (1 << 160) - 1;

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
     * @notice Returns whether the contract is frozen
     * @return Always returns false as this contract is never frozen
     */
    function isFrozen() external pure returns (bool) {
        return false;
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
            // Default quantization, for NFTs
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
