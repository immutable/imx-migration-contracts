// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "@src/bridge/starkex/StarkExchangeMigration.sol";
import "forge-std/Test.sol";
import {IStarkExchangeMigration} from "../../../../src/bridge/starkex/IStarkExchangeMigration.sol";
import {MockVaultRootSenderAdapter} from "../../../common/MockVaultRootSenderAdapter.sol";

interface IStarkExchangeProxy is IStarkExchangeMigration {
    event ImplementationAdded(address indexed implementation, bytes initData, bool finalize);
    event Upgraded(address indexed implementation);

    function vaultRoot() external view returns (uint256 vaultRoot);

    function addImplementation(address newImplementation, bytes calldata initData, bool finalized) external;
    function upgradeTo(address newImplementation, bytes calldata initData, bool finalized) external payable;
    function implementation() external view returns (address implementation);
    function isNotFinalized() external view returns (bool);
}

contract StarkExchangeMigrationTest is Test {
    uint256 private constant BRIDGE_FEE = 0.001 ether;
    IStarkExchangeProxy public constant starkExProxy = IStarkExchangeProxy(0x5FDCCA53617f4d2b9134B29090C87D01058e27e9);
    address private constant ZKEVM_BRIDGE = 0xBa5E35E26Ae59c7aea6F029B68c6460De2d13eB6; // Bridge address
    address private constant STARKEX_PROXY_OWNER = 0xD2C37fC6fD89563187f3679304975655e448D192;
    address private constant L2VAULT_PROCESSOR = 0x5Ffb1b3C4D6E8B7A9c1E8d3f2b5e6f7a8B9C0d1E; // L2 Vault Processor address
    address private constant STARKEX_MIGRATION_MANAGER = STARKEX_PROXY_OWNER;

    address private mockVaultRootSender;

    address[] private tokens = [
        0xF57e7e7C23978C3cAEC3C3548E3D615c346e79fF, // IMX
        0xccC8cb5229B0ac8069C51fd58367Fd1e622aFD97, // GODS
        0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, // USDC
        0x9AB7bb7FdC60f4357ECFef43986818A2A3569c62 // GOG
    ];

    function setUp() public {
        string memory RPC_URL = vm.envString("ETH_RPC_URL");
        vm.createSelectFork(RPC_URL);
        mockVaultRootSender = address(new MockVaultRootSenderAdapter());
    }

    function _upgradeStarkExchange() internal returns (address) {
        vm.startPrank(STARKEX_PROXY_OWNER);
        address starkExchange = address(new StarkExchangeMigration());
        bytes memory initData =
            abi.encode(STARKEX_MIGRATION_MANAGER, ZKEVM_BRIDGE, mockVaultRootSender, L2VAULT_PROCESSOR);

        vm.expectEmit(true, true, true, true);
        emit IStarkExchangeProxy.ImplementationAdded(starkExchange, initData, false);
        starkExProxy.addImplementation(starkExchange, initData, false);

        skip(15 days);
        vm.expectEmit(true, true, true, true);
        emit IStarkExchangeProxy.Upgraded(starkExchange);
        starkExProxy.upgradeTo(starkExchange, initData, false);

        assertTrue(starkExProxy.isNotFinalized(), "Implementation should not be finalized through this upgrade");

        vm.stopPrank();
        return starkExchange;
    }

    function test_UpgradeStarkExchange() public {
        address newImpl = _upgradeStarkExchange();
        assertEq(starkExProxy.implementation(), newImpl, "Implementation should be updated");
    }

    function test_UpgradeStarkExchange_VaultRootPreserved() public {
        uint256 initialVaultRoot = uint256(vm.load(address(starkExProxy), bytes32(uint256(13))));
        assertNotEq(initialVaultRoot, 0, "Vault root should not be zero");

        _upgradeStarkExchange();
        uint256 vaultRoot = starkExProxy.vaultRoot();
        assertEq(vaultRoot, initialVaultRoot, "Vault root should remain the same after upgrade");
    }

    function test_migrate_ETHHoldings() public {
        uint256 initStarkExBal = address(starkExProxy).balance;
        console.log("Initial ETH balance on StarkEx bridge: %s", initStarkExBal);
        assertGt(initStarkExBal, 0, "Initial ETH balance should be greater than zero");

        uint256 initzkEVMBal = ZKEVM_BRIDGE.balance;
        console.log("Initial ETH balance on zkEVM bridge: %s", initzkEVMBal);
        assertGt(initzkEVMBal, 0, "Initial ETH balance should be greater than zero");

        _upgradeStarkExchange();

        vm.startPrank(STARKEX_MIGRATION_MANAGER);
        uint256 migrateAmount = initStarkExBal;

        uint256 bridgeFee = 0.001 ether; // Example bridge fee
        vm.deal(STARKEX_MIGRATION_MANAGER, bridgeFee);
        IStarkExchangeMigration.TokenMigrationDetails[] memory asset =
            new IStarkExchangeMigration.TokenMigrationDetails[](1);
        asset[0] = IStarkExchangeMigration.TokenMigrationDetails({
            token: address(0xeee),
            amount: migrateAmount,
            bridgeFee: BRIDGE_FEE
        });

        starkExProxy.migrateHoldings{value: bridgeFee}(asset);

        uint256 finStarkExBal = address(starkExProxy).balance;
        assertEq(finStarkExBal, 0, "Final ETH balance on StarkEx bridge should be zero after migration");

        uint256 finzkEVMBal = address(ZKEVM_BRIDGE).balance;
        assertEq(finzkEVMBal, initzkEVMBal + migrateAmount, "Final ETH balance on zkEVM bridge does not match expected");
        vm.stopPrank();
    }

    function test_migrate_ERC20Holdings() public {
        _upgradeStarkExchange();
        vm.startPrank(STARKEX_MIGRATION_MANAGER);

        uint256 bridgeFee = 0.001 ether;
        vm.deal(STARKEX_MIGRATION_MANAGER, bridgeFee * tokens.length);

        for (uint256 i = 0; i < tokens.length; i++) {
            IERC20Metadata token = IERC20Metadata(tokens[i]);

            uint256 initStarkExBal = token.balanceOf(address(starkExProxy));
            console.log("Initial balance of %s on StarkEx bridge: %s", tokens[i], initStarkExBal);
            assertGt(initStarkExBal, 0, "Initial balance should be greater than zero");

            uint256 initzkEVMBal = token.balanceOf(ZKEVM_BRIDGE);
            console.log("Initial balance of %s on zkEVM bridge: %s", tokens[i], initzkEVMBal);

            IStarkExchangeMigration.TokenMigrationDetails[] memory assets =
                new IStarkExchangeMigration.TokenMigrationDetails[](1);
            assets[0] = IStarkExchangeMigration.TokenMigrationDetails({
                token: address(token),
                amount: initStarkExBal,
                bridgeFee: bridgeFee
            });

            starkExProxy.migrateHoldings{value: bridgeFee}(assets);

            uint256 finStarkExBal = token.balanceOf(address(starkExProxy));
            assertEq(finStarkExBal, 0, "Final balance on StarkEx bridge should be zero after migration");

            uint256 finzkEVMBal = token.balanceOf(ZKEVM_BRIDGE);
            assertEq(
                finzkEVMBal, initzkEVMBal + initStarkExBal, "Final balance on zkEVM bridge does not match expected"
            );
        }
        vm.stopPrank();
    }

    function test_migrateVaultState() public {
        _upgradeStarkExchange();
        vm.startPrank(STARKEX_MIGRATION_MANAGER);

        uint256 vaultRoot = starkExProxy.vaultRoot();
        assertGt(vaultRoot, 0, "Vault root should be greater than zero");

        uint256 bridgeFee = 0.001 ether; // Example bridge fee
        vm.deal(STARKEX_MIGRATION_MANAGER, bridgeFee);

        vm.expectCall(
            mockVaultRootSender,
            abi.encodeCall(
                VaultRootSenderAdapter(mockVaultRootSender).sendVaultRoot, (vaultRoot, STARKEX_MIGRATION_MANAGER)
            )
        );
        starkExProxy.migrateVaultRoot{value: bridgeFee}();

        uint256 newVaultRoot = starkExProxy.vaultRoot();
        assertEq(newVaultRoot, vaultRoot, "Vault root should remain the same after migration");

        vm.stopPrank();
    }
}
