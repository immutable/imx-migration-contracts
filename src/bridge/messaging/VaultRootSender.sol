// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "@axelar-gmp-sdk-solidity/interfaces/IAxelarGasService.sol";
import {AxelarExecutable} from "@axelar-gmp-sdk-solidity/executable/AxelarExecutable.sol";
import {IAxelarGateway} from "@axelar-gmp-sdk-solidity/interfaces/IAxelarGateway.sol";

contract VaultRootSender is AxelarExecutable {
    address public immutable starkExBridge;
    IAxelarGasService public immutable axelarGasService;
    string public zkEVMChainId;
    string public zkEVMVaultReceiver;

    event VaultRootSent(string indexed destinationChain, string indexed vaultReceiver, bytes indexed payload);

    error InvalidChainId();
    error UnauthorizedCaller();
    error NoBridgeFee();
    error InvalidVaultRoot();

    constructor(
        address _starkExBridge,
        string memory _zkEVMVaultReceiver,
        string memory _zkEVMChainId,
        address _axelarGasService,
        address _axelarGateway
    ) AxelarExecutable(_axelarGateway) {
        require(_starkExBridge != address(0), InvalidAddress());
        require(_axelarGasService != address(0), InvalidAddress());
        require(bytes(_zkEVMVaultReceiver).length > 0, InvalidAddress());
        require(bytes(_zkEVMChainId).length > 0, InvalidChainId());

        starkExBridge = _starkExBridge;
        zkEVMVaultReceiver = _zkEVMVaultReceiver;
        zkEVMChainId = _zkEVMChainId;
        axelarGasService = IAxelarGasService(_axelarGasService);
    }

    function sendVaultRoot(uint256 vaultRoot, address gasRefundReceiver) external payable {
        require(msg.sender == starkExBridge, UnauthorizedCaller());
        require(msg.value > 0, NoBridgeFee());
        require(gasRefundReceiver != address(0), InvalidAddress());
        require(vaultRoot != 0, InvalidVaultRoot());

        // Load from storage.
        string memory _zkEVMVaultReceiver = zkEVMVaultReceiver;
        string memory _zkEVMChainId = zkEVMChainId;
        bytes memory payload = abi.encode(vaultRoot);

        axelarGasService.payNativeGasForContractCall{value: msg.value}(
            address(this), _zkEVMChainId, _zkEVMVaultReceiver, payload, gasRefundReceiver
        );

        IAxelarGateway(gatewayAddress).callContract(_zkEVMChainId, _zkEVMVaultReceiver, payload);
        emit VaultRootSent(_zkEVMChainId, _zkEVMVaultReceiver, payload);
    }

    function _execute(bytes32, string calldata, string calldata, bytes calldata) internal pure override {
        revert("Not Supported");
    }
}
