// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "../src/verifiers/accounts/AccountProofVerifier.sol";
import "../src/verifiers/vaults/VaultEscapeProofVerifier.sol";
import "forge-std/Script.sol";
import "forge-std/console.sol";
import {VaultWithdrawalProcessor} from "../src/withdrawals/VaultWithdrawalProcessor.sol";
import {TokenMappings} from "../src/assets/TokenMappings.sol";

contract DeployL2Contracts is Script {
    bool private allowRootOverride;
    address private vaultRootProvider;
    address private vaultFundProvider;
    address private accountVerifier;
    address private vaultVerifier;
    address[63] private lookupTables;
    VaultWithdrawalProcessor private withdrawalProcessor;
    VaultWithdrawalProcessor.Operators private operators;
    TokenMappings.AssetDetails[] private assetMappings;

    function setUp() external {
        string memory config = vm.readFile(vm.envString("DEPLOYMENT_CONFIG_FILE"));
        allowRootOverride = vm.parseJsonBool(config, "$.allow_root_override");

        vaultRootProvider = vm.parseJsonAddress(config, "$.vault_root_provider");
        require(vaultRootProvider != address(0), "Vault root provider cannot be zero");

        vaultFundProvider = vm.parseJsonAddress(config, "$.vault_fund_provider");
        require(vaultFundProvider != address(0), "Vault fund provider cannot be zero");

        // zero address implies new deployment is required
        accountVerifier = vm.parseJsonAddress(config, "$.account_verifier");
        // zero address implies new deployment is required
        vaultVerifier = vm.parseJsonAddress(config, "$.vault_verifier");

        operators = abi.decode(vm.parseJson(config, "$.operators"), (VaultWithdrawalProcessor.Operators));

        address[] memory _lookupTables = vm.parseJsonAddressArray(config, "$.lookup_tables");
        require(_lookupTables.length == 63, "Lookup tables should contain exactly 63 addresses");
        for (uint256 i = 0; i < _lookupTables.length; i++) {
            lookupTables[i] = _lookupTables[i];
        }

        assetMappings = abi.decode(vm.parseJson(config, "$.asset_mappings"), (TokenMappings.AssetDetails[]));
        require(assetMappings.length > 0, "At least one asset mapping must be provided");
    }

    // NOTE: Make sure to use either --slow or -batch-size 1 when running this script for Tenderly to avoid out of order deployments of contracts and incorrect addresses.
    function run() external {

        // Deploy account verifier if not provided
        if (accountVerifier == address(0)) {
            vm.broadcast();
            accountVerifier = address(new AccountProofVerifier(vaultRootProvider, allowRootOverride));
        }

        // Deploy vault verifier if not provided
        if (vaultVerifier == address(0)) {
            vm.broadcast();
            vaultVerifier = address(new VaultEscapeProofVerifier(lookupTables));
        }

        vm.broadcast();
        withdrawalProcessor = new VaultWithdrawalProcessor(
            IAccountProofVerifier(accountVerifier),
            IVaultProofVerifier(vaultVerifier),
            vaultRootProvider,
            vaultFundProvider,
            assetMappings,
            operators,
            allowRootOverride
        );
        _logDeploymentDetails();
    }

    function _logDeploymentDetails() private view {
        console.log("VaultWithdrawalProcessor: ", address(withdrawalProcessor));
        console.log("AccountProofVerifier: ", address(accountVerifier));
        console.log("VaultEscapeProofVerifier: ", address(vaultVerifier));
    }
}
