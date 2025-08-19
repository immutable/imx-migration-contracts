// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "@src/assets/TokenRegistry.sol";
import "@src/withdrawals/VaultWithdrawalProcessor.sol";
import {VaultEscapeProofVerifier} from "@src/verifiers/vaults/VaultEscapeProofVerifier.sol";
import {VaultRootReceiverAdapter} from "@src/bridge/messaging/VaultRootReceiverAdapter.sol";
import {AccountProofVerifier} from "@src/verifiers/accounts/AccountProofVerifier.sol";
import {FixtureLookupTables} from "../../../common/FixtureLookupTables.sol";
import {MockAxelarGateway} from "../../../common/MockAxelarGateway.sol";
import {ProofUtils} from "../../../common/ProofUtils.sol";
import {Test} from "forge-std/Test.sol";
import {FixtureAssets} from "../../../common/FixtureAssets.sol";
import {FixtureVaultEscapes} from "../../../common/FixtureVaultEscapes.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {FixtureAccounts} from "../../../common/FixtureAccounts.sol";
import {console} from "forge-std/console.sol";

/**
 * VaultWithdrawalProcessorIntegrationTest.sol
 * - Create a set of account associations and a merkle root.
 * - Create and deploy an account proof verifier contract.
 * - Create and deploy a vault verifier contract.
 * - Create an asset mapping registry contract.
 * - Create a vault root receiver contract.
 * - Create and deploy a vault withdrawal processor contract.
 * - Test:
 *   - Provision Funds -> Send message -> Set Root
 *   - Claim Withdrawal
 * - Gas Estimation
 */
contract VaultWithdrawalProcessorIntegrationTest is
    Test,
    ProofUtils,
    FixtureAssets,
    FixtureVaultEscapes,
    FixtureAccounts,
    FixtureLookupTables
{
    VaultEscapeProofVerifier private vaultVerifier;
    VaultRootReceiverAdapter private vaultRootReceiver;

    MockAxelarGateway private axelarGateway;
    VaultRootReceiverAdapter private rootReceiver;
    VaultWithdrawalProcessor private vaultProcessor;
    VaultWithdrawalProcessor.RoleOperators private operators;
    string private rootProviderContract = "0x1234567890123456789012345678901234567890";

    function setUp() public {
        string memory RPC_URL = vm.envString("ZKEVM_RPC_URL");
        vm.createSelectFork(RPC_URL);

        axelarGateway = new MockAxelarGateway(true);
        // Create account associations and compute the merkle root

        vaultVerifier = new VaultEscapeProofVerifier(ZKEVM_MAINNET_LOOKUP_TABLES);

        rootReceiver = new VaultRootReceiverAdapter(address(this), address(axelarGateway));

        operators = ProcessorAccessControl.RoleOperators({
            pauser: address(this),
            unpauser: address(this),
            disburser: address(this),
            defaultAdmin: address(this),
            accountRootProvider: address(this),
            vaultRootProvider: address(rootReceiver),
            tokenMappingManager: address(this)
        });

        vaultProcessor = new VaultWithdrawalProcessor(address(vaultVerifier), operators, true);

        vaultProcessor.setAccountRoot(accountsRoot);
        vaultProcessor.registerTokenMappings(fixAssets);

        rootReceiver.setVaultRootSource("ethereum", rootProviderContract);

        // Configure the vault root store in the root receiver
        rootReceiver.setVaultRootReceiver(VaultRootReceiver(address(vaultProcessor)));
    }

    function test_ProcessVaultWithdrawal_IMX() public {
        // Set the vault root. In practice this would be done through a cross-chain message from an L1 contract using Axelar
        vm.expectEmit(true, true, true, true);
        emit VaultRootReceiver.VaultRootSet(0, fixVaultEscapes[0].root);
        vm.expectEmit(true, true, true, true);
        emit VaultRootReceiverAdapter.VaultRootReceived(fixVaultEscapes[0].root);
        rootReceiver.execute(
            keccak256("set-vault-root"),
            "ethereum",
            rootProviderContract,
            abi.encode(rootReceiver.SET_VAULT_ROOT(), fixVaultEscapes[0].root)
        );

        address vaultProcessorAddr = address(vaultProcessor);

        // Fund the vault processor. In practice this would be done by the bridging of funds through the native bridge
        // Fund some IMX
        deal(vaultProcessorAddr, 1 ether);

        assertEq(vaultProcessorAddr.balance, 1 ether);
        AccountAssociation memory account = fixAccounts[fixVaultEscapes[2].vault.starkKey];

        assertEq(account.ethAddress.balance, 0);

        uint256[] memory vaultProof = fixVaultEscapes[2].proof;
        uint256 vaultBalance = 546024000000000;

        vm.startSnapshotGas("ProcessVaultWithdrawal_NativeAsset");
        bytes32[] memory accProof = _getMerkleProof(account.starkKey);
        vaultProcessor.verifyAndProcessWithdrawal(account.ethAddress, accProof, vaultProof);
        vm.stopSnapshotGas();

        assertEq(
            account.ethAddress.balance, vaultBalance, "Post-withdrawal user's IMX balance did not match expected value"
        );
        assertEq(
            vaultProcessorAddr.balance,
            1 ether - vaultBalance,
            "Post-withdrawal vault processor's IMX balance did not match expected"
        );
    }

    function test_ProcessVaultWithdrawal_USDC() public {
        // Set the vault root. In practice this would be done through a cross-chain message from an L1 contract using Axelar
        vm.expectEmit(true, true, true, true);
        emit VaultRootReceiver.VaultRootSet(0, fixVaultEscapes[1].root);
        vm.expectEmit(true, true, true, true);
        emit VaultRootReceiverAdapter.VaultRootReceived(fixVaultEscapes[1].root);
        rootReceiver.execute(
            keccak256("set-vault-root"),
            "ethereum",
            rootProviderContract,
            abi.encode(rootReceiver.SET_VAULT_ROOT(), fixVaultEscapes[1].root)
        );

        address vaultProcessorAddr = address(vaultProcessor);

        // Fund some USDC
        IERC20 usdc = IERC20(fixAssets[1].tokenOnZKEVM);
        deal(address(usdc), vaultProcessorAddr, 1 ether);

        assertEq(usdc.balanceOf(vaultProcessorAddr), 1 ether);
        AccountAssociation memory account = fixAccounts[fixVaultEscapes[1].vault.starkKey];

        assertEq(usdc.balanceOf(account.ethAddress), 0);

        bytes32[] memory accProof = _getMerkleProof(account.starkKey);
        uint256[] memory vaultProof = fixVaultEscapes[1].proof;
        uint256 vaultBalance = 76;

        vm.startSnapshotGas("ProcessVaultWithdrawal_ERC20");
        vaultProcessor.verifyAndProcessWithdrawal(account.ethAddress, accProof, vaultProof);
        vm.stopSnapshotGas();

        assertEq(
            usdc.balanceOf(account.ethAddress), vaultBalance, "Post-withdrawal user USDC balance did not match expected"
        );
        assertEq(
            usdc.balanceOf(vaultProcessorAddr),
            1 ether - vaultBalance,
            "Post-withdrawal usdc balance of vault Processor did not match expected"
        );
    }
}
