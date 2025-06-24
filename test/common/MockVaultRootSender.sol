// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "@src/bridge/messaging/VaultRootSender.sol";

contract MockVaultRootSender {
    constructor() {}
    function sendVaultRoot(uint256, address) external payable {}
}
