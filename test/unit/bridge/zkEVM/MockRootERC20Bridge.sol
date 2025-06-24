// Copyright Immutable Pty Ltd 2018 - 2023
// SPDX-License-Identifier: Apache 2.0
pragma solidity 0.8.27;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IRootERC20Bridge} from "../../../../src/bridge/zkEVM/IRootERC20Bridge.sol";

/**
 * @title Root ERC20 Bridge Interface
 * @notice Defines the key functions of an ERC20 bridge on the root chain, which enables bridging of standard ERC20 tokens, ETH, wETH, IMX and wIMX from the root chain to the child chain and back.
 * @dev Features:
 *     - Maps tokens from the root chain to the child chain.
 *     - Deposits tokens from the root chain to the child chain.
 *     - Deposits native ETH from the root chain to the child chain.
 */
contract MockRootERC20Bridge is IRootERC20Bridge {
    /**
     * @notice Deposit tokens to the bridge and issue corresponding tokens to `msg.sender` on the child chain.
     * @custom:requires `rootToken` should already have been mapped with `mapToken()`.
     * @param rootToken The address of the token on the root chain.
     * @param amount The amount of tokens to deposit.
     * @dev The function is `payable` because the message passing protocol requires a fee to be paid.
     */
    function deposit(IERC20Metadata rootToken, uint256 amount) external payable override {
        // This is a mock function, so we do not implement any logic here.
        // In a real implementation, this would handle the deposit logic.
    }

    /**
     * @notice Deposit tokens to the bridge and issue corresponding tokens to `receiver` address on the child chain.
     * @custom:requires `rootToken` should already have been mapped with `mapToken()`.
     * @param rootToken The address of the token on the root chain.
     * @param receiver The address of the receiver on the child chain, to credit tokens to.
     * @param amount The amount of tokens to deposit.
     * @dev The function is `payable` because the message passing protocol requires a fee to be paid.
     */
    function depositTo(IERC20Metadata rootToken, address receiver, uint256 amount) external payable override {
        // This is a mock function, so we do not implement any logic here.
        // In a real implementation, this would handle the deposit logic.
    }

    /**
     * @notice Deposit ETH to the bridge and issue corresponding wrapped ETH to `msg.sender` on the child chain.
     * @param amount The amount of tokens to deposit.
     * @dev The function is `payable` because the message passing protocol requires a fee to be paid.
     * @dev the `msg.value` provided should cover the amount to send as well as the bridge fee.
     */
    function depositETH(uint256 amount) external payable override {}
    /**
     * @notice Deposit ETH to the bridge and issue corresponding wrapped ETH to `receiver` address on the child chain.
     * @param receiver The address of the receiver on the child chain.
     * @param amount The amount of tokens to deposit.
     * @dev The function is `payable` because the message passing protocol requires a fee to be paid.
     * @dev the `msg.value` provided should cover the amount to send as well as the bridge fee.
     */
    function depositToETH(address receiver, uint256 amount) external payable override {}
}
