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
import {EllipticCurve} from "@src/bridge/starkex/libraries/EllipticCurve.sol";
import {StarkCurveECDSA} from "@src/bridge/starkex/libraries/StarkCurveECDSA.sol";

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
        assetTypeToAssetInfo[assetType] =
            abi.encodePacked(bytes4(keccak256("ERC20Token(address)")), abi.encode(tokenAddress));
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

    function setPendingWithdrawal(uint256 ownerKey, uint256 assetId, uint256 quantizedAmount) external {
        pendingWithdrawals[ownerKey][assetId] = quantizedAmount;
    }
}

contract StarkExchangeVCODistributionTest is Test {
    StarkExchangeVCODistributionHarness public bridge;
    MockERC20 public vcoToken;

    uint256 constant VCO_QUANTUM = 1;

    // Ethereum addresses corresponding to each holder's Stark key
    address constant HOLDER_1_ETH = 0x5eBb994EBC1c44815FbF2fA61a6E1f8368dcB0C7;
    address constant HOLDER_2_ETH = 0x216e8577B504aC3dB213eDd261e47fffBb354248;
    address constant HOLDER_3_ETH = 0x10cbBBb225BBEA137aC01F0F6D91CDB126BccaA6;
    address constant HOLDER_4_ETH = 0x409F85D2207796b543b8abdB6a0E2490BB1483D1;
    address constant HOLDER_5_ETH = 0xCE5A537D4dA620DE59efA6F74a0A065732600c71;
    address constant HOLDER_6_ETH = 0x941f54cb53Dc1478Cb126a2Ba8a83b2130419dB5;
    address constant HOLDER_7_ETH = 0xBC6EeB5111fEa2B5e9B2Bc534bBcbCa9568999a4;

    function setUp() public {
        // Deploy mock VCO token
        vcoToken = new MockERC20("VCO Token", "VCO", 18);

        // Deploy harness behind ERC1967Proxy
        StarkExchangeVCODistributionHarness implementation = new StarkExchangeVCODistributionHarness();
        bytes memory initCallData = abi.encodeWithSelector(StarkExchangeVCODistribution.initialize.selector, bytes(""));
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initCallData);
        bridge = StarkExchangeVCODistributionHarness(address(proxy));

        // Register VCO asset type in legacy storage (required for withdraw to work)
        bridge.setupAssetType(bridge.VCO_ASSET_TYPE(), VCO_QUANTUM, address(vcoToken));

        // Register Stark key → Ethereum address mappings (simulates registerEthAddress calls)
        bridge.setupEthKey(bridge.HOLDER_1_KEY(), HOLDER_1_ETH);
        bridge.setupEthKey(bridge.HOLDER_2_KEY(), HOLDER_2_ETH);
        bridge.setupEthKey(bridge.HOLDER_3_KEY(), HOLDER_3_ETH);
        bridge.setupEthKey(bridge.HOLDER_4_KEY(), HOLDER_4_ETH);
        bridge.setupEthKey(bridge.HOLDER_5_KEY(), HOLDER_5_ETH);
        bridge.setupEthKey(bridge.HOLDER_6_KEY(), HOLDER_6_ETH);
        bridge.setupEthKey(bridge.HOLDER_7_KEY(), HOLDER_7_ETH);
    }

    function test_Initialize_DeploysSuccessfully() public view {
        assertEq(
            bridge.VCO_ASSET_TYPE(),
            1485183671027309009439509871835489442660821279230223034298428454062208985878,
            "VCO asset type should match"
        );
    }

    // -----------------------------------------------------------------------
    // Task 3: Initialization correctness and guards
    // -----------------------------------------------------------------------

    function test_Initialize_SetsAllPendingWithdrawals() public view {
        uint256 vcoAssetType = bridge.VCO_ASSET_TYPE();

        assertEq(bridge.getWithdrawalBalance(bridge.HOLDER_1_KEY(), vcoAssetType), bridge.HOLDER_1_AMOUNT());
        assertEq(bridge.getWithdrawalBalance(bridge.HOLDER_2_KEY(), vcoAssetType), bridge.HOLDER_2_AMOUNT());
        assertEq(bridge.getWithdrawalBalance(bridge.HOLDER_3_KEY(), vcoAssetType), bridge.HOLDER_3_AMOUNT());
        assertEq(bridge.getWithdrawalBalance(bridge.HOLDER_4_KEY(), vcoAssetType), bridge.HOLDER_4_AMOUNT());
        assertEq(bridge.getWithdrawalBalance(bridge.HOLDER_5_KEY(), vcoAssetType), bridge.HOLDER_5_AMOUNT());
        assertEq(bridge.getWithdrawalBalance(bridge.HOLDER_6_KEY(), vcoAssetType), bridge.HOLDER_6_AMOUNT());
        assertEq(bridge.getWithdrawalBalance(bridge.HOLDER_7_KEY(), vcoAssetType), bridge.HOLDER_7_AMOUNT());
    }

    function test_RevertIf_Initialize_CalledTwice() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        bridge.initialize(bytes(""));
    }

    function test_Constructor_DisablesInitializers_OnImplementation() public {
        StarkExchangeVCODistribution implementation = new StarkExchangeVCODistribution();
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        implementation.initialize(bytes(""));
    }

    // -----------------------------------------------------------------------
    // Task 4: VCO withdrawal flow
    // -----------------------------------------------------------------------

    function test_Withdraw_SingleHolder() public {
        uint256 holderKey = bridge.HOLDER_1_KEY();
        uint256 vcoAssetType = bridge.VCO_ASSET_TYPE();
        uint256 expectedAmount = bridge.HOLDER_1_AMOUNT() * VCO_QUANTUM;

        // Fund the bridge with VCO tokens
        vcoToken.mint(address(bridge), expectedAmount);

        // Withdraw
        bridge.withdraw(holderKey, vcoAssetType);

        // Verify: recipient received tokens, pending balance is zero
        assertEq(vcoToken.balanceOf(HOLDER_1_ETH), expectedAmount, "Recipient should receive VCO tokens");
        assertEq(
            bridge.getWithdrawalBalance(holderKey, vcoAssetType), 0, "Pending balance should be zero after withdrawal"
        );
    }

    function test_Withdraw_AllHolders() public {
        uint256 vcoAssetType = bridge.VCO_ASSET_TYPE();

        uint256[7] memory keys = [
            bridge.HOLDER_1_KEY(),
            bridge.HOLDER_2_KEY(),
            bridge.HOLDER_3_KEY(),
            bridge.HOLDER_4_KEY(),
            bridge.HOLDER_5_KEY(),
            bridge.HOLDER_6_KEY(),
            bridge.HOLDER_7_KEY()
        ];
        uint256[7] memory amounts = [
            bridge.HOLDER_1_AMOUNT(),
            bridge.HOLDER_2_AMOUNT(),
            bridge.HOLDER_3_AMOUNT(),
            bridge.HOLDER_4_AMOUNT(),
            bridge.HOLDER_5_AMOUNT(),
            bridge.HOLDER_6_AMOUNT(),
            bridge.HOLDER_7_AMOUNT()
        ];
        address[7] memory ethAddresses =
            [HOLDER_1_ETH, HOLDER_2_ETH, HOLDER_3_ETH, HOLDER_4_ETH, HOLDER_5_ETH, HOLDER_6_ETH, HOLDER_7_ETH];

        // Fund bridge with total VCO needed
        uint256 total = 0;
        for (uint256 i = 0; i < 7; i++) {
            total += amounts[i] * VCO_QUANTUM;
        }
        vcoToken.mint(address(bridge), total);

        // Withdraw for each holder and verify
        for (uint256 i = 0; i < 7; i++) {
            uint256 expectedAmount = amounts[i] * VCO_QUANTUM;

            bridge.withdraw(keys[i], vcoAssetType);

            assertEq(vcoToken.balanceOf(ethAddresses[i]), expectedAmount, "Holder should receive correct VCO amount");
            assertEq(bridge.getWithdrawalBalance(keys[i], vcoAssetType), 0, "Pending balance should be cleared");
        }
    }

    function test_RevertIf_Withdraw_NoPendingBalance() public {
        uint256 vcoAssetType = bridge.VCO_ASSET_TYPE();

        // First withdraw succeeds
        uint256 holderKey = bridge.HOLDER_1_KEY();
        uint256 amount = bridge.HOLDER_1_AMOUNT() * VCO_QUANTUM;
        vcoToken.mint(address(bridge), amount);
        bridge.withdraw(holderKey, vcoAssetType);

        // Second withdraw for same holder reverts
        vm.expectRevert("NO_PENDING_WITHDRAWAL");
        bridge.withdraw(holderKey, vcoAssetType);
    }

    function test_Withdraw_EmitsLogWithdrawalPerformed() public {
        uint256 holderKey = bridge.HOLDER_1_KEY();
        uint256 vcoAssetType = bridge.VCO_ASSET_TYPE();
        uint256 quantizedAmount = bridge.HOLDER_1_AMOUNT();
        uint256 nonQuantizedAmount = quantizedAmount * VCO_QUANTUM;

        vcoToken.mint(address(bridge), nonQuantizedAmount);

        vm.expectEmit(true, true, true, true);
        emit LegacyStarkExchangeBridge.LogWithdrawalPerformed(
            holderKey, vcoAssetType, nonQuantizedAmount, quantizedAmount, HOLDER_1_ETH
        );

        bridge.withdraw(holderKey, vcoAssetType);
    }

    // -----------------------------------------------------------------------
    // Task 5: Preserved StarkExchangeMigration functionality
    // -----------------------------------------------------------------------

    function test_MigrateHoldings_PreservedFunctionality() public {
        address migrationManager = address(0xBEEF);
        MockRootERC20Bridge mockZkEVMBridge = new MockRootERC20Bridge();
        MockSenderAdapter mockSender = new MockSenderAdapter();
        address withdrawalProcessor = address(0xDEAD);

        bridge.setupMigrationConfig(
            migrationManager, address(mockZkEVMBridge), address(mockSender), withdrawalProcessor
        );

        // Create and fund a test ERC20
        MockERC20 testToken = new MockERC20("Test", "TST", 18);
        uint256 tokenAmount = 1 ether;
        testToken.mint(address(bridge), tokenAmount);

        IStarkExchangeMigration.TokenMigrationDetails[] memory assets =
            new IStarkExchangeMigration.TokenMigrationDetails[](1);
        assets[0] = IStarkExchangeMigration.TokenMigrationDetails({
            token: address(testToken), amount: tokenAmount, bridgeFee: 0.001 ether
        });

        vm.deal(migrationManager, 1 ether);
        vm.prank(migrationManager);
        bridge.migrateHoldings{value: 0.001 ether}(assets);

        assertEq(
            testToken.balanceOf(address(mockZkEVMBridge)), tokenAmount, "Tokens should be migrated to zkEVM bridge"
        );
    }

    function test_MigrateVaultRoot_PreservedFunctionality() public {
        address migrationManager = address(0xBEEF);
        MockSenderAdapter mockSender = new MockSenderAdapter();

        bridge.setupMigrationConfig(
            migrationManager, address(new MockRootERC20Bridge()), address(mockSender), address(0xDEAD)
        );

        // Set vault root in storage (slot 13)
        uint256 testVaultRoot = 0x1234567890abcdef;
        vm.store(address(bridge), bytes32(uint256(13)), bytes32(testVaultRoot));

        vm.deal(migrationManager, 1 ether);
        vm.prank(migrationManager);
        bridge.migrateVaultRoot{value: 0.001 ether}();

        // If it didn't revert, the function works. The mock sender doesn't store state,
        // so we verify via non-revert and the vault root is unchanged.
        assertEq(
            uint256(vm.load(address(bridge), bytes32(uint256(13)))), testVaultRoot, "Vault root should be preserved"
        );
    }

    function test_RevertIf_MigrateHoldings_Unauthorized() public {
        address migrationManager = address(0xBEEF);
        bridge.setupMigrationConfig(
            migrationManager, address(new MockRootERC20Bridge()), address(new MockSenderAdapter()), address(0xDEAD)
        );

        IStarkExchangeMigration.TokenMigrationDetails[] memory assets =
            new IStarkExchangeMigration.TokenMigrationDetails[](1);
        assets[0] = IStarkExchangeMigration.TokenMigrationDetails({
            token: address(vcoToken), amount: 1 ether, bridgeFee: 0.001 ether
        });

        address unauthorized = address(0xBAD);
        vm.deal(unauthorized, 1 ether);
        vm.prank(unauthorized);
        vm.expectRevert(IStarkExchangeMigration.UnauthorizedMigrationInitiator.selector);
        bridge.migrateHoldings{value: 0.001 ether}(assets);
    }

    // -----------------------------------------------------------------------
    // STARK key test helpers
    // -----------------------------------------------------------------------

    uint256 constant TEST_STARK_PRIVATE_KEY = 0x1234567890abcdef;
    uint256 constant TEST_NONCE = 0xfedcba9876543210;

    function _generateStarkKeyPair(uint256 privateKey) internal pure returns (uint256 pubX, uint256 pubY) {
        (pubX, pubY) = EllipticCurve.ecMul(
            privateKey,
            StarkCurveECDSA.EC_GEN_X,
            StarkCurveECDSA.EC_GEN_Y,
            StarkCurveECDSA.ALPHA,
            StarkCurveECDSA.FIELD_PRIME
        );
    }

    function _signRegistration(uint256 privateKey, uint256 nonce, address ethKey, uint256 starkKey, uint256 starkKeyY)
        internal
        pure
        returns (bytes memory)
    {
        uint256 msgHash =
            uint256(keccak256(abi.encodePacked("UserRegistration:", ethKey, starkKey))) % StarkCurveECDSA.EC_ORDER;

        // r = (nonce * G).x
        (uint256 r,) = EllipticCurve.ecMul(
            nonce,
            StarkCurveECDSA.EC_GEN_X,
            StarkCurveECDSA.EC_GEN_Y,
            StarkCurveECDSA.ALPHA,
            StarkCurveECDSA.FIELD_PRIME
        );

        // s = nonce^(-1) * (msgHash + r * privateKey) mod EC_ORDER
        uint256 rk = mulmod(r, privateKey, StarkCurveECDSA.EC_ORDER);
        uint256 sum = addmod(msgHash, rk, StarkCurveECDSA.EC_ORDER);
        uint256 nonceInv = EllipticCurve.invMod(nonce, StarkCurveECDSA.EC_ORDER);
        uint256 s = mulmod(nonceInv, sum, StarkCurveECDSA.EC_ORDER);

        return abi.encode(r, s, starkKeyY);
    }

    // -----------------------------------------------------------------------
    // registerEthAddress tests
    // -----------------------------------------------------------------------

    function test_RegisterEthAddress_Valid() public {
        (uint256 starkKey, uint256 starkKeyY) = _generateStarkKeyPair(TEST_STARK_PRIVATE_KEY);
        address ethKey = address(0x9876543210987654321098765432109876543210);

        bytes memory sig = _signRegistration(TEST_STARK_PRIVATE_KEY, TEST_NONCE, ethKey, starkKey, starkKeyY);

        bridge.registerEthAddress(ethKey, starkKey, sig);

        assertEq(bridge.getEthKey(starkKey), ethKey, "Registered eth key should match");
    }

    function test_RegisterSender_Valid() public {
        (uint256 starkKey, uint256 starkKeyY) = _generateStarkKeyPair(TEST_STARK_PRIVATE_KEY);
        address sender = address(0xABCDabcdABcDabcDaBCDAbcdABcdAbCdABcDABCd);

        bytes memory sig = _signRegistration(TEST_STARK_PRIVATE_KEY, TEST_NONCE, sender, starkKey, starkKeyY);

        vm.prank(sender);
        bridge.registerSender(starkKey, sig);

        assertEq(bridge.getEthKey(starkKey), sender, "Registered eth key should be msg.sender");
    }

    function test_RegisterEthAddress_EmitsLogUserRegistered() public {
        (uint256 starkKey, uint256 starkKeyY) = _generateStarkKeyPair(TEST_STARK_PRIVATE_KEY);
        address ethKey = address(0x9876543210987654321098765432109876543210);
        address caller = address(0x1111111111111111111111111111111111111111);

        bytes memory sig = _signRegistration(TEST_STARK_PRIVATE_KEY, TEST_NONCE, ethKey, starkKey, starkKeyY);

        vm.expectEmit(true, true, true, true);
        emit LegacyStarkExchangeBridge.LogUserRegistered(ethKey, starkKey, caller);

        vm.prank(caller);
        bridge.registerEthAddress(ethKey, starkKey, sig);
    }

    function test_RevertIf_RegisterEthAddress_ZeroStarkKey() public {
        vm.expectRevert("INVALID_STARK_KEY");
        bridge.registerEthAddress(address(0x1234), 0, bytes(new bytes(96)));
    }

    function test_RevertIf_RegisterEthAddress_StarkKeyTooLarge() public {
        uint256 kModulus = 0x800000000000011000000000000000000000000000000000000000000000001;
        vm.expectRevert("INVALID_STARK_KEY");
        bridge.registerEthAddress(address(0x1234), kModulus, bytes(new bytes(96)));
    }

    function test_RevertIf_RegisterEthAddress_ZeroEthAddress() public {
        (uint256 starkKey,) = _generateStarkKeyPair(TEST_STARK_PRIVATE_KEY);
        vm.expectRevert("INVALID_ETH_ADDRESS");
        bridge.registerEthAddress(address(0), starkKey, bytes(new bytes(96)));
    }

    function test_RevertIf_RegisterEthAddress_DuplicateRegistration() public {
        (uint256 starkKey, uint256 starkKeyY) = _generateStarkKeyPair(TEST_STARK_PRIVATE_KEY);
        address ethKey = address(0x9876543210987654321098765432109876543210);

        bytes memory sig = _signRegistration(TEST_STARK_PRIVATE_KEY, TEST_NONCE, ethKey, starkKey, starkKeyY);
        bridge.registerEthAddress(ethKey, starkKey, sig);

        // Second registration with same stark key should fail
        address ethKey2 = address(0x1111111111111111111111111111111111111111);
        bytes memory sig2 = _signRegistration(TEST_STARK_PRIVATE_KEY, TEST_NONCE, ethKey2, starkKey, starkKeyY);

        vm.expectRevert("STARK_KEY_UNAVAILABLE");
        bridge.registerEthAddress(ethKey2, starkKey, sig2);
    }

    function test_RevertIf_RegisterEthAddress_InvalidSignatureLength() public {
        (uint256 starkKey,) = _generateStarkKeyPair(TEST_STARK_PRIVATE_KEY);
        vm.expectRevert("INVALID_STARK_SIGNATURE_LENGTH");
        bridge.registerEthAddress(address(0x1234), starkKey, bytes(new bytes(64)));
    }

    function test_RevertIf_RegisterEthAddress_InvalidSignature() public {
        (uint256 starkKey, uint256 starkKeyY) = _generateStarkKeyPair(TEST_STARK_PRIVATE_KEY);
        address ethKey = address(0x9876543210987654321098765432109876543210);
        address wrongEthKey = address(0x1111111111111111111111111111111111111111);

        // Sign for ethKey but try to register wrongEthKey
        bytes memory sig = _signRegistration(TEST_STARK_PRIVATE_KEY, TEST_NONCE, ethKey, starkKey, starkKeyY);

        vm.expectRevert("INVALID_STARK_SIGNATURE");
        bridge.registerEthAddress(wrongEthKey, starkKey, sig);
    }

    function test_RevertIf_RegisterEthAddress_OffCurveKey() public {
        // Use a value that is in range (< K_MODULUS) but not on the Stark curve.
        // For y^2 = x^3 + x + beta (mod p), approximately half of x values are off-curve.
        uint256 offCurveKey = 5;
        vm.expectRevert("INVALID_STARK_KEY");
        bridge.registerEthAddress(address(0x1234), offCurveKey, bytes(new bytes(96)));
    }

    // -----------------------------------------------------------------------
    // Task 6: Register-then-withdraw end-to-end test
    // -----------------------------------------------------------------------

    function test_RegisterThenWithdraw_FullFlow() public {
        // Generate a STARK key pair (the public key x-coordinate is >160 bits)
        (uint256 starkKey, uint256 starkKeyY) = _generateStarkKeyPair(TEST_STARK_PRIVATE_KEY);
        address ethKey = address(0x9876543210987654321098765432109876543210);

        // Verify this key is actually >160 bits (would fail getEthKey without registration)
        assertGt(starkKey, type(uint160).max, "Stark key should be >160 bits for this test");
        assertEq(bridge.getEthKey(starkKey), address(0), "Key should not be registered yet");

        // Register the Stark key -> Ethereum address
        bytes memory sig = _signRegistration(TEST_STARK_PRIVATE_KEY, TEST_NONCE, ethKey, starkKey, starkKeyY);
        bridge.registerEthAddress(ethKey, starkKey, sig);
        assertEq(bridge.getEthKey(starkKey), ethKey, "Key should now be registered");

        // Set up a pending withdrawal for this stark key
        uint256 vcoAssetType = bridge.VCO_ASSET_TYPE();
        uint256 withdrawAmount = 1000;
        bridge.setPendingWithdrawal(starkKey, vcoAssetType, withdrawAmount);

        // Fund bridge with VCO tokens (quantum is 1, so nonQuantized == quantized)
        vcoToken.mint(address(bridge), withdrawAmount);

        // Withdraw — should succeed because the key is now registered
        bridge.withdraw(starkKey, vcoAssetType);

        // Verify recipient received tokens
        assertEq(vcoToken.balanceOf(ethKey), withdrawAmount, "Recipient should receive VCO tokens");
        assertEq(bridge.getWithdrawalBalance(starkKey, vcoAssetType), 0, "Pending balance should be cleared");
    }
}
