// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import "@src/bridge/starkex/StarkExchangeMigrationV2.sol";
import {IStarkExchangeMigration} from "@src/bridge/starkex/IStarkExchangeMigration.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IStarkExchangeProxy {
    function addImplementation(address newImplementation, bytes calldata initData, bool finalized) external;
    function upgradeTo(address newImplementation, bytes calldata initData, bool finalized) external payable;
    function implementation() external view returns (address);
    function isNotFinalized() external view returns (bool);
    function vaultRoot() external view returns (uint256);

    // LegacyStarkExchangeBridge functions
    function withdraw(uint256 ownerKey, uint256 assetType) external;
    function getWithdrawalBalance(uint256 ownerKey, uint256 assetId) external view returns (uint256);
    function getEthKey(uint256 ownerKey) external view returns (address);
    function getQuantum(uint256 assetType) external view returns (uint256);
    function registerEthAddress(address ethKey, uint256 starkKey, bytes calldata starkSignature) external;

    // StarkExchangeMigrationV2 constants
    function VCO_ASSET_TYPE() external view returns (uint256);
    function HOLDER_1_KEY() external view returns (uint256);
    function HOLDER_1_ETH() external view returns (address);
    function HOLDER_1_AMOUNT() external view returns (uint256);
    function HOLDER_6_KEY() external view returns (uint256);
    function HOLDER_6_ETH() external view returns (address);
    function HOLDER_6_AMOUNT() external view returns (uint256);
    function HOLDER_7_KEY() external view returns (uint256);
    function HOLDER_7_ETH() external view returns (address);
    function HOLDER_7_AMOUNT() external view returns (uint256);

    // StarkExchangeMigration functions
    function migrationManager() external view returns (address);
    function zkEVMBridge() external view returns (address);
}

