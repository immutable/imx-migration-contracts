// Copyright Immutable Pty Ltd 2018 - 2025
// SPDX-License-Identifier: Apache-2.0.
pragma solidity ^0.8.27;

import {StarkExchangeMigration} from "./StarkExchangeMigration.sol";

/**
 * @title StarkExchangeVCODistribution
 * @notice Upgrades the StarkEx bridge to distribute VCO tokens to 7 holders who were missed during the
 *         original migration due to a bug in the VCO token's `approve` method.
 * @dev Populates `pendingWithdrawals` entries during initialization, allowing holders to withdraw
 *      using the standard `withdraw(uint256, uint256)` function inherited from LegacyStarkExchangeBridge.
 *      All existing StarkExchangeMigration functionality is preserved.
 */
contract StarkExchangeVCODistribution is StarkExchangeMigration {
    /// @notice VCO token asset type ID from the StarkEx system
    uint256 public constant VCO_ASSET_TYPE =
        1485183671027309009439509871835489442660821279230223034298428454062208985878;

    // -----------------------------------------------------------------------
    //  Holder data: Stark keys and quantized VCO balances
    // -----------------------------------------------------------------------
    uint256 public constant HOLDER_1_KEY = 0x07d2ca42b17532a203fa5ed81a3a5abf5b16e05bd46b5583e05265b09a3f4753;
    uint256 public constant HOLDER_1_AMOUNT = 4900000000000;
    uint256 public constant HOLDER_2_KEY = 0x01fb73de41e5392ef06b02030759d30da7d4da9d64e31115a705e62127f9dcb0;
    uint256 public constant HOLDER_2_AMOUNT = 125000000000;
    uint256 public constant HOLDER_3_KEY = 0x052b2366397e911659836f1304d4fa9bf55188c0152ad2ff42fadc77a757b434;
    uint256 public constant HOLDER_3_AMOUNT = 7540000000;
    uint256 public constant HOLDER_4_KEY = 0x07c57cd4c9cf16ca3d66aa50278e7e4e2baeb55562f81553573cff7bdbeb3bcc;
    uint256 public constant HOLDER_4_AMOUNT = 4900000000000;
    uint256 public constant HOLDER_5_KEY = 0x00b59aa8b25d30099884e724376fe562e15bdc8c24eda4a6212edffc1c4e4958;
    uint256 public constant HOLDER_5_AMOUNT = 382500000000;
    uint256 public constant HOLDER_6_KEY = 0x025ee41b0f85758eab738070b553e0f966776481df6d3bc4c57858909080ca01;
    uint256 public constant HOLDER_6_AMOUNT = 266488641810000000;
    uint256 public constant HOLDER_7_KEY = 0x01a8f1faf9536efcf2bedf660c9f8d529ad07978812926823d29df617adb8df2;
    uint256 public constant HOLDER_7_AMOUNT = 235000000000;

    /**
     * @notice Populates `pendingWithdrawals` with VCO token entries for the 7 holders.
     * @param data Unused — required to match the parent function signature for StarkEx proxy compatibility.
     * @dev Uses `reinitializer(2)` because the parent's `initialize` used `initializer` (equivalent to
     *      reinitializer(1)). This ensures the function can only execute once.
     */
    function initialize(bytes calldata data) external override reinitializer(2) {
        pendingWithdrawals[HOLDER_1_KEY][VCO_ASSET_TYPE] = HOLDER_1_AMOUNT;
        pendingWithdrawals[HOLDER_2_KEY][VCO_ASSET_TYPE] = HOLDER_2_AMOUNT;
        pendingWithdrawals[HOLDER_3_KEY][VCO_ASSET_TYPE] = HOLDER_3_AMOUNT;
        pendingWithdrawals[HOLDER_4_KEY][VCO_ASSET_TYPE] = HOLDER_4_AMOUNT;
        pendingWithdrawals[HOLDER_5_KEY][VCO_ASSET_TYPE] = HOLDER_5_AMOUNT;
        pendingWithdrawals[HOLDER_6_KEY][VCO_ASSET_TYPE] = HOLDER_6_AMOUNT;
        pendingWithdrawals[HOLDER_7_KEY][VCO_ASSET_TYPE] = HOLDER_7_AMOUNT;
    }
}
