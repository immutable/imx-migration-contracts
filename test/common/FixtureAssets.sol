// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "@src/assets/BridgedTokenMapping.sol";
import {ERC20MintableBurnable} from "@axelar-gmp-sdk-solidity/test/token/ERC20MintableBurnable.sol";

abstract contract FixtureAssets {
    address constant NATIVE_IMX = address(0xfff);
    BridgedTokenMapping.TokenMapping[] public fixAssets = [
        BridgedTokenMapping.TokenMapping(
            BridgedTokenMapping.ImmutableXToken(
                88914301944088089141574999348394996493546404963067902156417732601144566237, 100_000_000
            ),
            NATIVE_IMX
        ),
        BridgedTokenMapping.TokenMapping(
            BridgedTokenMapping.ImmutableXToken(
                1147032829293317481173155891309375254605214077236177772270270553197624560221, 1
            ),
            address(0x6de8aCC0D406837030CE4dd28e7c08C5a96a30d2) // USDC on zkEVM mainnet
        ),
        BridgedTokenMapping.TokenMapping(
            BridgedTokenMapping.ImmutableXToken(
                1103114524755001640548555873671808205895038091681120606634696969331999845790, 100_000_000
            ),
            address(0x52A6c53869Ce09a731CD772f245b97A4401d3348) // ETH on zkEVM mainnet
        )
    ];
}
