// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {AxelarExecutable} from "@axelar-gmp-sdk-solidity/executable/AxelarExecutable.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import "@src/withdrawals/IVaultRootStore.sol";

/**
 * @title VaultRootReceiver
 * This contract receives a message from the corresponding L1 contract.
 * The message includes vault root information and asset registration related details
 */
contract VaultRootReceiver is AxelarExecutable {
    error InvalidSourceChain();
    error InvalidSourceAddress();
    error InvalidVaultRoot();

    IVaultRootStore public immutable stateManager;
    string public vaultSourceChain;
    string public vaultStateSender;

    constructor(
        IVaultRootStore _stateManager,
        string memory _vaultStateSender,
        string memory _vaultSourceChain,
        address _axelarGateway
    ) AxelarExecutable(_axelarGateway) {
        require(address(_stateManager) != address(0), "Invalid withdrawal processer address");
        require(bytes(_vaultSourceChain).length != 0, "Invalid vault source chain ID");
        require(bytes(_vaultStateSender).length != 0, "Invalid vault source address");

        // Register the vault state sender as a trusted source for messages
        stateManager = _stateManager;
        vaultSourceChain = _vaultSourceChain;
        vaultStateSender = _vaultStateSender;
    }

    function _execute(bytes32, string calldata _sourceChain, string calldata _sourceAddress, bytes calldata _payload)
        internal
        override
    {
        require(Strings.equal(_sourceChain, vaultSourceChain), InvalidSourceChain());
        require(Strings.equal(_sourceAddress, vaultStateSender), InvalidSourceAddress());

        (uint256 vaultRoot) = abi.decode(_payload, (uint256));

        require(vaultRoot != 0, InvalidVaultRoot());

        stateManager.setVaultRoot(vaultRoot);
    }
}
