// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "@src/bridge/starkex/StarkExchangeMigration.sol";
import "forge-std/Test.sol";
import {IStarkExchangeMigration} from "../../../../src/bridge/starkex/IStarkExchangeMigration.sol";

interface IStarkExchangeProxy is IStarkExchangeMigration {
    event ImplementationAdded(address indexed implementation, bytes initData, bool finalize);

    function vaultRoot() external view returns (uint256 vaultRoot);

    function addImplementation(address newImplementation, bytes calldata initData, bool finalized) external;
    function upgradeTo(address newImplementation, bytes calldata initData, bool finalized) external payable;
    function implementation() external view returns (address implementation);
}

contract StarkExchangeTest is Test {
    IStarkExchangeProxy public constant starkExProxy = IStarkExchangeProxy(0x5FDCCA53617f4d2b9134B29090C87D01058e27e9);
    address public constant zkEVMBridge = 0xBa5E35E26Ae59c7aea6F029B68c6460De2d13eB6; // Bridge address
    address public constant proxyOwner = 0xD2C37fC6fD89563187f3679304975655e448D192;
    address public constant l2VaultProcessor = 0x5Ffb1b3C4D6E8B7A9c1E8d3f2b5e6f7a8B9C0d1E; // L2 Vault Processor address
    address public constant migrationManager = proxyOwner;

    // TODO: Include the below tokens once they are mapped to the zkEVM bridge
    //        0x7E77dCb127F99ECe88230a64Db8d595F31F1b068, // SILV2
    //        0x767FE9EDC9E0dF98E07454847909b5E959D7ca0E, // ILV
    //        0x90685e300A4c4532EFCeFE91202DfE1Dfd572F47, // CTA
    //        0xeD35af169aF46a02eE13b9d79Eb57d6D68C1749e // OMI
    address[] private tokens = [
        0xF57e7e7C23978C3cAEC3C3548E3D615c346e79fF, // IMX
        0xccC8cb5229B0ac8069C51fd58367Fd1e622aFD97, // GODS
        0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, // USDC
        0x9AB7bb7FdC60f4357ECFef43986818A2A3569c62 // GOG
    ];

    function setUp() public {
        string memory RPC_URL = vm.envString("ETH_RPC_URL");
        vm.createSelectFork(RPC_URL);
    }

    function _upgradeStarkExchange() internal returns (address) {
        vm.startPrank(proxyOwner);
        address starkExchange = address(new StarkExchangeMigration());
        bytes memory initData = abi.encode(migrationManager, zkEVMBridge, l2VaultProcessor);

        vm.expectEmit(true, true, true, true);
        emit IStarkExchangeProxy.ImplementationAdded(starkExchange, initData, false);
        starkExProxy.addImplementation(starkExchange, initData, false);

        skip(15 days);
        starkExProxy.upgradeTo(starkExchange, initData, false);

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

    function test_migrateAllETHHoldings() public {
        uint256 initStarkExBal = address(starkExProxy).balance;
        console.log("Initial ETH balance on StarkEx bridge: %s", initStarkExBal);
        assertGt(initStarkExBal, 0, "Initial ETH balance should be greater than zero");

        uint256 initzkEVMBal = zkEVMBridge.balance;
        console.log("Initial ETH balance on zkEVM bridge: %s", initzkEVMBal);
        assertGt(initzkEVMBal, 0, "Initial ETH balance should be greater than zero");

        _upgradeStarkExchange();

        vm.startPrank(migrationManager);
        uint256 migrateAmount = initStarkExBal;

        uint256 bridgeFee = 0.001 ether; // Example bridge fee
        vm.deal(migrationManager, bridgeFee);
        starkExProxy.migrateETHHoldings{value: bridgeFee}(migrateAmount);

        uint256 finStarkExBal = address(starkExProxy).balance;
        assertEq(finStarkExBal, 0, "Final ETH balance on StarkEx bridge should be zero after migration");

        uint256 finzkEVMBal = address(zkEVMBridge).balance;
        assertEq(finzkEVMBal, initzkEVMBal + migrateAmount, "Final ETH balance on zkEVM bridge does not match expected");
        vm.stopPrank();
    }

    function test_migrateAllERC20Holdings() public {
        _upgradeStarkExchange();
        vm.startPrank(migrationManager);

        uint256 bridgeFee = 0.001 ether;
        vm.deal(migrationManager, bridgeFee * tokens.length);

        for (uint256 i = 0; i < tokens.length; i++) {
            IERC20Metadata token = IERC20Metadata(tokens[i]);

            uint256 initStarkExBal = token.balanceOf(address(starkExProxy));
            console.log("Initial balance of %s on StarkEx bridge: %s", tokens[i], initStarkExBal);
            assertGt(initStarkExBal, 0, "Initial balance should be greater than zero");

            uint256 initzkEVMBal = token.balanceOf(zkEVMBridge);
            console.log("Initial balance of %s on zkEVM bridge: %s", tokens[i], initzkEVMBal);

            starkExProxy.migrateERC20Holdings{value: bridgeFee}(token, initStarkExBal);

            uint256 finStarkExBal = token.balanceOf(address(starkExProxy));
            assertEq(finStarkExBal, 0, "Final balance on StarkEx bridge should be zero after migration");

            uint256 finzkEVMBal = token.balanceOf(zkEVMBridge);
            assertEq(
                finzkEVMBal, initzkEVMBal + initStarkExBal, "Final balance on zkEVM bridge does not match expected"
            );
        }

        vm.stopPrank();
    }
}
