// SPDX-License-Identifier: Apache-2.0.
pragma solidity ^0.8.27;

interface IAccountProofVerifier {
    // @notice InvalidAccountProof is an error thrown when the provided account proof is invalid.
    // @param starkKey The Stark key of the user.
    // @param ethAddress The associated Ethereum address of the user.
    error InvalidAccountProof(uint256 starkKey, address ethAddress);

    function verify(uint256 starkKey, address ethAddress, bytes32[] calldata proof) external returns (bool);
}
