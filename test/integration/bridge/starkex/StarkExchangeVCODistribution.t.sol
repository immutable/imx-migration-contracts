// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import "@src/bridge/starkex/StarkExchangeVCODistribution.sol";
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

    // StarkExchangeVCODistribution constants
    function VCO_ASSET_TYPE() external view returns (uint256);
    function HOLDER_1_KEY() external view returns (uint256);
    function HOLDER_1_AMOUNT() external view returns (uint256);
    function HOLDER_2_KEY() external view returns (uint256);
    function HOLDER_2_AMOUNT() external view returns (uint256);
    function HOLDER_3_KEY() external view returns (uint256);
    function HOLDER_3_AMOUNT() external view returns (uint256);
    function HOLDER_4_KEY() external view returns (uint256);
    function HOLDER_4_AMOUNT() external view returns (uint256);
    function HOLDER_5_KEY() external view returns (uint256);
    function HOLDER_5_AMOUNT() external view returns (uint256);
    function HOLDER_6_KEY() external view returns (uint256);
    function HOLDER_6_AMOUNT() external view returns (uint256);
    function HOLDER_7_KEY() external view returns (uint256);
    function HOLDER_7_AMOUNT() external view returns (uint256);

    // StarkExchangeMigration functions
    function migrationManager() external view returns (address);
    function zkEVMBridge() external view returns (address);
}

contract StarkExchangeVCODistributionIntegrationTest is Test {
    IStarkExchangeProxy public constant starkExProxy = IStarkExchangeProxy(0x5FDCCA53617f4d2b9134B29090C87D01058e27e9);
    address private constant STARKEX_PROXY_OWNER = 0xD2C37fC6fD89563187f3679304975655e448D192;
    address private constant VCO_TOKEN = 0x2Caa4021e580b07D92adf8A40Ec53b33a215D620;

    function setUp() public {
        string memory RPC_URL = vm.envString("ETH_RPC_URL");
        vm.createSelectFork(RPC_URL);
    }

    function _upgradeToVCODistribution() internal returns (address) {
        vm.startPrank(STARKEX_PROXY_OWNER);

        address newImpl = address(new StarkExchangeVCODistribution());
        bytes memory initData = bytes("");

        starkExProxy.addImplementation(newImpl, initData, false);
        skip(15 days);
        starkExProxy.upgradeTo(newImpl, initData, false);

        vm.stopPrank();
        return newImpl;
    }

    function test_Upgrade_ImplementationUpdated() public {
        address newImpl = _upgradeToVCODistribution();
        assertEq(starkExProxy.implementation(), newImpl, "Implementation should be updated");
    }

    function test_Upgrade_VaultRootPreserved() public {
        uint256 vaultRootBefore = starkExProxy.vaultRoot();
        assertNotEq(vaultRootBefore, 0, "Vault root should not be zero before upgrade");

        _upgradeToVCODistribution();

        assertEq(starkExProxy.vaultRoot(), vaultRootBefore, "Vault root should be preserved after upgrade");
    }

    function test_Upgrade_MigrationConfigPreserved() public {
        address managerBefore = starkExProxy.migrationManager();
        address bridgeBefore = starkExProxy.zkEVMBridge();

        _upgradeToVCODistribution();

        assertEq(starkExProxy.migrationManager(), managerBefore, "Migration manager should be preserved");
        assertEq(starkExProxy.zkEVMBridge(), bridgeBefore, "zkEVM bridge should be preserved");
    }

    function test_Upgrade_PendingWithdrawalsPopulated() public {
        _upgradeToVCODistribution();

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

    function test_Upgrade_VCOWithdrawalWorks() public {
        _upgradeToVCODistribution();

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
}
