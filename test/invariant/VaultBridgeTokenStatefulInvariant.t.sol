// SPDX-License-Identifier: LicenseRef-PolygonLabs-Source-Available
pragma solidity 0.8.29;

import {
    VaultBridgeTokenTestBase,
    TestHarnessVaultBridgeToken
} from "test/base/primary-chain/VaultBridgeTokenTestBase.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @dev Stateful action driver for the primary-chain vault.  The handler is
/// the user account, so every action observes the state left by prior actions.
contract VaultBridgeTokenHandler {
    TestHarnessVaultBridgeToken internal immutable vault;
    IERC20 internal immutable underlying;
    address internal immutable recipient;

    constructor(TestHarnessVaultBridgeToken vault_, IERC20 underlying_, address recipient_) {
        vault = vault_;
        underlying = underlying_;
        recipient = recipient_;
        underlying_.approve(address(vault_), type(uint256).max);
    }

    function actionDeposit(uint256 entropy) public {
        uint256 balance = underlying.balanceOf(address(this));
        if (balance == 0) return;
        uint256 limit = balance < 1e18 ? balance : 1e18;
        uint256 assets = (entropy % limit) + 1;
        try vault.deposit(assets, address(this)) {} catch {}
    }

    function actionMint(uint256 entropy) public {
        uint256 balance = underlying.balanceOf(address(this));
        if (balance == 0) return;
        uint256 shares = (entropy % 1e18) + 1;
        uint256 requiredAssets = vault.previewMint(shares);
        if (requiredAssets > balance) return;
        try vault.mint(shares, address(this)) {} catch {}
    }

    function actionRedeem(uint256 entropy) public {
        uint256 maxShares = vault.maxRedeem(address(this));
        if (maxShares == 0) return;
        uint256 shares = (entropy % maxShares) + 1;
        try vault.redeem(shares, address(this), address(this)) {} catch {}
    }

    function actionWithdraw(uint256 entropy) public {
        uint256 maxAssets = vault.maxWithdraw(address(this));
        if (maxAssets == 0) return;
        uint256 assets = (entropy % maxAssets) + 1;
        try vault.withdraw(assets, address(this), address(this)) {} catch {}
    }

    function actionRoundTrip(uint256 entropy) external {
        actionDeposit(entropy);
        uint256 maxShares = vault.maxRedeem(address(this));
        if (maxShares == 0) return;
        uint256 shares = (entropy % maxShares) + 1;
        try vault.redeem(shares, address(this), address(this)) {} catch {}
    }

    function actionTransfer(uint256 entropy) external {
        uint256 balance = vault.balanceOf(address(this));
        if (balance == 0) return;
        uint256 shares = (entropy % balance) + 1;
        try vault.transfer(recipient, shares) {} catch {}
    }

    function actionInvalid(uint256 entropy) external {
        uint256 supplyBefore = vault.totalSupply();
        uint256 assetsBefore = vault.totalAssets();
        try vault.deposit(0, address(0)) {} catch {}
        require(vault.totalSupply() == supplyBefore, "invalid deposit changed supply");
        require(vault.totalAssets() == assetsBefore, "invalid deposit changed assets");
        entropy;
    }

    function actionExtreme() external {
        try vault.deposit(type(uint256).max, address(this)) {} catch {}
        try vault.mint(type(uint256).max, address(this)) {} catch {}
        try vault.redeem(type(uint256).max, address(this), address(this)) {} catch {}
    }
}

/// @title VaultBridgeToken stateful invariants
/// @notice Exercises deposit/mint/withdraw/redeem and transfer transitions on
/// local mocks only.  No fork or live bridge is used.
contract VaultBridgeTokenStatefulInvariant is VaultBridgeTokenTestBase {
    VaultBridgeTokenHandler internal handler;

    function setUp() public {
        deployVaultBridgeTokenInfrastructure();
        handler = new VaultBridgeTokenHandler(
            vbToken, IERC20(underlyingToken), recipient
        );
        deal(underlyingToken, address(handler), 1e27);
        targetContract(address(handler));
    }

    function testFuzz_statefulVaultFlow(uint256 seed) public {
        for (uint256 i; i < 256; ++i) {
            uint256 entropy = uint256(keccak256(abi.encode(seed, i)));
            uint256 branch = entropy % 8;
            if (branch == 0) handler.actionDeposit(entropy);
            else if (branch == 1) handler.actionMint(entropy);
            else if (branch == 2) handler.actionRedeem(entropy);
            else if (branch == 3) handler.actionWithdraw(entropy);
            else if (branch == 4) handler.actionRoundTrip(entropy);
            else if (branch == 5) handler.actionTransfer(entropy);
            else if (branch == 6) handler.actionInvalid(entropy);
            else handler.actionExtreme();

            _assertTechnicalInvariants();
            _assertBusinessInvariants();
        }
    }

    function _assertTechnicalInvariants() internal view {
        assertLe(vbToken.reservedAssets(), vbToken.totalAssets());
        assertLe(vbToken.balanceOf(address(handler)), vbToken.totalSupply());
        assertLe(vbToken.balanceOf(recipient), vbToken.totalSupply());
    }

    function _assertBusinessInvariants() internal view {
        assertGe(vbToken.totalAssets(), vbToken.totalSupply());
        assertEq(
            vbToken.totalSupply(),
            vbToken.balanceOf(address(handler)) + vbToken.balanceOf(recipient),
            "vault supply is not conserved among test actors"
        );
    }

    function invariant_reserveBounded() external view {
        assertLe(vbToken.reservedAssets(), vbToken.totalAssets());
    }

    function invariant_assetsCoverSupply() external view {
        assertGe(vbToken.totalAssets(), vbToken.totalSupply());
    }

    function invariant_supplyConserved() external view {
        assertEq(
            vbToken.totalSupply(),
            vbToken.balanceOf(address(handler)) + vbToken.balanceOf(recipient)
        );
    }

    function invariant_handlerBalanceBounded() external view {
        assertLe(vbToken.balanceOf(address(handler)), vbToken.totalSupply());
    }
}
