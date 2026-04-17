// Copyright Immutable Pty Ltd 2018 - 2025
// SPDX-License-Identifier: Apache-2.0.
pragma solidity ^0.8.27;

import {StarkExchangeMigration} from "./StarkExchangeMigration.sol";

/**
 * @title StarkExchangeMigrationV2
 * @notice Upgrades the StarkEx bridge to:
 *         1. Distribute VCO tokens to 7 holders who were missed during the original migration
 *            due to a bug in the VCO token's `approve` method.
 *         2. Register Stark key → Ethereum address associations for holders whose keys are not
 *            yet registered on-chain, enabling them to call `withdraw`.
 * @dev Populates `pendingWithdrawals` and `ethKeys` entries during initialization. Holders can then
 *      withdraw using the standard `withdraw(uint256, uint256)` function inherited from LegacyStarkExchangeBridge.
 *      All existing StarkExchangeMigration functionality is preserved.
 */
contract StarkExchangeMigrationV2 is StarkExchangeMigration {
    /// @notice VCO token asset type ID from the StarkEx system
    uint256 public constant VCO_ASSET_TYPE =
        1485183671027309009439509871835489442660821279230223034298428454062208985878;

    // -----------------------------------------------------------------------
    //  VCO holder data: Stark keys, Ethereum addresses, and quantized balances
    // -----------------------------------------------------------------------
    uint256 public constant HOLDER_1_KEY = 0x07d2ca42b17532a203fa5ed81a3a5abf5b16e05bd46b5583e05265b09a3f4753;
    address public constant HOLDER_1_ETH = 0x5eBb994EBC1c44815FbF2fA61a6E1f8368dcB0C7;
    uint256 public constant HOLDER_1_AMOUNT = 4900000000000;
    uint256 public constant HOLDER_2_KEY = 0x01fb73de41e5392ef06b02030759d30da7d4da9d64e31115a705e62127f9dcb0;
    address public constant HOLDER_2_ETH = 0x216e8577B504aC3dB213eDd261e47fffBb354248;
    uint256 public constant HOLDER_2_AMOUNT = 125000000000;
    uint256 public constant HOLDER_3_KEY = 0x052b2366397e911659836f1304d4fa9bf55188c0152ad2ff42fadc77a757b434;
    address public constant HOLDER_3_ETH = 0x10cbBBb225BBEA137aC01F0F6D91CDB126BccaA6;
    uint256 public constant HOLDER_3_AMOUNT = 7540000000;
    uint256 public constant HOLDER_4_KEY = 0x07c57cd4c9cf16ca3d66aa50278e7e4e2baeb55562f81553573cff7bdbeb3bcc;
    address public constant HOLDER_4_ETH = 0x409F85D2207796b543b8abdB6a0E2490BB1483D1;
    uint256 public constant HOLDER_4_AMOUNT = 4900000000000;
    uint256 public constant HOLDER_5_KEY = 0x00b59aa8b25d30099884e724376fe562e15bdc8c24eda4a6212edffc1c4e4958;
    address public constant HOLDER_5_ETH = 0xCE5A537D4dA620DE59efA6F74a0A065732600c71;
    uint256 public constant HOLDER_5_AMOUNT = 382500000000;
    uint256 public constant HOLDER_6_KEY = 0x025ee41b0f85758eab738070b553e0f966776481df6d3bc4c57858909080ca01;
    address public constant HOLDER_6_ETH = 0x941f54cb53Dc1478Cb126a2Ba8a83b2130419dB5;
    uint256 public constant HOLDER_6_AMOUNT = 266488641810000000;
    uint256 public constant HOLDER_7_KEY = 0x01a8f1faf9536efcf2bedf660c9f8d529ad07978812926823d29df617adb8df2;
    address public constant HOLDER_7_ETH = 0xBC6EeB5111fEa2B5e9B2Bc534bBcbCa9568999a4;
    uint256 public constant HOLDER_7_AMOUNT = 235000000000;

    /**
     * @notice Populates `pendingWithdrawals` with VCO token entries for the 7 holders and registers
     *         Stark key → Ethereum address associations for holders not yet registered on-chain.
     * @dev The bytes parameter is unused but required to match the parent function signature for StarkEx proxy compatibility.
     *      Uses `reinitializer(2)` because the parent's `initialize` used `initializer` (equivalent to
     *      reinitializer(1)). This ensures the function can only execute once.
     */
    function initialize(
        bytes calldata /* data */
    )
        external
        override
        reinitializer(2)
    {
        // Populate VCO pending withdrawals
        pendingWithdrawals[HOLDER_1_KEY][VCO_ASSET_TYPE] += HOLDER_1_AMOUNT;
        pendingWithdrawals[HOLDER_2_KEY][VCO_ASSET_TYPE] += HOLDER_2_AMOUNT;
        pendingWithdrawals[HOLDER_3_KEY][VCO_ASSET_TYPE] += HOLDER_3_AMOUNT;
        pendingWithdrawals[HOLDER_4_KEY][VCO_ASSET_TYPE] += HOLDER_4_AMOUNT;
        pendingWithdrawals[HOLDER_5_KEY][VCO_ASSET_TYPE] += HOLDER_5_AMOUNT;
        pendingWithdrawals[HOLDER_6_KEY][VCO_ASSET_TYPE] += HOLDER_6_AMOUNT;
        pendingWithdrawals[HOLDER_7_KEY][VCO_ASSET_TYPE] += HOLDER_7_AMOUNT;

        // Register Stark key → Ethereum address for holders not yet registered on-chain
        if (ethKeys[HOLDER_1_KEY] == address(0)) ethKeys[HOLDER_1_KEY] = HOLDER_1_ETH;
        if (ethKeys[HOLDER_2_KEY] == address(0)) ethKeys[HOLDER_2_KEY] = HOLDER_2_ETH;
        if (ethKeys[HOLDER_3_KEY] == address(0)) ethKeys[HOLDER_3_KEY] = HOLDER_3_ETH;
        if (ethKeys[HOLDER_4_KEY] == address(0)) ethKeys[HOLDER_4_KEY] = HOLDER_4_ETH;
        if (ethKeys[HOLDER_5_KEY] == address(0)) ethKeys[HOLDER_5_KEY] = HOLDER_5_ETH;
        if (ethKeys[HOLDER_6_KEY] == address(0)) ethKeys[HOLDER_6_KEY] = HOLDER_6_ETH;
        if (ethKeys[HOLDER_7_KEY] == address(0)) ethKeys[HOLDER_7_KEY] = HOLDER_7_ETH;
    }
}
