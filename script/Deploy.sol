// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/verifiers/vaults/VaultEscapeProofVerifier.sol";
import "../src/verifiers/accounts/AccountProofVerifier.sol";
import "../src/withdrawals/VaultWithdrawalProcessor.sol";
import "../src/assets/AssetMappingRegistry.sol";
import "./DeploymentLookupTables.sol";

/**
 * @title Deploy
 * @notice Foundry deployment script for vault withdrawal processor
 * @dev This script will deploy:
 *      1. VaultEscapeProofVerifier with ZKEVM mainnet lookup tables
 *      2. AccountProofVerifier
 *      3. VaultWithdrawalProcessor with the deployed verifiers
 *
 * Usage:
 *   forge script script/Deploy.sol:Deploy --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast
 *
 * Environment Variables:
 *   - OWNER_ADDRESS: The address that will own the contracts (defaults to deployer)
 *   - VAULT_ROOT_PROVIDER: Address of the vault root provider (defaults to owner)
 *   - VAULT_FUND_PROVIDER: Address of the vault fund provider (defaults to owner)
 */
contract Deploy is Script, DeploymentLookupTables {
    VaultEscapeProofVerifier public vaultVerifier;
    AccountProofVerifier public accountVerifier;
    VaultWithdrawalProcessor public vaultProcessor;

    address public owner;
    address public vaultRootProvider;
    address public vaultFundProvider;

    function setUp() public {
        // Get owner address from environment or use deployer
        owner = vm.envOr("OWNER_ADDRESS", msg.sender);

        // Get vault providers from environment or use owner
        vaultRootProvider = vm.envOr("VAULT_ROOT_PROVIDER", owner);
        vaultFundProvider = vm.envOr("VAULT_FUND_PROVIDER", owner);

        require(owner != address(0), "Owner address cannot be zero");
        require(vaultRootProvider != address(0), "Vault root provider cannot be zero");
        require(vaultFundProvider != address(0), "Vault fund provider cannot be zero");
    }

    function run() public {
        vm.startBroadcast();

        console.log("Vault Withdrawal Processor Deployment");
        console.log("Deployer:", msg.sender);
        console.log("Owner:", owner);
        console.log("Vault Root Provider:", vaultRootProvider);
        console.log("Vault Fund Provider:", vaultFundProvider);

        // 1. Deploy VaultEscapeProofVerifier with ZKEVM mainnet lookup tables
        console.log("Deploying VaultEscapeProofVerifier...");
        vaultVerifier = new VaultEscapeProofVerifier(ZKEVM_MAINNET_LOOKUP_TABLES);
        console.log("VaultEscapeProofVerifier deployed at:", address(vaultVerifier));

        // 2. Deploy AccountProofVerifier
        console.log("Deploying AccountProofVerifier...");
        accountVerifier = new AccountProofVerifier(owner);
        console.log("AccountProofVerifier deployed at:", address(accountVerifier));

        // 3. Create asset mappings for the vault processor
        // Using some common assets for demonstration - in production this would be customized
        AssetMappingRegistry.AssetDetails[] memory assets = createDefaultAssetMappings();
        console.log("Created", assets.length, "default asset mappings");

        // 4. Create operators struct - all roles granted to owner
        // TODO: Enable different addresses for each role for production deployment
        VaultWithdrawalProcessor.Operators memory operators =
            VaultWithdrawalProcessor.Operators({pauser: owner, unpauser: owner, disburser: owner, defaultAdmin: owner});

        // 5. Deploy VaultWithdrawalProcessor
        console.log("Deploying VaultWithdrawalProcessor...");
        vaultProcessor = new VaultWithdrawalProcessor(
            accountVerifier, vaultVerifier, vaultRootProvider, vaultFundProvider, assets, operators
        );
        console.log("VaultWithdrawalProcessor deployed at:", address(vaultProcessor));

        vm.stopBroadcast();

        // Log final deployment summary
        console.log("");
        console.log("=== Deployment Complete ===");
        console.log("VaultEscapeProofVerifier:", address(vaultVerifier));
        console.log("AccountProofVerifier:", address(accountVerifier));
        console.log("VaultWithdrawalProcessor:", address(vaultProcessor));
        console.log("Next steps:");
        console.log("1. Fund the VaultWithdrawalProcessor with assets for withdrawals");
        console.log("2. Set up the vault root provider to call setVaultRoot() on the processor");
        console.log("3. Set the account root by calling setAccountRoot() on the AccountProofVerifier");
    }

    /**
     * @notice Creates default asset mappings for common tokens
     * @dev In production, customize these mappings for your specific use case
     * @return assets Array of asset details for the processor
     * TODO: Create a more comprehensive asset mapping registry, and a way to update it post-deployment.
     */
    function createDefaultAssetMappings() internal pure returns (AssetMappingRegistry.AssetDetails[] memory assets) {
        assets = new AssetMappingRegistry.AssetDetails[](3);

        // Native IMX mapping
        assets[0] = AssetMappingRegistry.AssetDetails(
            AssetMappingRegistry.ImmutableXAsset(
                88914301944088089141574999348394996493546404963067902156417732601144566237, // IMX asset ID on Immutable X
                100_000_000 // quantum (8 decimals)
            ),
            address(0xfff) // Native IMX address on zkEVM
        );

        // USDC mapping
        assets[1] = AssetMappingRegistry.AssetDetails(
            AssetMappingRegistry.ImmutableXAsset(
                1147032829293317481173155891309375254605214077236177772270270553197624560221, // USDC asset ID on Immutable X
                1 // quantum (6 decimals, so 1 quantum = 1 micro USDC)
            ),
            address(0x6de8aCC0D406837030CE4dd28e7c08C5a96a30d2) // USDC on zkEVM mainnet
        );

        // ETH mapping
        assets[2] = AssetMappingRegistry.AssetDetails(
            AssetMappingRegistry.ImmutableXAsset(
                1103114524755001640548555873671808205895038091681120606634696969331999845790, // ETH asset ID on Immutable X
                100_000_000 // quantum (8 decimals)
            ),
            address(0x52A6c53869Ce09a731CD772f245b97A4401d3348) // ETH on zkEVM mainnet
        );

        return assets;
    }
}
