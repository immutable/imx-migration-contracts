// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

abstract contract FixtureAccounts {
    struct AccountAssociation {
        uint256 starkKey;
        address ethAddress;
        bytes32[] proof;
    }

    mapping(uint256 starkKey => AccountAssociation account) public fixAccounts;
    bytes32 public accountsRoot = 0x816b31af579ba78c6c494ab5db61296cf6dfbaeb0f3c6f83341065b87e88f522;

    constructor() {
        fixAccounts[1414930096151095810604649355863564842445074775977418556334494265558852329642] = AccountAssociation({
            starkKey: 1414930096151095810604649355863564842445074775977418556334494265558852329642,
            ethAddress: address(0x53Ff1260845C449E03f21E4DA481A010A61bC526),
            proof: createProofArray(
                [
                    0xed549a72dda62f737a649eb8fb2bdcf4b21f37625c9d72f563658d51519474d1,
                    0x4a7e2483699ff8951b72c1a1c88f1a7ef1d2069ac699181e9d1b7dffb7a0e2d2,
                    0xe634d298700efe31d7caadf510c1e4166b69e15367df749e483ed884b660654a,
                    0xef8f1fcaa1cffeff84a1294d1f94e96458d6bfc3d67087ede8ea3fd5062d7179,
                    0x436f28064cc08cb09a8f989f3e1e8afbf6900d070dbd213d2adf47570ef9aba8,
                    0xd7843737933a1446d280d04827d9f50ace95ef3c42281c816e7bd8f1ec05bb25,
                    0x51ce3b90db20ad4f98a84c1b9a02492a8ff4af7d191a3a1e447f55a0a6ec82c5,
                    0x9d2970fbd12e22991cae80f65ea3371b4b68d6bfe430efd84ebaaa58326b3315,
                    0xd9a652aab0985f327e22e3d51616d33b144b80deea98b515baf73a1828bce215,
                    0x5c355b0e18fa9975c0336d379453fa94ccc5848cf93d66e071aaca1aeaca1128,
                    0xa569e263b3ed947dbe99f776043e0b756242d74e8a7f7aa4b650778e35e16d32,
                    0xf00fdf60eb927f3a13c27b7de8959261db7274b56bbc2f05e83c1b5d8bd597f0,
                    0x87078f0fa0ceb94b429eec39d8e38dd0e3468e82f2c1a48571a70f1e0230948a,
                    0xbfeb3cc9554d5fd0b3264202b5634758d6873222bb5c7b391f1c2469a5db38c8,
                    0x5dfba56d8ae2c9a863d559199d80efe0f6e17278a81858c97bb97ae6c4bc6e23,
                    0x25f0d4ed0e0083c02cc37db74d56e86adf33e99b33883806ee83cc4366296c55,
                    0x5200b26938822dc8048818f7e3072bb835611ab2af85011c5d48f34b3da5fb36,
                    0x97faac43746ad6558038fa9632be9f1eb2fda79a26ac3d9b6f28bb257520de18,
                    0xd3dcaec4e2c537f40bbe4554b9b0edeac602fcc3af9f50489a14db55685593cf,
                    0x3376656625f5da2697156e4ffe7f7f65d47eb86674ad441f5ae2d631497661da,
                    0xd7930c38f7bec5bc507a01462b57f3d02f49e6d552ad348afd2cce3483c26679,
                    0xf9ed60685cd0db2f0db82f10a4c9b649bde6fde105d0d99be835ea76dbccc6a3,
                    0xb59b87148a5e4b7acafa01047f3f81598fbba0054ef25e46932f04dca0e70d87,
                    0x04752a9f3161b06f9b77c1727f7950fe84244548578acfd6154a83acd955b283,
                    0x46c52caef4d8fe3a691e6e0d13cde4419b925668ecbb2b4fb97b0bcfa5d9c2a8
                ]
            )
        });

        fixAccounts[3055930544108265584083972760202604393685974236397931590704927916735572300145] = AccountAssociation({
            starkKey: 3055930544108265584083972760202604393685974236397931590704927916735572300145,
            ethAddress: address(0x5D3034791096881E99A5BfA9F572E9412e16ecFD),
            proof: createProofArray(
                [
                    0xab8969cb5e0d7035fe93bc32f931c572e3e4a93cb8b9706b9e51754a71259fd1,
                    0xaa383891679ce37e310c844c02e6de11eb70bfaac325f6c554ec96173de3f553,
                    0x4cfdbc53104367d5b3f4af861b9d720d78c9100a4de8310fd4facac5a8a2327e,
                    0x2b38b36bef6cae95d49a01d8ccae93cf3c4716f60eedcc25b9b73ea9daeda698,
                    0x71fd854479a6eb86feb864c5254fc96b475cfc776072d0871edb2864d44b7af3,
                    0x6d33805afaea25086e29669588aa37caf98a229139584dfb90d1d1f9c58689ee,
                    0x4bcae348d68429b0ab768949a6e1bb8dd8e71089c044a4635daf423d39c8005c,
                    0x6f41ea630a9c1ea858768e018ec4a261ca457d092615796019ffd9ea59dd656b,
                    0xcc164a13cea8892b87738c002387568ef9adbf07266bd72829cfe90d0177aff4,
                    0x1a3684a745edac6324649948db959bf362922cc3e1a88caa88f35d9c4ac8c23b,
                    0xedacd0c7ccae57070496dc1a2acd0a9189c792b9a4b8b4f14acb6fc0b17dd07d,
                    0x4d8a2fa1d9a01beb2b624b277f9f48ad0e7ceddf9a2badf30a96055418727266,
                    0xe0949daa5aacb1c45ad65b92b1f59d5751f215b129ab64083bd647e4e97d97da,
                    0xb2effc8e04f1f0a72cf4e06e8ee95236faec1e36f0963259a9ce6a6fe104ae4e,
                    0xabb4a9e6efd69313caa89b96cdcf24e1a9d5f517d35abf202bb47356bcdaef86,
                    0x912124a08a0476d0c7f077788fb16cb5b3444fb5af997bc11b57b8fbed444efe,
                    0x5200b26938822dc8048818f7e3072bb835611ab2af85011c5d48f34b3da5fb36,
                    0x97faac43746ad6558038fa9632be9f1eb2fda79a26ac3d9b6f28bb257520de18,
                    0xd3dcaec4e2c537f40bbe4554b9b0edeac602fcc3af9f50489a14db55685593cf,
                    0x3376656625f5da2697156e4ffe7f7f65d47eb86674ad441f5ae2d631497661da,
                    0xd7930c38f7bec5bc507a01462b57f3d02f49e6d552ad348afd2cce3483c26679,
                    0xf9ed60685cd0db2f0db82f10a4c9b649bde6fde105d0d99be835ea76dbccc6a3,
                    0xb59b87148a5e4b7acafa01047f3f81598fbba0054ef25e46932f04dca0e70d87,
                    0x04752a9f3161b06f9b77c1727f7950fe84244548578acfd6154a83acd955b283,
                    0x46c52caef4d8fe3a691e6e0d13cde4419b925668ecbb2b4fb97b0bcfa5d9c2a8
                ]
            )
        });

        fixAccounts[113529659226429843176452665089448311127881873478525686571802957293159429587] = AccountAssociation({
            starkKey: 113529659226429843176452665089448311127881873478525686571802957293159429587,
            ethAddress: address(0xEe6367281bFDf8B889a630236FDAc1bEcaaC10e7),
            proof: createProofArray(
                [
                    0xd527e554673caa90b619cc8b801739af0747fc57aea4e67b0d4f60a7e84b4ab3,
                    0xe4c7352d87dda6c6a85ce3731caf496e26f9c11337c1bebe8dcace7d4cdecc37,
                    0x8ee17de18b3b9189299039c617f0356e7b897559aef437c37fc846cfde4c3f73,
                    0xc7b6a2ef377c5c98ba1db7059f094d8c8b71bfa9d18b198849c42188be16db9d,
                    0xd98765bd69d91161918d6f336b87a1e588e671ca3d202b27d87a9b9e93e56aed,
                    0xb4c35006c654d64e5becf07581f49fbdfa9880ad0059755935f3b0f422b574ee,
                    0xe6b077583cf2d95196554d160577dda6df25222a25275b2269d194f1eef5de37,
                    0x7a04ff3450b33fdde6758ec9d59baadd3e2bfd41eeb2fee6979c1139442b0ea1,
                    0x7c743018f27f00e48d1da2925e53b196771abb8df375b8324e635a78df470a9e,
                    0xbfc5340d4fbf01a199f08ccc82cb5edb6dd7a8aa2166e3bbb8c4da9eb6931d58,
                    0x8ee2724ee3d18a38f5f874988f6f90baafd242ecd2aea2670e5969fcc5cf4e2b,
                    0xdb2bd3a2758d1f78e5c283bb43bdd132b178a06f40a31caa923424ded2a0ad6a,
                    0x6e775d91f7700f116201846d6c5c19e98ef8a7a4dbfafa86513415be73e723c7,
                    0xbfeb3cc9554d5fd0b3264202b5634758d6873222bb5c7b391f1c2469a5db38c8,
                    0x5dfba56d8ae2c9a863d559199d80efe0f6e17278a81858c97bb97ae6c4bc6e23,
                    0x25f0d4ed0e0083c02cc37db74d56e86adf33e99b33883806ee83cc4366296c55,
                    0x5200b26938822dc8048818f7e3072bb835611ab2af85011c5d48f34b3da5fb36,
                    0x97faac43746ad6558038fa9632be9f1eb2fda79a26ac3d9b6f28bb257520de18,
                    0xd3dcaec4e2c537f40bbe4554b9b0edeac602fcc3af9f50489a14db55685593cf,
                    0x3376656625f5da2697156e4ffe7f7f65d47eb86674ad441f5ae2d631497661da,
                    0xd7930c38f7bec5bc507a01462b57f3d02f49e6d552ad348afd2cce3483c26679,
                    0xf9ed60685cd0db2f0db82f10a4c9b649bde6fde105d0d99be835ea76dbccc6a3,
                    0xb59b87148a5e4b7acafa01047f3f81598fbba0054ef25e46932f04dca0e70d87,
                    0x04752a9f3161b06f9b77c1727f7950fe84244548578acfd6154a83acd955b283,
                    0x46c52caef4d8fe3a691e6e0d13cde4419b925668ecbb2b4fb97b0bcfa5d9c2a8
                ]
            )
        });
    }

    function createProofArray(uint256[25] memory proof) public pure returns (bytes32[] memory) {
        bytes32[] memory dynamicProofs = new bytes32[](25);
        for (uint256 i = 0; i < 25; i++) {
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
