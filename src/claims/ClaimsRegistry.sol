// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

abstract contract ClaimsRegistry {
    mapping(bytes32 => bool) public claimsMapping;

    function _registerClaim(bytes32 claimHash) internal {
        require(claimHash != bytes32(0), "Invalid claim hash");
        require(!claimsMapping[claimHash], "Claim already exists");

        claimsMapping[claimHash] = true;
    }

    function _registerClaim(uint256 starkKey, uint256 assetId) internal {
        bytes32 claimHash = keccak256(abi.encode(starkKey, assetId));
        _registerClaim(claimHash);
    }

    function isClaimed(bytes32 claimHash) public view returns (bool) {
        return claimsMapping[claimHash];
    }

    function isClaimed(uint256 starkKey, uint256 assetId) public view returns (bool) {
        bytes32 claimHash = keccak256(abi.encode(starkKey, assetId));
        return claimsMapping[claimHash];
    }
}
