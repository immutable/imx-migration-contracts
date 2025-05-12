// SPDX-License-Identifier: Apache-2.0.
pragma solidity ^0.8.20;

interface IAccountVerifier {
    error InvalidAccountProof(string message);
    function verify(uint256 starkKey, address ethAddress, bytes32[] calldata proof) external returns (bool);
}