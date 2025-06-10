// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "../../../../src/assets/AssetMappingRegistry.sol";
import "../../../../src/withdrawals/VaultWithdrawalProcessor.sol";
import {AccountProofVerifier} from "../../../../src/verifiers/accounts/AccountProofVerifier.sol";
import {FixtureLookupTables} from "../../../common/FixtureLookupTables.sol";
import {MockAxelarGateway} from "../../../common/MockAxelarGateway.sol";
import {ProofUtils} from "../../../common/ProofUtils.sol";
import {Test} from "forge-std/Test.sol";
import {VaultEscapeProofVerifier} from "../../../../src/verifiers/vaults/VaultEscapeProofVerifier.sol";
import {VaultRootReceiver} from "../../../../src/bridge/messaging/VaultRootReceiver.sol";
import {FixtureAssets} from "../../../common/FixtureAssets.sol";
import {FixVaultEscapes} from "../../../common/FixVaultEscapes.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
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
    FixVaultEscapes,
    FixtureLookupTables
{
    AccountProofVerifier private accountVerifier;
    VaultEscapeProofVerifier private vaultVerifier;
    VaultRootReceiver private vaultRootReceiver;
    bytes32[] private accounts;
    // Create test data
    uint256 private user1SK = fixVaultEscapes[2].vault.starkKey;
    address private user1Address = address(0x123);

    uint256 private user2SK = fixVaultEscapes[1].vault.starkKey;
    address private user2Address = address(0xabc);

    bytes32 private accountsRoot;
    MockAxelarGateway private axelarGateway;
    VaultRootReceiver private rootReceiver;
    VaultWithdrawalProcessor private vaultProcessor;
    VaultWithdrawalProcessor.Operators private operators;
    string private rootProviderContract = "0x1234567890123456789012345678901234567890";

    function setUp() public {
        string memory RPC_URL = vm.envString("ZKEVM_RPC_URL");
        vm.createSelectFork(RPC_URL);

        axelarGateway = new MockAxelarGateway(true);
        // Create account associations and compute the merkle root
        accounts = new bytes32[](4);
        accounts[0] = keccak256(abi.encode(user1SK, user1Address));
        accounts[1] = keccak256(abi.encode(user2SK, user2Address));
        accounts[2] = keccak256(abi.encode(0xabcdef, address(0xabcd)));
        accounts[3] = keccak256(abi.encode(0xbbbbbb, address(0xbbcde)));

        accountsRoot = _computeMerkleRoot(accounts);
        accountVerifier = new AccountProofVerifier(accountsRoot);

        rootReceiver = new VaultRootReceiver("ethereum", rootProviderContract, address(this), address(axelarGateway));

        vaultVerifier = new VaultEscapeProofVerifier(ZKEVM_MAINNET_LOOKUP_TABLES);

        operators = VaultWithdrawalProcessor.Operators({
            pauser: address(this),
            unpauser: address(this),
            disburser: address(this),
            defaultAdmin: address(this)
        });

        vaultProcessor = new VaultWithdrawalProcessor(
            accountVerifier, vaultVerifier, address(rootReceiver), address(this), fixAssets, operators
        );

        // Configure the vault root store in the root receiver
        rootReceiver.setVaultRootStore(VaultRootStore(address(vaultProcessor)));
    }

    function test_ProcessVaultWithdrawal_IMX() public {
        // Set the vault root. In practice this would be done through a cross-chain message from an L1 contract using Axelar
        vm.expectEmit(true, true, true, true);
        emit VaultRootStore.VaultRootSet(0, fixVaultEscapes[0].root);
        vm.expectEmit(true, true, true, true);
        emit VaultRootReceiver.VaultRootReceived(fixVaultEscapes[0].root);
        rootReceiver.execute(
            keccak256("set-vault-root"), "ethereum", rootProviderContract, abi.encode(fixVaultEscapes[0].root)
        );

        address vaultProcessorAddr = address(vaultProcessor);

        // Fund the vault processor. In practice this would be done by the bridging of funds through the native bridge
        // Fund some IMX
        deal(vaultProcessorAddr, 1 ether);

        assertEq(vaultProcessorAddr.balance, 1 ether);
        assertEq(user1Address.balance, 0);

        bytes32[] memory accProof = _getMerkleProof(accounts, 0);

        uint256[] memory vaultProof = fixVaultEscapes[2].proof;
        uint256 vaultBalance = 546024000000000;

        console.log("User 1 stark key: %s", user1SK);
        console.log("Proof extracted stark key: %s", vaultVerifier.extractLeafFromProof(vaultProof).starkKey);

        vm.startSnapshotGas("ProcessVaultWithdrawal_NativeAsset");
        vaultProcessor.verifyAndProcessWithdrawal(user1Address, accProof, vaultProof);
        vm.stopSnapshotGas();

        assertEq(user1Address.balance, vaultBalance, "Post-withdrawal user's IMX balance did not match expected value");
        assertEq(
            vaultProcessorAddr.balance,
            1 ether - vaultBalance,
            "Post-withdrawal vault processor's IMX balance did not match expected"
        );
    }

    function test_ProcessVaultWithdrawal_USDC() public {
        // Set the vault root. In practice this would be done through a cross-chain message from an L1 contract using Axelar
        vm.expectEmit(true, true, true, true);
        emit VaultRootStore.VaultRootSet(0, fixVaultEscapes[1].root);
        vm.expectEmit(true, true, true, true);
        emit VaultRootReceiver.VaultRootReceived(fixVaultEscapes[1].root);
        rootReceiver.execute(
            keccak256("set-vault-root"), "ethereum", rootProviderContract, abi.encode(fixVaultEscapes[1].root)
        );

        address vaultProcessorAddr = address(vaultProcessor);

        // Fund some USDC
        IERC20 usdc = IERC20(fixAssets[1].assetOnZKEVM);
        deal(address(usdc), vaultProcessorAddr, 1 ether);

        assertEq(usdc.balanceOf(vaultProcessorAddr), 1 ether);
        assertEq(usdc.balanceOf(user1Address), 0);

        bytes32[] memory accProof = _getMerkleProof(accounts, 1);
        uint256[] memory vaultProof = fixVaultEscapes[1].proof;
        uint256 vaultBalance = 76;

        vm.startSnapshotGas("ProcessVaultWithdrawal_ERC20");
        vaultProcessor.verifyAndProcessWithdrawal(user2Address, accProof, vaultProof);
        vm.stopSnapshotGas();

        assertEq(usdc.balanceOf(user2Address), vaultBalance, "Post-withdrawal user USDC balance did not match expected");
        assertEq(
            usdc.balanceOf(vaultProcessorAddr),
            1 ether - vaultBalance,
            "Post-withdrawal usdc balance of vault Processor did not match expected"
        );
    }
}
