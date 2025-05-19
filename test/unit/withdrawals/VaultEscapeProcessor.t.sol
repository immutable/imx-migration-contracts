// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import "@src/withdrawals/VaultEscapeProcessor.sol";
import "../../../src/withdrawals/IVaultEscapeProcessor.sol";
import "../../../src/proofs/vaults/VaultEscapeProofVerifier.sol";
import "../../../src/proofs/accounts/IAccountProofVerifier.sol";
import "../../../src/assets/AssetsRegistry.sol";

contract MockAccountVerifier is IAccountProofVerifier {
    bool public shouldVerify;

    function setShouldVerify(bool _shouldVerify) external {
        shouldVerify = _shouldVerify;
    }

    function verify(uint256, address, bytes32[] calldata) external view override returns (bool) {
        return shouldVerify;
    }
}

contract MockVaultVerifier is VaultEscapeProofVerifier {
    bool public shouldVerify;

    constructor(address[63] memory lookupTables) VaultEscapeProofVerifier(lookupTables) {}

    function setShouldVerify(bool _shouldVerify) external {
        shouldVerify = _shouldVerify;
    }

    function verifyEscapeProof(uint256[] calldata) external view override returns (bool) {
        return shouldVerify;
    }
}

contract VaultEscapeProcessorTest is Test {
    VaultEscapeProcessor public processor;
    MockAccountVerifier public accountVerifier;
    MockVaultVerifier public vaultVerifier;

    // Test addresses
    address public constant TEST_ETH_ADDRESS = address(0xBEEF);
    uint256 public constant TEST_VAULT_ROOT = 0xdef0;

    // Test data
    uint256 public constant TEST_STARK_KEY = 0x1234;
    uint256 public constant TEST_ASSET_ID = 0x5678;
    uint256 public constant TEST_QUANTIZED_AMOUNT = 0x9abc;

    // Mock proof data
    bytes32[] public mockAccountProof;
    uint256[] public mockVaultProof;

    // Test assets
    AssetsRegistry.AssetDetails[] public testAssets;

    function setUp() public {
        // Deploy mock verifiers
        accountVerifier = new MockAccountVerifier();
        address[63] memory lookupTables;

        vaultVerifier = new MockVaultVerifier(lookupTables);

        // Initialize test assets
        testAssets = new AssetsRegistry.AssetDetails[](1);
        testAssets[0] =
            AssetsRegistry.AssetDetails({assetId: TEST_ASSET_ID, assetAddress: address(0xCAFE), quantum: 1e18});

        // Initialize processor
        processor =
            new VaultEscapeProcessor(address(accountVerifier), address(vaultVerifier), TEST_VAULT_ROOT, testAssets);

        // Initialize mock proofs
        mockAccountProof = new bytes32[](1);
        mockAccountProof[0] = bytes32(uint256(1));

        mockVaultProof = new uint256[](68); // Minimum valid length
        mockVaultProof[0] = TEST_STARK_KEY << 4;
        mockVaultProof[1] = TEST_ASSET_ID;
        mockVaultProof[3] = TEST_QUANTIZED_AMOUNT;
        mockVaultProof[66] = TEST_VAULT_ROOT << 4;
        mockVaultProof[67] = 0x1234 << 8;
    }

    function test_Constructor() public view {
        assertEq(address(processor.accountVerifier()), address(accountVerifier));
        assertEq(address(processor.vaultVerifier()), address(vaultVerifier));
        assertEq(processor.vaultRoot(), TEST_VAULT_ROOT);
    }

    function test_VerifyProofAndDisburseFunds_Success() public {
        // Set up mocks
        accountVerifier.setShouldVerify(true);
        vaultVerifier.setShouldVerify(true);

        // Fund the processor with test tokens
        address assetAddress = processor.getAssetAddress(TEST_ASSET_ID);
        deal(assetAddress, address(processor), TEST_QUANTIZED_AMOUNT * 1e18);

        // Process withdrawal
        bool success = processor.verifyProofAndDisburseFunds(TEST_ETH_ADDRESS, mockAccountProof, mockVaultProof);

        assertTrue(success);
    }

    function test_VerifyProofAndDisburseFunds_InvalidStarkKey() public {
        // Modify proof to have invalid starkKey
        mockVaultProof[0] = 0;

        vm.expectRevert(abi.encodeWithSelector(IVaultEscapeProcessor.InvalidVaultProof.selector, "Invalid Stark key"));
        processor.verifyProofAndDisburseFunds(TEST_ETH_ADDRESS, mockAccountProof, mockVaultProof);
    }

    function test_VerifyProofAndDisburseFunds_InvalidAssetId() public {
        // Modify proof to have invalid assetId
        mockVaultProof[1] = 0;

        vm.expectRevert(abi.encodeWithSelector(IVaultEscapeProcessor.InvalidVaultProof.selector, "Invalid asset ID"));
        processor.verifyProofAndDisburseFunds(TEST_ETH_ADDRESS, mockAccountProof, mockVaultProof);
    }

    function test_VerifyProofAndDisburseFunds_InvalidQuantizedAmount() public {
        // Modify proof to have invalid quantizedAmount
        mockVaultProof[3] = 0;

        vm.expectRevert(
            abi.encodeWithSelector(IVaultEscapeProcessor.InvalidVaultProof.selector, "Invalid quantized amount")
        );
        processor.verifyProofAndDisburseFunds(TEST_ETH_ADDRESS, mockAccountProof, mockVaultProof);
    }

    function test_VerifyProofAndDisburseFunds_InvalidRoot() public {
        // Modify proof to have invalid root
        mockVaultProof[66] = 0xffff << 4;

        vm.expectRevert(abi.encodeWithSelector(IVaultEscapeProcessor.InvalidVaultProof.selector, "Invalid root"));
        processor.verifyProofAndDisburseFunds(TEST_ETH_ADDRESS, mockAccountProof, mockVaultProof);
    }

    function test_VerifyProofAndDisburseFunds_UnknownAsset() public {
        // Modify proof to have unknown assetId
        mockVaultProof[1] = 0xffff;

        vm.expectRevert(abi.encodeWithSelector(IVaultEscapeProcessor.AssetNotRegistered.selector, 0xffff));
        processor.verifyProofAndDisburseFunds(TEST_ETH_ADDRESS, mockAccountProof, mockVaultProof);
    }

    function test_VerifyProofAndDisburseFunds_InvalidAccountProof() public {
        accountVerifier.setShouldVerify(false);

        vm.expectRevert(
            abi.encodeWithSelector(IVaultEscapeProcessor.InvalidAccountProof.selector, TEST_STARK_KEY, TEST_ETH_ADDRESS)
        );
        processor.verifyProofAndDisburseFunds(TEST_ETH_ADDRESS, mockAccountProof, mockVaultProof);
    }

    function test_VerifyProofAndDisburseFunds_InvalidVaultProof() public {
        accountVerifier.setShouldVerify(true);
        vaultVerifier.setShouldVerify(false);

        vm.expectRevert(abi.encodeWithSelector(IVaultEscapeProcessor.InvalidVaultProof.selector, "Invalid vault proof"));
        processor.verifyProofAndDisburseFunds(TEST_ETH_ADDRESS, mockAccountProof, mockVaultProof);
    }

    function test_VerifyProofAndDisburseFunds_DuplicateClaim() public {
        // Set up mocks
        accountVerifier.setShouldVerify(true);
        vaultVerifier.setShouldVerify(true);

        // Fund the processor with test tokens
        address assetAddress = processor.getAssetAddress(TEST_ASSET_ID);
        deal(assetAddress, address(processor), TEST_QUANTIZED_AMOUNT * 1e18);

        // Process first withdrawal
        processor.verifyProofAndDisburseFunds(TEST_ETH_ADDRESS, mockAccountProof, mockVaultProof);

        // Try to process the same withdrawal again
        vm.expectRevert(
            abi.encodeWithSelector(
                IVaultEscapeProcessor.FundAlreadyDisbursedForVault.selector, TEST_STARK_KEY, TEST_ASSET_ID
            )
        );
        processor.verifyProofAndDisburseFunds(TEST_ETH_ADDRESS, mockAccountProof, mockVaultProof);
    }
}
