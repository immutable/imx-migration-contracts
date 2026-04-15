// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import "@src/bridge/starkex/StarkExchangeVCODistribution.sol";
import "@src/bridge/starkex/IStarkExchangeMigration.sol";
import "@src/bridge/messaging/VaultRootSenderAdapter.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {LegacyStarkExchangeBridge} from "@src/bridge/starkex/LegacyStarkExchangeBridge.sol";

/**
 * @title MockERC20
 * @notice Mock ERC20 token for testing VCO withdrawals
 */
contract MockERC20 is ERC20 {
    uint8 private _decimals;

    constructor(string memory name, string memory symbol, uint8 decimals_) ERC20(name, symbol) {
        _decimals = decimals_;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/**
 * @title MockRootERC20Bridge
 * @notice Minimal mock for IRootERC20Bridge
 */
contract MockRootERC20Bridge {
    function deposit(IERC20Metadata, uint256) external payable {}
    function depositTo(IERC20Metadata rootToken, address, uint256 amount) external payable {
        rootToken.transferFrom(msg.sender, address(this), amount);
    }
    function depositETH(uint256) external payable {}
    function depositToETH(address, uint256) external payable {}
}

/**
 * @title MockSenderAdapter
 * @notice Minimal mock for VaultRootSenderAdapter
 */
contract MockSenderAdapter {
    function sendVaultRoot(uint256, address) external payable {}
}

/**
 * @title StarkExchangeVCODistributionHarness
 * @notice Test harness that exposes internal storage setters for legacy StarkEx state
 */
contract StarkExchangeVCODistributionHarness is StarkExchangeVCODistribution {
    function setupAssetType(uint256 assetType, uint256 quantum, address tokenAddress) external {
        registeredAssetType[assetType] = true;
        assetTypeToQuantum[assetType] = quantum;
        assetTypeToAssetInfo[assetType] = abi.encodePacked(
            bytes4(keccak256("ERC20Token(address)")),
            abi.encode(tokenAddress)
        );
    }

    function setupEthKey(uint256 ownerKey, address ethAddress) external {
        ethKeys[ownerKey] = ethAddress;
    }

    function setupMigrationConfig(
        address _migrationManager,
        address _zkEVMBridge,
        address _rootSenderAdapter,
        address _zkEVMWithdrawalProcessor
    ) external {
        migrationManager = _migrationManager;
        zkEVMBridge = _zkEVMBridge;
        rootSenderAdapter = VaultRootSenderAdapter(_rootSenderAdapter);
        zkEVMWithdrawalProcessor = _zkEVMWithdrawalProcessor;
    }
}

contract StarkExchangeVCODistributionTest is Test {
    StarkExchangeVCODistributionHarness public bridge;
    MockERC20 public vcoToken;

    uint256 constant VCO_QUANTUM = 1;

    function setUp() public {
        // Deploy mock VCO token
        vcoToken = new MockERC20("VCO Token", "VCO", 18);

        // Deploy harness behind ERC1967Proxy
        StarkExchangeVCODistributionHarness implementation = new StarkExchangeVCODistributionHarness();
        bytes memory initCallData =
            abi.encodeWithSelector(StarkExchangeVCODistribution.initialize.selector, bytes(""));
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initCallData);
        bridge = StarkExchangeVCODistributionHarness(address(proxy));

        // Register VCO asset type in legacy storage (required for withdraw to work)
        bridge.setupAssetType(bridge.VCO_ASSET_TYPE(), VCO_QUANTUM, address(vcoToken));
    }

    function test_Initialize_DeploysSuccessfully() public view {
        assertEq(
            bridge.VCO_ASSET_TYPE(),
            1485183671027309009439509871835489442660821279230223034298428454062208985878,
            "VCO asset type should match"
        );
    }
}
