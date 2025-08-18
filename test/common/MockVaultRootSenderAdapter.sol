// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "@src/bridge/messaging/VaultRootSenderAdapter.sol";

contract MockVaultRootSenderAdapter {
    constructor() {}
    function sendVaultRoot(uint256, address) external payable {}
}
