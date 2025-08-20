// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

abstract contract FixtureAccounts {
    struct AccountAssociation {
        uint256 starkKey;
        address ethAddress;
        bytes32[] proof;
    }

    mapping(uint256 starkKey => AccountAssociation account) public fixAccounts;
    bytes32 public accountsRoot = 0x46a7085f240b0e45266b5d02619baa3e877147d86ef20fa7e19acaeabfd53a74;

    constructor() {
        fixAccounts[79411809110095984468032809253690107888721902246953260848891387903178601] = AccountAssociation({
            starkKey: 79411809110095984468032809253690107888721902246953260848891387903178601,
            ethAddress: address(0xe0fB7622091e3D9ef9b438471B10B9Ea88c7cf6b),
            proof: createProofArray(
                [
                    0xbe494fa2bddad52fdb8180800a332ff9f28ad255a7088847dc77534ae58ec6f4,
                    0x6025aec7ddf34e8093f32b99fc96761dd5afccdb977e591f6f194530901a9d5f,
                    0x9802dc00bc4ef54de40187aa45594731bf625e444b02c0fd476157eb9b9a9776,
                    0xad629256f2fa844e378a3701531d02af9fd55350b2678cebb626e7ce5d9cba83,
                    0x3163caf6453b4640b24d8c0c142f1bc99e84cf031138572b0805e249cc59a387,
                    0xbe90ee981e1ccaa85544d44db79cc592a0ceb8387762a5624b1ad8dc8ca722c9,
                    0xe69f677b8c80f14f8b034d1701f0b34f0727f23152c159d68a4a4a6f4d183d58,
                    0x2a305d111ab376fddbaa8091cf9417adc2f5e87bbbb59efb597563d6bdc9717e,
                    0x2d563b1957b52a691a2838b6c77975044574d622c658779be3d0c01a304b248a,
                    0xe94ac05f4363f9c9058ebc25212319c5129e7285a09e01368d3be55c22600726,
                    0x69abeee43b6b639075107b71d975e1dfadff0ac99a230cebefb0b97c99ee7aae,
                    0x16eb934b98eb64e62723a90912e0e2fb10f4e39aac658b9ee3650e3bf41e7f44,
                    0xece03bf70f93ee041dabc8860526692d1f5447bacad4a0a65477d301ac8da62d,
                    0x31f3479d29db791f6c74a9fa4bcd866d5503ce3ca617e293e38f39fbbec7761a,
                    0x107af09f9217ec7f4cad9c08d41a012875bdf8d0c10faf68a84d4fa854cc49fb,
                    0x9c6a195a87fb79760f0afb75d8a9a4b1f01243212c2ad9562403f4e438c3c09e,
                    0xb591ad89ec59fa478f2a728c5cedb994d5ce91fd20b68df915888c0f1bcf7f29,
                    0x902556aca657c9a2cf3073c87381122616538f847392958418d478388978f450,
                    0x862711b53c27c653165e4d866f1722d214010b8d594eac63fcec4a6123604f63,
                    0x709377f00dada35249a068665478f635edb4968f3f859d39ba5fcf16163ba4d8,
                    0xd7930c38f7bec5bc507a01462b57f3d02f49e6d552ad348afd2cce3483c26679,
                    0xf9ed60685cd0db2f0db82f10a4c9b649bde6fde105d0d99be835ea76dbccc6a3,
                    0xb59b87148a5e4b7acafa01047f3f81598fbba0054ef25e46932f04dca0e70d87,
                    0x4752a9f3161b06f9b77c1727f7950fe84244548578acfd6154a83acd955b283,
                    0x33e9b0030b55753389eb72e6c807e173964efebdff7d528ef8526f2c76ba29b4,
                    0x6b3f66184b56e694adab675c3cfd436bb11182d13cb3c49817a5ae83f8ebe524,
                    0x838c5655cb21c6cb83313b5a631175dff4963772cce9108188b34ac87c81c41e
                ]
            )
        });

        fixAccounts[122390381828974573409072566700372845104411769093133497217042494342897787] = AccountAssociation({
            starkKey: 122390381828974573409072566700372845104411769093133497217042494342897787,
            ethAddress: address(0xA53b8a5b86C75F6b1bE663B759433D68548405c3),
            proof: createProofArray(
                [
                    0x6188d23a360f5792db39e8a98cb25986cc65d22d16044c2bbb3e94ac85706eae,
                    0x52e79e69211f8ebc6eca5c3f67449d26482dfef6b2bbcc924eee887921e1f806,
                    0xb5904048409bdc8b0889ade5ea07748491623b55ecf89a9a59fc4c7a49d9d322,
                    0x213807da6ae711059999a7cdeacd631645f5b51b1c860a36b37feb805a271405,
                    0xece9c10ac21ac399523e01540929101d42412076efaec46a67a91279ad8f1211,
                    0x2d9c6136529e127fb5695460163792aec5113773ac6973fb3eb0bf1aff402128,
                    0xe150c0128f14b291973033fd9c177de738a5fe988bb5d29b4d08faa936c7f3a8,
                    0xba070399ca3685057a4f01b4ce080e7ec1f42e11403c17afeab5ed3b1eb8c18f,
                    0x72e4d7b80a5d8e25c2f8619086fdcdb2d03d913bf497626240b54bc8f50e4267,
                    0x930277a552e6f3033b4a00c066253654df7f453f030e06c660ae1082bf423c1d,
                    0xe668d87178969014b697bcf93e25109f0fc4c77fe4bd242c3880834350eab1c8,
                    0x9b436fab9096188b4952d083e22ce7da04d0845128ed891dd408f1bcb0b3802d,
                    0xa0aa76b0a63a5cdf3ccfa16a20fa553802455193d7d34cb68351245fa40857b9,
                    0x7feec7cfdef9bed1cd0f7268caa702ced22789a2d36934b219f391101c14c968,
                    0x453a3b0345691bf9b293f16db601ecf0947bd5423b34f86f14ad3c4faa6c9987,
                    0xc1a8dcc09156f566f3e077c1d0520ad716922fb98c6526815740a6dab7c404fe,
                    0xfaefa89cd38c2312ece4dfe70a4cfeb2992587e4a3f38e368f1a2fa4fe453fec,
                    0xe34e066618f4044ee7cf510593e321478feac7a5968f5613a3dd816c89d50303,
                    0x23323b9e1f150e6f2d6179c0ffcaefd855ac7fe89fcceec8dee8c72c8243a656,
                    0x83fd2bf12ee0ca8a645d4351a4a4ad056e96c119cb9a44f57c6ce75aa4425427,
                    0xb2654c0fe6c1dbc4c4c8509bd147596d011b664216cf7a22e26f08d2ca9bcfb,
                    0x7b30d3e32ffef55599e1a8c17a49514fb0d63460c0f4b264095aee38b2646932,
                    0x6d7db050e5936cf2cb020e0303d5266f584834524367be2a5f4269b7ee0ecb9f,
                    0x59ca79ceb91ed1f6930ec1ad06d81073bd73bbbd55e8f66b83aee1dde893f74b,
                    0x33e9b0030b55753389eb72e6c807e173964efebdff7d528ef8526f2c76ba29b4,
                    0x6b3f66184b56e694adab675c3cfd436bb11182d13cb3c49817a5ae83f8ebe524,
                    0x838c5655cb21c6cb83313b5a631175dff4963772cce9108188b34ac87c81c41e
                ]
            )
        });

        fixAccounts[79411809110095984468032809253690107888721902246953260848891387903178601] = AccountAssociation({
            starkKey: 79411809110095984468032809253690107888721902246953260848891387903178601,
            ethAddress: address(0xe0fB7622091e3D9ef9b438471B10B9Ea88c7cf6b),
            proof: createProofArray(
                [
                    0xbe494fa2bddad52fdb8180800a332ff9f28ad255a7088847dc77534ae58ec6f4,
                    0x6025aec7ddf34e8093f32b99fc96761dd5afccdb977e591f6f194530901a9d5f,
                    0x9802dc00bc4ef54de40187aa45594731bf625e444b02c0fd476157eb9b9a9776,
                    0xad629256f2fa844e378a3701531d02af9fd55350b2678cebb626e7ce5d9cba83,
                    0x3163caf6453b4640b24d8c0c142f1bc99e84cf031138572b0805e249cc59a387,
                    0xbe90ee981e1ccaa85544d44db79cc592a0ceb8387762a5624b1ad8dc8ca722c9,
                    0xe69f677b8c80f14f8b034d1701f0b34f0727f23152c159d68a4a4a6f4d183d58,
                    0x2a305d111ab376fddbaa8091cf9417adc2f5e87bbbb59efb597563d6bdc9717e,
                    0x2d563b1957b52a691a2838b6c77975044574d622c658779be3d0c01a304b248a,
                    0xe94ac05f4363f9c9058ebc25212319c5129e7285a09e01368d3be55c22600726,
                    0x69abeee43b6b639075107b71d975e1dfadff0ac99a230cebefb0b97c99ee7aae,
                    0x16eb934b98eb64e62723a90912e0e2fb10f4e39aac658b9ee3650e3bf41e7f44,
                    0xece03bf70f93ee041dabc8860526692d1f5447bacad4a0a65477d301ac8da62d,
                    0x31f3479d29db791f6c74a9fa4bcd866d5503ce3ca617e293e38f39fbbec7761a,
                    0x107af09f9217ec7f4cad9c08d41a012875bdf8d0c10faf68a84d4fa854cc49fb,
                    0x9c6a195a87fb79760f0afb75d8a9a4b1f01243212c2ad9562403f4e438c3c09e,
                    0xb591ad89ec59fa478f2a728c5cedb994d5ce91fd20b68df915888c0f1bcf7f29,
                    0x902556aca657c9a2cf3073c87381122616538f847392958418d478388978f450,
                    0x862711b53c27c653165e4d866f1722d214010b8d594eac63fcec4a6123604f63,
                    0x709377f00dada35249a068665478f635edb4968f3f859d39ba5fcf16163ba4d8,
                    0xd7930c38f7bec5bc507a01462b57f3d02f49e6d552ad348afd2cce3483c26679,
                    0xf9ed60685cd0db2f0db82f10a4c9b649bde6fde105d0d99be835ea76dbccc6a3,
                    0xb59b87148a5e4b7acafa01047f3f81598fbba0054ef25e46932f04dca0e70d87,
                    0x4752a9f3161b06f9b77c1727f7950fe84244548578acfd6154a83acd955b283,
                    0x33e9b0030b55753389eb72e6c807e173964efebdff7d528ef8526f2c76ba29b4,
                    0x6b3f66184b56e694adab675c3cfd436bb11182d13cb3c49817a5ae83f8ebe524,
                    0x838c5655cb21c6cb83313b5a631175dff4963772cce9108188b34ac87c81c41e
                ]
            )
        });
    }

    function createProofArray(uint256[27] memory proof) public pure returns (bytes32[] memory) {
        bytes32[] memory dynamicProofs = new bytes32[](27);
        for (uint256 i = 0; i < 27; i++) {
            dynamicProofs[i] = bytes32(proof[i]);
        }
        return dynamicProofs;
    }

    function _getMerkleProof(uint256 starkKey) public view returns (bytes32[] memory) {
        AccountAssociation memory account = fixAccounts[starkKey];
        require(account.starkKey != 0, "Account not found");
        return account.proof;
    }
}
