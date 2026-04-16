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
    //  Holder data: Stark keys and quantized amounts
    //  IMPORTANT: Replace these placeholder values with actual holder data
    //  before deployment. The Stark key is the ownerKey used to call withdraw().
    //  The amount is the QUANTIZED amount (actual amount = quantized * quantum).
    // -----------------------------------------------------------------------
    uint256 public constant HOLDER_1_KEY = 0x00AA00000000000000000000000000000000000001;
    uint256 public constant HOLDER_1_AMOUNT = 100;
    uint256 public constant HOLDER_2_KEY = 0x00AA00000000000000000000000000000000000002;
    uint256 public constant HOLDER_2_AMOUNT = 200;
    uint256 public constant HOLDER_3_KEY = 0x00AA00000000000000000000000000000000000003;
    uint256 public constant HOLDER_3_AMOUNT = 300;
    uint256 public constant HOLDER_4_KEY = 0x00AA00000000000000000000000000000000000004;
    uint256 public constant HOLDER_4_AMOUNT = 400;
    uint256 public constant HOLDER_5_KEY = 0x00AA00000000000000000000000000000000000005;
    uint256 public constant HOLDER_5_AMOUNT = 500;
    uint256 public constant HOLDER_6_KEY = 0x00AA00000000000000000000000000000000000006;
    uint256 public constant HOLDER_6_AMOUNT = 600;
    uint256 public constant HOLDER_7_KEY = 0x00AA00000000000000000000000000000000000007;
    uint256 public constant HOLDER_7_AMOUNT = 700;

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
