// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IAxelarGateway} from "@axelar-gmp-sdk-solidity/interfaces/IAxelarGateway.sol";

contract MockAxelarGateway is IAxelarGateway {
    bool private shouldValidate = true;

    constructor(bool _shouldValidate) {
        setShouldValidate(_shouldValidate);
    }

    function setShouldValidate(bool _shouldValidate) public {
        shouldValidate = _shouldValidate;
    }

    function validateContractCall(bytes32, string calldata, string calldata, bytes32)
        external
        view
        override
        returns (bool)
    {
        return shouldValidate;
    }

    function isContractCallApproved(bytes32, string calldata, string calldata, address, bytes32)
        external
        view
        override
        returns (bool)
    {
        return shouldValidate;
    }

    function isCommandExecuted(bytes32) external pure override returns (bool) {
        return false;
    }

    function callContract(string calldata, string calldata, bytes calldata) external pure override {}
}
