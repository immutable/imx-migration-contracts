// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import "@src/bridge/starkex/StarkExchangeMigration.sol";
import "@src/bridge/starkex/IStarkExchangeMigration.sol";
import "@src/bridge/zkEVM/IRootERC20Bridge.sol";
import "@src/bridge/messaging/VaultRootSenderAdapter.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title MockERC20
 * @notice Mock ERC20 token for testing
 */
contract MockERC20 is ERC20 {
    uint8 private _decimals;

    constructor(string memory name, string memory symbol, uint8 decimals_) ERC20(name, symbol) {
        _decimals = decimals_;
        _mint(msg.sender, 1000000 * 10 ** decimals_);
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
 * @notice Mock implementation of IRootERC20Bridge for testing
 */
contract MockRootERC20Bridge is IRootERC20Bridge {
    mapping(IERC20Metadata => uint256) public deposits;
    mapping(address => uint256) public ethDeposits;

    event DepositCalled(IERC20Metadata token, uint256 amount);
    event DepositToCalled(IERC20Metadata token, address receiver, uint256 amount);
    event DepositETHCalled(uint256 amount);
    event DepositToETHCalled(address receiver, uint256 amount);

    function deposit(IERC20Metadata rootToken, uint256 amount) external payable override {
        deposits[rootToken] += amount;
        bool success = rootToken.transferFrom(msg.sender, address(this), amount);
        require(success, "Transfer failed");
        emit DepositCalled(rootToken, amount);
    }

    function depositTo(IERC20Metadata rootToken, address receiver, uint256 amount) external payable override {
        deposits[rootToken] += amount;
        bool success = rootToken.transferFrom(msg.sender, address(this), amount);
        require(success, "Transfer failed");
        emit DepositToCalled(rootToken, receiver, amount);
    }

    function depositETH(uint256 amount) external payable override {
        require(msg.value >= amount, "Insufficient ETH");
        ethDeposits[msg.sender] += amount;
        emit DepositETHCalled(amount);
    }

    function depositToETH(address receiver, uint256 amount) external payable override {
        require(msg.value >= amount, "Insufficient ETH");
        ethDeposits[receiver] += amount;
        emit DepositToETHCalled(receiver, amount);
    }
}

/**
 * @title MockVaultRootSenderAdapter
 * @notice Mock implementation of VaultRootSenderAdapter for testing
 */
contract MockVaultRootSenderAdapter {
    uint256 public lastVaultRoot;
    address public lastRefundAddress;
    uint256 public lastBridgeFee;

    event SendVaultRootCalled(uint256 vaultRoot, address refundAddress);

    function sendVaultRoot(uint256 vaultRoot, address refundAddress) external payable {
        lastVaultRoot = vaultRoot;
        lastRefundAddress = refundAddress;
        lastBridgeFee = msg.value;
        emit SendVaultRootCalled(vaultRoot, refundAddress);
    }
}

contract StarkExchangeMigrationTest is Test {
    StarkExchangeMigration public starkExBridge;
    MockRootERC20Bridge public mockBridge;
    MockVaultRootSenderAdapter public mockSenderAdapter;
    MockERC20 public testToken;

    address private constant MIGRATION_MANAGER = 0x1234567890123456789012345678901234567890;
    address private constant WITHDRAWAL_PROCESSOR = 0x9999999999999999999999999999999999999999;
    address private constant UNAUTHORIZED_ADDRESS = 0x8888888888888888888888888888888888888888;

    uint256 private constant TEST_VAULT_ROOT = 0x1234567890123456789012345678901234567890123456789012345678901234;
    uint256 private constant BRIDGE_FEE = 0.001 ether;

    function setUp() public {
        starkExBridge = new StarkExchangeMigration();
        mockBridge = new MockRootERC20Bridge();
        mockSenderAdapter = new MockVaultRootSenderAdapter();
        testToken = new MockERC20("Test Token", "TEST", 18);

        bytes memory initData =
            abi.encode(MIGRATION_MANAGER, address(mockBridge), address(mockSenderAdapter), WITHDRAWAL_PROCESSOR);
        starkExBridge.initialize(initData);

        vm.store(address(starkExBridge), bytes32(uint256(13)), bytes32(TEST_VAULT_ROOT));
        vm.deal(MIGRATION_MANAGER, 10 ether);
    }

    function test_Initialize_ValidParameters() public {
        StarkExchangeMigration newMigration = new StarkExchangeMigration();

        bytes memory initData =
            abi.encode(MIGRATION_MANAGER, address(mockBridge), address(mockSenderAdapter), WITHDRAWAL_PROCESSOR);

        newMigration.initialize(initData);

        assertEq(newMigration.migrationManager(), MIGRATION_MANAGER, "Migration manager should be set");
        assertEq(newMigration.zkEVMBridge(), address(mockBridge), "zkEVM bridge should be set");
        assertEq(
            address(newMigration.rootSenderAdapter()), address(mockSenderAdapter), "Root sender adapter should be set"
        );
        assertEq(newMigration.zkEVMWithdrawalProcessor(), WITHDRAWAL_PROCESSOR, "Withdrawal processor should be set");
    }

    function test_RevertIf_Initialize_InvalidMigrationManager() public {
        StarkExchangeMigration newMigration = new StarkExchangeMigration();

        bytes memory initData = abi.encode(
            address(0), // Invalid migration manager
            address(mockBridge),
            address(mockSenderAdapter),
            WITHDRAWAL_PROCESSOR
        );

        vm.expectRevert(IStarkExchangeMigration.InvalidAddress.selector);
        newMigration.initialize(initData);
    }

    function test_RevertIf_Initialize_InvalidZkEVMBridge() public {
        StarkExchangeMigration newMigration = new StarkExchangeMigration();

        bytes memory initData = abi.encode(
            MIGRATION_MANAGER,
            address(0), // Invalid zkEVM bridge
            address(mockSenderAdapter),
            WITHDRAWAL_PROCESSOR
        );

        vm.expectRevert(IStarkExchangeMigration.InvalidAddress.selector);
        newMigration.initialize(initData);
    }

    function test_RevertIf_Initialize_InvalidRootSenderAdapter() public {
        StarkExchangeMigration newMigration = new StarkExchangeMigration();

        bytes memory initData = abi.encode(
            MIGRATION_MANAGER,
            address(mockBridge),
            address(0), // Invalid root sender adapter
            WITHDRAWAL_PROCESSOR
        );

        vm.expectRevert(IStarkExchangeMigration.InvalidAddress.selector);
        newMigration.initialize(initData);
    }

    function test_RevertIf_Initialize_InvalidWithdrawalProcessor() public {
        StarkExchangeMigration newMigration = new StarkExchangeMigration();

        bytes memory initData = abi.encode(
            MIGRATION_MANAGER,
            address(mockBridge),
            address(mockSenderAdapter),
            address(0) // Invalid withdrawal processor
        );

        vm.expectRevert(IStarkExchangeMigration.InvalidAddress.selector);
        newMigration.initialize(initData);
    }

    function test_RevertIf_Initialize_Twice() public {
        StarkExchangeMigration newMigration = new StarkExchangeMigration();

        bytes memory initData =
            abi.encode(MIGRATION_MANAGER, address(mockBridge), address(mockSenderAdapter), WITHDRAWAL_PROCESSOR);

        newMigration.initialize(initData);

        vm.expectRevert();
        newMigration.initialize(initData);
    }

    function test_MigrateVaultRoot() public {
        vm.prank(MIGRATION_MANAGER);
        starkExBridge.migrateVaultRoot{value: BRIDGE_FEE}();

        assertEq(mockSenderAdapter.lastVaultRoot(), TEST_VAULT_ROOT, "Vault root should be sent");
        assertEq(mockSenderAdapter.lastRefundAddress(), MIGRATION_MANAGER, "Refund address should be migration manager");
        assertEq(mockSenderAdapter.lastBridgeFee(), BRIDGE_FEE, "Bridge fee should be passed through");
    }

    function test_RevertIf_MigrateVaultRoot_Unauthorized() public {
        vm.deal(UNAUTHORIZED_ADDRESS, 1 ether);
        vm.prank(UNAUTHORIZED_ADDRESS);
        vm.expectRevert(IStarkExchangeMigration.UnauthorizedMigrationInitiator.selector);
        starkExBridge.migrateVaultRoot{value: BRIDGE_FEE}();
    }

    function test_MigrateHoldings_ETH() public {
        uint256 ethAmount = 1 ether;
        IStarkExchangeMigration.TokenMigrationDetails[] memory assets =
            new IStarkExchangeMigration.TokenMigrationDetails[](1);
        assets[0] = IStarkExchangeMigration.TokenMigrationDetails({
            token: starkExBridge.NATIVE_ETH(), amount: ethAmount, bridgeFee: BRIDGE_FEE
        });

        vm.deal(address(starkExBridge), ethAmount);
        vm.expectEmit(true, true, true, true);
        emit IStarkExchangeMigration.ETHHoldingsMigration(ethAmount, WITHDRAWAL_PROCESSOR, MIGRATION_MANAGER);

        vm.prank(MIGRATION_MANAGER);
        starkExBridge.migrateHoldings{value: BRIDGE_FEE}(assets);

        assertEq(mockBridge.ethDeposits(WITHDRAWAL_PROCESSOR), ethAmount, "ETH should be deposited to bridge");
    }

    function test_MigrateHoldings_ERC20() public {
        uint256 tokenAmount = 10 ether;
        IStarkExchangeMigration.TokenMigrationDetails[] memory assets =
            new IStarkExchangeMigration.TokenMigrationDetails[](1);
        assets[0] = IStarkExchangeMigration.TokenMigrationDetails({
            token: address(testToken), amount: tokenAmount, bridgeFee: BRIDGE_FEE
        });

        deal(address(testToken), address(starkExBridge), tokenAmount);

        vm.expectEmit(true, true, true, true);
        emit IStarkExchangeMigration.ERC20HoldingsMigration(
            address(testToken), tokenAmount, WITHDRAWAL_PROCESSOR, MIGRATION_MANAGER
        );

        vm.prank(MIGRATION_MANAGER);
        starkExBridge.migrateHoldings{value: BRIDGE_FEE}(assets);

        assertEq(
            mockBridge.deposits(IERC20Metadata(address(testToken))), tokenAmount, "Tokens should be deposited to bridge"
        );
    }

    function test_MigrateHoldings_Mixed() public {
        uint256 ethAmount = 1 ether;
        uint256 tokenAmount = 100 ether;

        IStarkExchangeMigration.TokenMigrationDetails[] memory assets =
            new IStarkExchangeMigration.TokenMigrationDetails[](2);
        assets[0] = IStarkExchangeMigration.TokenMigrationDetails({
            token: starkExBridge.NATIVE_ETH(), amount: ethAmount, bridgeFee: BRIDGE_FEE
        });
        assets[1] = IStarkExchangeMigration.TokenMigrationDetails({
            token: address(testToken), amount: tokenAmount, bridgeFee: BRIDGE_FEE
        });

        vm.deal(address(starkExBridge), ethAmount);
        deal(address(testToken), address(starkExBridge), tokenAmount);

        vm.expectEmit(true, true, true, true);
        emit IStarkExchangeMigration.ETHHoldingsMigration(ethAmount, WITHDRAWAL_PROCESSOR, MIGRATION_MANAGER);
        vm.expectEmit(true, true, true, true);
        emit IStarkExchangeMigration.ERC20HoldingsMigration(
            address(testToken), tokenAmount, WITHDRAWAL_PROCESSOR, MIGRATION_MANAGER
        );

        vm.prank(MIGRATION_MANAGER);
        starkExBridge.migrateHoldings{value: 2 * BRIDGE_FEE}(assets);

        assertEq(mockBridge.ethDeposits(WITHDRAWAL_PROCESSOR), ethAmount, "ETH should be deposited to bridge");
        assertEq(
            mockBridge.deposits(IERC20Metadata(address(testToken))), tokenAmount, "Tokens should be deposited to bridge"
        );
    }

    function test_RevertIf_MigrateHoldings_EmptyArray() public {
        IStarkExchangeMigration.TokenMigrationDetails[] memory emptyAssets =
            new IStarkExchangeMigration.TokenMigrationDetails[](0);

        vm.prank(MIGRATION_MANAGER);
        vm.expectRevert(IStarkExchangeMigration.NoMigrationDetails.selector);
        starkExBridge.migrateHoldings(emptyAssets);
    }

    function test_RevertIf_MigrateHoldings_Unauthorized() public {
        uint256 ethAmount = 1 ether;
        IStarkExchangeMigration.TokenMigrationDetails[] memory assets =
            new IStarkExchangeMigration.TokenMigrationDetails[](1);
        assets[0] = IStarkExchangeMigration.TokenMigrationDetails({
            token: starkExBridge.NATIVE_ETH(), amount: ethAmount, bridgeFee: BRIDGE_FEE
        });

        vm.deal(UNAUTHORIZED_ADDRESS, 2 ether);
        vm.prank(UNAUTHORIZED_ADDRESS);
        vm.expectRevert(IStarkExchangeMigration.UnauthorizedMigrationInitiator.selector);
        starkExBridge.migrateHoldings{value: BRIDGE_FEE}(assets);
    }

    function test_RevertIf_MigrateHoldings_ZeroTokenAddress() public {
        uint256 tokenAmount = 10 ether;
        IStarkExchangeMigration.TokenMigrationDetails[] memory assets =
            new IStarkExchangeMigration.TokenMigrationDetails[](1);
        assets[0] = IStarkExchangeMigration.TokenMigrationDetails({
            token: address(0), // Invalid token address
            amount: tokenAmount,
            bridgeFee: BRIDGE_FEE
        });

        vm.prank(MIGRATION_MANAGER);
        vm.expectRevert(IStarkExchangeMigration.InvalidAddress.selector);
        starkExBridge.migrateHoldings{value: BRIDGE_FEE}(assets);
    }

    function test_RevertIf_MigrateHoldings_ZeroAmount() public {
        IStarkExchangeMigration.TokenMigrationDetails[] memory assets =
            new IStarkExchangeMigration.TokenMigrationDetails[](1);
        assets[0] = IStarkExchangeMigration.TokenMigrationDetails({
            token: address(testToken), amount: 0, bridgeFee: BRIDGE_FEE
        });

        vm.prank(MIGRATION_MANAGER);
        vm.expectRevert(IStarkExchangeMigration.InvalidAmount.selector);
        starkExBridge.migrateHoldings{value: BRIDGE_FEE}(assets);
    }

    function test_RevertIf_MigrateHoldings_InsufficientTokenBalance() public {
        uint256 excessiveAmount = 20 ether; // More than available balance
        IStarkExchangeMigration.TokenMigrationDetails[] memory assets =
            new IStarkExchangeMigration.TokenMigrationDetails[](1);
        assets[0] = IStarkExchangeMigration.TokenMigrationDetails({
            token: address(testToken), amount: excessiveAmount, bridgeFee: BRIDGE_FEE
        });

        vm.prank(MIGRATION_MANAGER);
        vm.expectRevert(IStarkExchangeMigration.AmountExceedsBalance.selector);
        starkExBridge.migrateHoldings{value: BRIDGE_FEE}(assets);
    }

    function test_RevertIf_MigrateHoldings_InsufficientETHBalance() public {
        uint256 excessiveAmount = 2 ether;
        IStarkExchangeMigration.TokenMigrationDetails[] memory assets =
            new IStarkExchangeMigration.TokenMigrationDetails[](1);
        assets[0] = IStarkExchangeMigration.TokenMigrationDetails({
            token: starkExBridge.NATIVE_ETH(), amount: excessiveAmount, bridgeFee: BRIDGE_FEE
        });

        vm.prank(MIGRATION_MANAGER);
        vm.expectRevert(IStarkExchangeMigration.AmountExceedsBalance.selector);
        starkExBridge.migrateHoldings{value: BRIDGE_FEE}(assets);
    }

    function test_RevertIf_MigrateHoldings_InsufficientBridgeFee() public {
        uint256 tokenAmount = 10 ether;
        IStarkExchangeMigration.TokenMigrationDetails[] memory assets =
            new IStarkExchangeMigration.TokenMigrationDetails[](1);
        assets[0] = IStarkExchangeMigration.TokenMigrationDetails({
            token: address(testToken), amount: tokenAmount, bridgeFee: BRIDGE_FEE
        });

        vm.prank(MIGRATION_MANAGER);
        vm.expectRevert(IStarkExchangeMigration.InsufficientBridgeFee.selector);
        starkExBridge.migrateHoldings{value: BRIDGE_FEE - 0.0001 ether}(assets);
    }

    function test_RevertIf_MigrateHoldings_ExcessBridgeFee() public {
        uint256 tokenAmount = 1 ether;
        IStarkExchangeMigration.TokenMigrationDetails[] memory assets =
            new IStarkExchangeMigration.TokenMigrationDetails[](1);
        assets[0] = IStarkExchangeMigration.TokenMigrationDetails({
            token: address(testToken), amount: tokenAmount, bridgeFee: BRIDGE_FEE
        });

        deal(address(testToken), address(starkExBridge), tokenAmount);

        vm.prank(MIGRATION_MANAGER);
        vm.expectRevert(IStarkExchangeMigration.ExcessBridgeFeeProvided.selector);
        starkExBridge.migrateHoldings{value: BRIDGE_FEE + 0.01 ether}(assets);
    }
}