contract StarkExchangeMigrationV2IntegrationTest is Test {
    IStarkExchangeProxy public constant starkExProxy = IStarkExchangeProxy(0x5FDCCA53617f4d2b9134B29090C87D01058e27e9);
    address private constant STARKEX_PROXY_OWNER = 0xD2C37fC6fD89563187f3679304975655e448D192;
    address private constant VCO_TOKEN = 0x2Caa4021e580b07D92adf8A40Ec53b33a215D620;

    /// @dev Deployed StarkExchangeMigrationV2 implementation on mainnet
    address private constant DEPLOYED_IMPL = 0x273b65a7231321D4ee47a4c47408Ef43517455Ec;

    /// @dev Mainnet block at which the StarkEx bridge holds VCO tokens pre-migration
    ///      and the StarkExchangeMigrationV2 implementation is deployed
    uint256 private constant FORK_BLOCK = 24920000;

    function setUp() public {
        string memory RPC_URL = vm.envString("ETH_RPC_URL");
        vm.createSelectFork(RPC_URL, FORK_BLOCK);
    }

    function _upgradeTo() internal returns (address) {
        vm.startPrank(STARKEX_PROXY_OWNER);

        bytes memory initData = bytes("");

        starkExProxy.addImplementation(DEPLOYED_IMPL, initData, false);
        skip(15 days);
        starkExProxy.upgradeTo(DEPLOYED_IMPL, initData, false);

        vm.stopPrank();
        return DEPLOYED_IMPL;
    }

    function test_DeployedBytecodeMatchesCompiled() public {
        address freshImpl = address(new StarkExchangeMigrationV2());
        assertEq(
            DEPLOYED_IMPL.code,
            freshImpl.code,
            "Deployed implementation bytecode should match locally compiled bytecode"
        );
    }

    function test_Upgrade_ImplementationUpdated() public {
        address newImpl = _upgradeTo();
        assertEq(starkExProxy.implementation(), newImpl, "Implementation should be updated");
    }

    function test_Upgrade_VaultRootPreserved() public {
        uint256 vaultRootBefore = starkExProxy.vaultRoot();
        assertNotEq(vaultRootBefore, 0, "Vault root should not be zero before upgrade");

        _upgradeTo();

        assertEq(starkExProxy.vaultRoot(), vaultRootBefore, "Vault root should be preserved after upgrade");
    }

    function test_Upgrade_MigrationConfigPreserved() public {
        address managerBefore = starkExProxy.migrationManager();
        address bridgeBefore = starkExProxy.zkEVMBridge();

        _upgradeTo();

        assertEq(starkExProxy.migrationManager(), managerBefore, "Migration manager should be preserved");
        assertEq(starkExProxy.zkEVMBridge(), bridgeBefore, "zkEVM bridge should be preserved");
    }

    function test_Upgrade_PendingWithdrawalsPopulated() public {
        _upgradeTo();

        uint256 vcoAssetType = starkExProxy.VCO_ASSET_TYPE();
        uint256 quantum = starkExProxy.getQuantum(vcoAssetType);

        assertEq(
            starkExProxy.getWithdrawalBalance(starkExProxy.HOLDER_1_KEY(), vcoAssetType),
            starkExProxy.HOLDER_1_AMOUNT() * quantum,
            "Holder 1 pending withdrawal should be set"
        );
        assertEq(
            starkExProxy.getWithdrawalBalance(starkExProxy.HOLDER_7_KEY(), vcoAssetType),
            starkExProxy.HOLDER_7_AMOUNT() * quantum,
            "Holder 7 pending withdrawal should be set"
        );
    }

    function test_Upgrade_EthKeysRegistered() public {
        // Holder 1's stark key (hardcoded because proxy doesn't expose constants before upgrade)
        uint256 holder1Key = 0x07d2ca42b17532a203fa5ed81a3a5abf5b16e05bd46b5583e05265b09a3f4753;

        // Holder 1 is not registered before upgrade
        assertEq(starkExProxy.getEthKey(holder1Key), address(0), "Holder 1 should not be registered before upgrade");

        _upgradeTo();

        // After upgrade, holder 1 should be registered via initialize
        assertEq(
            starkExProxy.getEthKey(holder1Key),
            starkExProxy.HOLDER_1_ETH(),
            "Holder 1 should be registered after upgrade"
        );
    }

    function test_Upgrade_EthKeysNotOverwrittenIfAlreadyRegistered() public {
        // Holder 6's stark key (hardcoded because proxy doesn't expose constants before upgrade)
        uint256 holder6Key = 0x025ee41b0f85758eab738070b553e0f966776481df6d3bc4c57858909080ca01;

        // Holder 6 is already registered on-chain before upgrade
        address existingEth = starkExProxy.getEthKey(holder6Key);
        assertNotEq(existingEth, address(0), "Holder 6 should already be registered");

        _upgradeTo();

        // Should not be overwritten
        assertEq(starkExProxy.getEthKey(holder6Key), existingEth, "Holder 6 ethKey should not be overwritten");
    }

    function test_Upgrade_VCOWithdrawalWorks_PreviouslyRegisteredHolder() public {
        _upgradeTo();

        uint256 holderKey = starkExProxy.HOLDER_6_KEY();
        uint256 vcoAssetType = starkExProxy.VCO_ASSET_TYPE();
        address recipient = starkExProxy.getEthKey(holderKey);
        require(recipient != address(0), "Holder key must resolve to valid address");

        uint256 vcoBalanceBefore = IERC20(VCO_TOKEN).balanceOf(recipient);
        uint256 expectedWithdrawal = starkExProxy.getWithdrawalBalance(holderKey, vcoAssetType);
        assertGt(expectedWithdrawal, 0, "Expected withdrawal should be non-zero");

        starkExProxy.withdraw(holderKey, vcoAssetType);

        assertEq(
            IERC20(VCO_TOKEN).balanceOf(recipient),
            vcoBalanceBefore + expectedWithdrawal,
            "Recipient should receive VCO tokens"
        );
        assertEq(starkExProxy.getWithdrawalBalance(holderKey, vcoAssetType), 0, "Pending balance should be cleared");
    }

    function test_Upgrade_VCOWithdrawalWorks_NewlyRegisteredHolder() public {
        _upgradeTo();

        // Holder 1 was not registered on-chain before upgrade, but initialize registered them
        uint256 holderKey = starkExProxy.HOLDER_1_KEY();
        uint256 vcoAssetType = starkExProxy.VCO_ASSET_TYPE();
        address recipient = starkExProxy.getEthKey(holderKey);
        assertEq(recipient, starkExProxy.HOLDER_1_ETH(), "Holder 1 should be registered by initialize");

        uint256 vcoBalanceBefore = IERC20(VCO_TOKEN).balanceOf(recipient);
        uint256 expectedWithdrawal = starkExProxy.getWithdrawalBalance(holderKey, vcoAssetType);
        assertGt(expectedWithdrawal, 0, "Expected withdrawal should be non-zero");

        starkExProxy.withdraw(holderKey, vcoAssetType);

        assertEq(
            IERC20(VCO_TOKEN).balanceOf(recipient),
            vcoBalanceBefore + expectedWithdrawal,
            "Recipient should receive VCO tokens"
        );
        assertEq(starkExProxy.getWithdrawalBalance(holderKey, vcoAssetType), 0, "Pending balance should be cleared");
    }
}
