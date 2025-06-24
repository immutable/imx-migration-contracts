// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "@axelar-gmp-sdk-solidity/interfaces/IAxelarGasService.sol";
import {AxelarExecutable} from "@axelar-gmp-sdk-solidity/executable/AxelarExecutable.sol";
import {IAxelarGateway} from "@axelar-gmp-sdk-solidity/interfaces/IAxelarGateway.sol";

contract VaultRootSender is AxelarExecutable {
    address public immutable bridge;
    IAxelarGasService public immutable gasService;
    string public l2ChainId;
    string public l2VaultReceiver;

    event AxelarMessageSent(string indexed destinationChain, string indexed vaultReceiver, bytes indexed payload);

    constructor(
        address _l1StarkExBridge,
        string memory _l2VaultReceiver,
        string memory _l2ChainId,
        address _gasService,
        address _gateway
    ) AxelarExecutable(_gateway) {
        // TODO: custom error
        require(_l1StarkExBridge != address(0), "Bridge address cannot be zero");
        require(bytes(_l2VaultReceiver).length > 0, "L2 vault receiver cannot be empty");
        require(bytes(_l2ChainId).length > 0, "L2 chain name cannot be empty");
        require(_gasService != address(0), "Gas service address cannot be zero");

        bridge = _l1StarkExBridge;
        l2VaultReceiver = _l2VaultReceiver;
        l2ChainId = _l2ChainId;
        gasService = IAxelarGasService(_gasService);
    }

    function sendVaultRoot(uint256 vaultRoot, address gasRefundReceiver) external payable {
        require(msg.sender == bridge, "Caller is not the bridge");
        require(msg.value > 0, "No gas provided");
        require(gasRefundReceiver != address(0), "Refund recipient cannot be zero address");
        require(vaultRoot != 0, "Root cannot be zero");

        // Load from storage.
        string memory _l2VaultReceiver = l2VaultReceiver;
        string memory _l2ChainId = l2ChainId;
        bytes memory payload = abi.encode(vaultRoot);

        gasService.payNativeGasForContractCall{value: msg.value}(
            address(this), _l2ChainId, _l2VaultReceiver, payload, gasRefundReceiver
        );

        IAxelarGateway(gatewayAddress).callContract(_l2ChainId, _l2VaultReceiver, payload);
        emit AxelarMessageSent(_l2ChainId, _l2VaultReceiver, payload);
    }

    function _execute(bytes32, string calldata, string calldata, bytes calldata) internal pure override {
        revert("VaultRootProvider does not support direct execution");
    }
}
