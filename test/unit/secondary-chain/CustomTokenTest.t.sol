// SPDX-License-Identifier: LicenseRef-PolygonLabs-Source-Available
pragma solidity ^0.8.29;

// Test Base
import {
    CustomTokenTestBase,
    TestHarnessCustomToken,
    ITransparentUpgradeableProxy
} from "test/base/secondary-chain/CustomTokenTestBase.sol";

// Core contracts
import {CustomToken} from "src/secondary-chain/CustomToken.sol";

// OpenZeppelin
import {IAccessControl} from "@openzeppelin-contracts/access/IAccessControl.sol";

/// @dev CustomToken tests
contract CustomTokenTest is CustomTokenTestBase {
    function setUp() public virtual {
        deployCustomTokenInfrastructure();
    }

    /// Stateful fuzz of the permissionless ERC20 path. The token is seeded
    /// through the test harness, then transfer/allowance operations are
    /// chained and checked for conservation of total supply.
    function testFuzz_transferAllowanceConservation(uint256 minted, uint256 sent, uint256 pulled) public {
        minted = bound(minted, 1, 1e24);
        sent = bound(sent, 0, minted);
        pulled = bound(pulled, 0, minted - sent);

        // Seed the token through Foundry's local storage helper; no production
        // mint endpoint is invoked by this test.
        // Keep the ERC-20 totalSupply consistent with the seeded balance.
        deal(address(customTokenHarness), sender, minted, true);

        uint256 supplyBefore = customTokenHarness.totalSupply();
        vm.prank(sender);
        customTokenHarness.transfer(recipient, sent);

        vm.prank(sender);
        customTokenHarness.approve(address(this), pulled);
        customTokenHarness.transferFrom(sender, address(this), pulled);

        assertEq(customTokenHarness.totalSupply(), supplyBefore);
        assertEq(
            customTokenHarness.balanceOf(sender)
                + customTokenHarness.balanceOf(recipient)
                + customTokenHarness.balanceOf(address(this)),
            minted
        );
    }

    function testFuzz_statefulTransferChain(uint256 minted, uint256 first, uint256 second) public {
        minted = bound(minted, 3, 1e24);
        first = bound(first, 1, minted - 1);
        // The second leg spends the recipient's balance, so it cannot exceed
        // the amount transferred in the first leg.
        second = bound(second, 1, first);

        // Keep the ERC-20 totalSupply consistent with the seeded balance.
        deal(address(customTokenHarness), sender, minted, true);
        vm.prank(sender);
        customTokenHarness.transfer(recipient, first);
        vm.prank(recipient);
        customTokenHarness.approve(address(this), second);
        customTokenHarness.transferFrom(recipient, address(this), second);

        assertEq(customTokenHarness.totalSupply(), minted);
        assertEq(
            customTokenHarness.balanceOf(sender)
                + customTokenHarness.balanceOf(recipient)
                + customTokenHarness.balanceOf(address(this)),
            minted
        );
    }

    function _testInitializationRevert(
        bytes4 expectedError,
        address owner_,
        uint8 decimals_,
        address bridge_,
        address nativeConverter_
    ) internal {
        vm.revertToState(stateBeforeInitialize);

        vm.expectRevert(expectedError);
        bytes memory customTokenInitData =
            abi.encodeCall(TestHarnessCustomToken.reinitialize2, (owner_, decimals_, bridge_, nativeConverter_));
        bytes memory customTokenUpgradeData =
            abi.encodeCall(ITransparentUpgradeableProxy.upgradeToAndCall, (customTokenImpl, customTokenInitData));
        vm.prank(_getProxyAdmin(address(existingCustomTokenProxy)));
        (address(existingCustomTokenProxy).call(customTokenUpgradeData));
    }

    function test_initialize_revertsWithInvalidOwner() public {
        _testInitializationRevert(
            CustomToken.InvalidOwner.selector,
            address(0), // Invalid owner
            customTokenDecimals,
            address(mockAgglayerBridge),
            dummyNativeConverter
        );
    }

    function test_initialize_revertsWithInvalidDecimals() public {
        _testInitializationRevert(
            CustomToken.InvalidOriginalUnderlyingTokenDecimals.selector,
            owner,
            0, // Invalid decimals
            address(mockAgglayerBridge),
            dummyNativeConverter
        );
    }

    function test_initialize_revertsWithInvalidBridge() public {
        _testInitializationRevert(
            CustomToken.InvalidBridge.selector,
            owner,
            customTokenDecimals,
            address(0), // Invalid bridge
            dummyNativeConverter
        );
    }

    function test_pauseUnpause_transfer() public {
        deal(address(customTokenHarness), sender, 1000e18);

        bytes memory transferCallData = abi.encodeCall(customTokenHarness.transfer, (recipient, 100e18));
        _testPauseUnpause(proxyAdmin, address(customTokenHarness), transferCallData);
    }

    function test_pauseUnpause_transferFrom() public {
        deal(address(customTokenHarness), sender, 1000e18);
        vm.prank(sender);
        customTokenHarness.approve(proxyAdmin, 100e18);

        bytes memory transferFromCallData = abi.encodeCall(customTokenHarness.transferFrom, (sender, recipient, 100e18));
        _testPauseUnpause(proxyAdmin, address(customTokenHarness), transferFromCallData);
    }

    function test_pauseUnpause_approve() public {
        bytes memory approveCallData = abi.encodeCall(customTokenHarness.approve, (recipient, 100e18));

        _testPauseUnpause(proxyAdmin, address(customTokenHarness), approveCallData);
    }

    function test_pauseUnpause_permit() public {
        uint256 value = 100e18;
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = customTokenHarness.nonces(sender);

        bytes32 structHash = keccak256(abi.encode(PERMIT_TYPEHASH, sender, recipient, value, nonce, deadline));

        bytes32 domainHash = customTokenHarness.DOMAIN_SEPARATOR();
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainHash, structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(senderPrivateKey, digest);

        bytes memory permitCallData =
            abi.encodeCall(customTokenHarness.permit, (sender, recipient, value, deadline, v, r, s));

        _testPauseUnpause(proxyAdmin, address(customTokenHarness), permitCallData);
    }

    function test_pause_onlyPauserRole() public {
        vm.prank(sender);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                address(this),
                customTokenHarness.PAUSER_ROLE()
            )
        );
        customTokenHarness.pause();
    }

    function test_unpause_onlyAdminRole() public {
        vm.prank(owner);
        customTokenHarness.pause();

        // The default caller when no prank is set should not have admin role
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                address(this), // The test contract itself is the default caller
                customTokenHarness.DEFAULT_ADMIN_ROLE()
            )
        );
        customTokenHarness.unpause();
    }

    function test_pause_success() public {
        assertFalse(customTokenHarness.paused());

        vm.prank(owner);
        customTokenHarness.pause();

        assertTrue(customTokenHarness.paused());
    }

    function test_unpause_success() public {
        vm.prank(owner);
        customTokenHarness.pause();
        assertTrue(customTokenHarness.paused());

        vm.prank(owner);
        customTokenHarness.unpause();
        assertFalse(customTokenHarness.paused());
    }

    function test_erc20_transfer_success() public {
        uint256 amount = 100e18;
        deal(address(customTokenHarness), sender, amount);

        vm.prank(sender);
        bool success = customTokenHarness.transfer(recipient, amount);

        assertTrue(success);
        assertEq(customTokenHarness.balanceOf(sender), 0);
        assertEq(customTokenHarness.balanceOf(recipient), amount);
    }

    function test_erc20_transferFrom_success() public {
        uint256 amount = 100e18;
        deal(address(customTokenHarness), sender, amount);

        vm.prank(sender);
        customTokenHarness.approve(proxyAdmin, amount);

        vm.prank(proxyAdmin);
        bool success = customTokenHarness.transferFrom(sender, recipient, amount);

        assertTrue(success);
        assertEq(customTokenHarness.balanceOf(sender), 0);
        assertEq(customTokenHarness.balanceOf(recipient), amount);
    }

    function test_erc20_approve_success() public {
        uint256 amount = 100e18;

        vm.prank(sender);
        bool success = customTokenHarness.approve(recipient, amount);

        assertTrue(success);
        assertEq(customTokenHarness.allowance(sender, recipient), amount);
    }

    function test_erc20_permit_success() public {
        uint256 value = 100e18;
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = customTokenHarness.nonces(sender);

        bytes32 structHash = keccak256(abi.encode(PERMIT_TYPEHASH, sender, recipient, value, nonce, deadline));

        bytes32 domainHash = customTokenHarness.DOMAIN_SEPARATOR();
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainHash, structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(senderPrivateKey, digest);

        customTokenHarness.permit(sender, recipient, value, deadline, v, r, s);

        assertEq(customTokenHarness.allowance(sender, recipient), value);
        assertEq(customTokenHarness.nonces(sender), nonce + 1);
    }

    function test_setNativeConverter_revertsWhenAlreadySet() public {
        vm.prank(owner);
        vm.expectRevert(CustomToken.NativeConverterAlreadySet.selector);
        customTokenHarness.setNativeConverter(address(0x5678));
    }

    function test_setNativeConverter_success() public {
        // Deploy a new CustomToken instance for this test
        vm.revertToState(stateBeforeInitialize);

        address newCustomTokenImpl = address(new TestHarnessCustomToken());
        bytes memory customTokenInitData = abi.encodeCall(
            TestHarnessCustomToken.reinitialize2, (owner, customTokenDecimals, address(mockAgglayerBridge), address(0))
        );
        bytes memory customTokenUpgradeData =
            abi.encodeCall(ITransparentUpgradeableProxy.upgradeToAndCall, (newCustomTokenImpl, customTokenInitData));
        vm.prank(_getProxyAdmin(address(existingCustomTokenProxy)));
        (address(existingCustomTokenProxy).call(customTokenUpgradeData));

        TestHarnessCustomToken customTokenInstance = TestHarnessCustomToken(address(existingCustomTokenProxy));

        // Set native converter
        address newNativeConverter = address(0x5678);
        vm.prank(owner);
        customTokenInstance.setNativeConverter(newNativeConverter);

        assertEq(customTokenInstance.nativeConverter(), newNativeConverter);
    }
}
