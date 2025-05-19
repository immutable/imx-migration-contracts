// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "@src/assets/AssetsRegistry.sol";

abstract contract FixtureAssets {
    AssetsRegistry.AssetDetails[] public fixAssets = [
        AssetsRegistry.AssetDetails(
            1103114524755001640548555873671808205895038091681120606634696969331999845790,
            7,
            address(0xfff) // IMX
        ),
        AssetsRegistry.AssetDetails(
            1810904411670354579114094206528523777019223281748314185673123994510590793656,
            1,
            address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48) // USDC
        )
    ];
}
