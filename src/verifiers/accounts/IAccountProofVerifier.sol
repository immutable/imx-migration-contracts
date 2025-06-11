// SPDX-License-Identifier: Apache-2.0.
pragma solidity ^0.8.18;

interface IAccountProofVerifier {
    error InvalidAccountProof(string message);

    function verifyAccountProof(uint256 starkKey, address ethAddress, bytes32[] calldata proof)
        external
        returns (bool);
}
