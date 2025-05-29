// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {AxelarExecutable} from "@axelar-gmp-sdk-solidity/executable/AxelarExecutable.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import "@src/withdrawals/VaultRootStore.sol";

/**
 * @title VaultRootReceiver
 * This contract receives a message from the corresponding L1 contract.
 * The message includes vault root information and asset registration related details
 */
contract VaultRootReceiver is AxelarExecutable {
    error InvalidSourceChain();
    error InvalidSourceAddress();

    VaultRootStore public immutable vaultRootStore;
    string public rootProviderChain;
    string public rootProviderContract;

    constructor(
        VaultRootStore _vaultRootStore,
        string memory _rootProviderChain,
        string memory _rootProviderContract,
        address _axelarGateway
    ) AxelarExecutable(_axelarGateway) {
        require(bytes(_rootProviderChain).length != 0, "Invalid vault source chain ID");
        require(bytes(_rootProviderContract).length != 0, "Invalid vault source address");

        require(address(_vaultRootStore) != address(0), "Invalid withdrawal processer address");

        // Register the vault state sender as a trusted source for messages
        rootProviderChain = _rootProviderChain;
        rootProviderContract = _rootProviderContract;

        vaultRootStore = _vaultRootStore;
    }

    function _execute(bytes32, string calldata _sourceChain, string calldata _sourceAddress, bytes calldata _payload)
        internal
        override
    {
        require(Strings.equal(_sourceChain, rootProviderChain), InvalidSourceChain());
        require(Strings.equal(_sourceAddress, rootProviderContract), InvalidSourceAddress());

        (uint256 vaultRoot) = abi.decode(_payload, (uint256));

        vaultRootStore.setVaultRoot(vaultRoot);
    }
}
