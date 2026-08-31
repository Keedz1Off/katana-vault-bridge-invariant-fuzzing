// SPDX-License-Identifier: LicenseRef-PolygonLabs-Source-Available
pragma solidity ^0.8.29;

// Test Base
import {
    GenericCustomTokenAgglayerTestBase,
    TransparentUpgradeableProxy,
    ITransparentUpgradeableProxy
} from "test/base/secondary-chain/GenericCustomTokenAgglayerTestBase.sol";

// Core contracts
import {
    GenericCustomTokenAgglayer,
    CustomTokenAgglayer
} from "src/secondary-chain/agglayer/GenericCustomTokenAgglayer.sol";
import {CustomToken} from "src/secondary-chain/CustomToken.sol";
import {NativeConverter} from "src/secondary-chain/NativeConverter.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {InitializationCounterUpgradeable} from "src/etc/InitializationCounterUpgradeable.sol";

/// @dev GenericCustomTokenAgglayer tests
contract GenericCustomTokenAgglayerTest is GenericCustomTokenAgglayerTestBase {
    function setUp() public virtual {
        deployGenericCustomTokenAgglayerInfrastructure();
    }

    function testFuzz_statefulMintTransferBurn(uint256 minted, uint256 moved, uint256 burned) public {
        minted = bound(minted, 3, 1e24);
        moved = bound(moved, 1, minted - 1);
        burned = bound(burned, 1, moved);

        vm.prank(address(mockAgglayerBridge));
        genericCustomTokenAgglayer.mint(recipient, minted);

        vm.prank(recipient);
        genericCustomTokenAgglayer.transfer(sender, moved);

        vm.prank(address(mockAgglayerBridge));
        genericCustomTokenAgglayer.burn(sender, burned);

        assertEq(genericCustomTokenAgglayer.totalSupply(), minted - burned);
        assertEq(genericCustomTokenAgglayer.balanceOf(recipient), minted - moved);
        assertEq(genericCustomTokenAgglayer.balanceOf(sender), moved - burned);
    }

    /// Stateless fuzz: every case starts from a fresh setUp and checks bridge mint.
    function testFuzz_bridgeMint(uint256 amount) public {
        amount = bound(amount, 1, 1e24);
        vm.prank(address(mockAgglayerBridge));
        genericCustomTokenAgglayer.mint(recipient, amount);

        assertEq(genericCustomTokenAgglayer.balanceOf(recipient), amount);
        assertEq(genericCustomTokenAgglayer.totalSupply(), amount);
    }

    /// Stateless fuzz: seed one balance, then check a single bridge burn.
    function testFuzz_bridgeBurn(uint256 minted, uint256 amount) public {
        minted = bound(minted, 1, 1e24);
        amount = bound(amount, 1, minted);

        vm.prank(address(mockAgglayerBridge));
        genericCustomTokenAgglayer.mint(sender, minted);
        vm.prank(address(mockAgglayerBridge));
        genericCustomTokenAgglayer.burn(sender, amount);

        assertEq(genericCustomTokenAgglayer.balanceOf(sender), minted - amount);
        assertEq(genericCustomTokenAgglayer.totalSupply(), minted - amount);
    }

    function test_mint_success_fromBridge() public {
        uint256 amount = 1000e18;

        vm.prank(address(mockAgglayerBridge));
        genericCustomTokenAgglayer.mint(recipient, amount);

        assertEq(genericCustomTokenAgglayer.balanceOf(recipient), amount);
        assertEq(genericCustomTokenAgglayer.totalSupply(), amount);
    }

    function test_mint_success_fromNativeConverter() public {
        uint256 amount = 1000e18;

        vm.prank(address(mockNativeConverter));
        genericCustomTokenAgglayer.mint(recipient, amount);

        assertEq(genericCustomTokenAgglayer.balanceOf(recipient), amount);
        assertEq(genericCustomTokenAgglayer.totalSupply(), amount);
    }

    function test_mint_success_toAddressZero_emitsTransfer() public {
        uint256 amount = 1000e18;

        vm.expectEmit(true, true, true, true);
        emit CustomToken.AlreadyMinted(amount);

        vm.prank(address(mockAgglayerBridge));
        genericCustomTokenAgglayer.mint(address(0), amount);

        assertEq(genericCustomTokenAgglayer.totalSupply(), 0);
        assertEq(mockNativeConverter.removeMigrationInProgressAmount(), amount);
    }

    function test_mint_revertsWithUnauthorized() public {
        uint256 amount = 1000e18;

        vm.expectRevert(CustomToken.Unauthorized.selector);
        vm.prank(makeAddr("unauthorized"));
        genericCustomTokenAgglayer.mint(recipient, amount);
    }

    function test_mint_revertsWhenPaused() public {
        uint256 amount = 1000e18;

        vm.prank(owner);
        genericCustomTokenAgglayer.pause();

        vm.expectRevert();
        vm.prank(address(mockAgglayerBridge));
        genericCustomTokenAgglayer.mint(recipient, amount);
    }

    function test_burn_success_fromBridge() public {
        uint256 amount = 1000e18;

        // First mint tokens
        vm.prank(address(mockAgglayerBridge));
        genericCustomTokenAgglayer.mint(sender, amount);

        assertEq(genericCustomTokenAgglayer.balanceOf(sender), amount);

        // Then burn them
        vm.prank(address(mockAgglayerBridge));
        genericCustomTokenAgglayer.burn(sender, amount);

        assertEq(genericCustomTokenAgglayer.balanceOf(sender), 0);
        assertEq(genericCustomTokenAgglayer.totalSupply(), 0);
    }

    function test_burn_success_fromNativeConverter() public {
        uint256 amount = 1000e18;

        // First mint tokens
        vm.prank(address(mockNativeConverter));
        genericCustomTokenAgglayer.mint(sender, amount);

        assertEq(genericCustomTokenAgglayer.balanceOf(sender), amount);

        // Then burn them
        vm.prank(address(mockNativeConverter));
        genericCustomTokenAgglayer.burn(sender, amount);

        assertEq(genericCustomTokenAgglayer.balanceOf(sender), 0);
        assertEq(genericCustomTokenAgglayer.totalSupply(), 0);
    }

    function test_burn_revertsWithUnauthorized() public {
        uint256 amount = 1000e18;

        // First mint tokens
        vm.prank(address(mockAgglayerBridge));
        genericCustomTokenAgglayer.mint(sender, amount);

        vm.expectRevert(CustomToken.Unauthorized.selector);
        vm.prank(makeAddr("unauthorized"));
        genericCustomTokenAgglayer.burn(sender, amount);
    }

    function test_burn_revertsWhenPaused() public {
        uint256 amount = 1000e18;

        // First mint tokens
        vm.prank(address(mockAgglayerBridge));
        genericCustomTokenAgglayer.mint(sender, amount);

        vm.prank(owner);
        genericCustomTokenAgglayer.pause();

        vm.expectRevert();
        vm.prank(address(mockAgglayerBridge));
        genericCustomTokenAgglayer.burn(sender, amount);
    }

    function test_burn_revertsWithInsufficientBalance() public {
        uint256 mintAmount = 500e18;
        uint256 burnAmount = 1000e18;

        // Mint less than we try to burn
        vm.prank(address(mockAgglayerBridge));
        genericCustomTokenAgglayer.mint(sender, mintAmount);

        vm.expectRevert();
        vm.prank(address(mockAgglayerBridge));
        genericCustomTokenAgglayer.burn(sender, burnAmount);
    }

    function test_mintAndBurn_multipleUsers() public {
        address user1 = makeAddr("user1");
        address user2 = makeAddr("user2");
        uint256 amount1 = 1000e18;
        uint256 amount2 = 2000e18;

        // Mint to both users
        vm.prank(address(mockAgglayerBridge));
        genericCustomTokenAgglayer.mint(user1, amount1);

        vm.prank(address(mockNativeConverter));
        genericCustomTokenAgglayer.mint(user2, amount2);

        assertEq(genericCustomTokenAgglayer.balanceOf(user1), amount1);
        assertEq(genericCustomTokenAgglayer.balanceOf(user2), amount2);
        assertEq(genericCustomTokenAgglayer.totalSupply(), amount1 + amount2);

        // Burn from user1
        vm.prank(address(mockAgglayerBridge));
        genericCustomTokenAgglayer.burn(user1, amount1);

        assertEq(genericCustomTokenAgglayer.balanceOf(user1), 0);
        assertEq(genericCustomTokenAgglayer.balanceOf(user2), amount2);
        assertEq(genericCustomTokenAgglayer.totalSupply(), amount2);
    }
}
