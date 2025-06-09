// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "@src/assets/AssetMappingRegistry.sol";
import {ERC20MintableBurnable} from "@axelar-gmp-sdk-solidity/test/token/ERC20MintableBurnable.sol";

abstract contract FixtureAssets {
    address constant NATIVE_IMX = address(0xfff);
    AssetMappingRegistry.AssetDetails[] public fixAssets = [
        AssetMappingRegistry.AssetDetails(
            AssetMappingRegistry.ImmutableXAsset(
                1103114524755001640548555873671808205895038091681120606634696969331999845790, 7
            ),
            NATIVE_IMX
        ),
        AssetMappingRegistry.AssetDetails(
            AssetMappingRegistry.ImmutableXAsset(
                1810904411670354579114094206528523777019223281748314185673123994510590793656, 18
            ),
            address(0x6de8aCC0D406837030CE4dd28e7c08C5a96a30d2) // USDC on zkEVM mainnet
        )
    ];
}
