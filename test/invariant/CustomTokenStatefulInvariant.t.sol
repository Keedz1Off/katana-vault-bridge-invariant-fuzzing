// SPDX-License-Identifier: LicenseRef-PolygonLabs-Source-Available
pragma solidity 0.8.29;

import {
    CustomTokenTestBase,
    TestHarnessCustomToken
} from "test/base/secondary-chain/CustomTokenTestBase.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @dev Small actor contracts make transferFrom execute with a distinct
/// msg.sender, so the handler can model two independent token holders.
contract CustomTokenActor {
    IERC20 internal immutable token;

    constructor(IERC20 token_) {
        token = token_;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        return token.transfer(to, amount);
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        return token.approve(spender, amount);
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        return token.transferFrom(from, to, amount);
    }
}

/// @dev Stateful action driver for the permissionless ERC-20 surface of
/// CustomToken.  Minting/burning is intentionally excluded: the base
/// CustomToken has no public mint/burn entry point; those are covered by the
/// Agglayer-specific handler in a separate file.
contract CustomTokenHandler {
    IERC20 internal immutable token;
    CustomTokenActor internal immutable actorA;
    CustomTokenActor internal immutable actorB;

    constructor(IERC20 token_, CustomTokenActor actorA_, CustomTokenActor actorB_) {
        token = token_;
        actorA = actorA_;
        actorB = actorB_;
    }

    function actionTransfer(uint256 entropy) public {
        uint256 balance = token.balanceOf(address(actorA));
        if (balance == 0) return;
        uint256 amount = (entropy % balance) + 1;
        try actorA.transfer(address(actorB), amount) {} catch {}
    }

    function actionApproveAndPull(uint256 entropy) public {
        uint256 balance = token.balanceOf(address(actorA));
        if (balance == 0) return;
        uint256 amount = (entropy % balance) + 1;
        try actorA.approve(address(actorB), amount) {
            try actorB.transferFrom(address(actorA), address(actorB), amount) {} catch {}
        } catch {}
    }

    function actionReverseTransfer(uint256 entropy) public {
        uint256 balance = token.balanceOf(address(actorB));
        if (balance == 0) return;
        uint256 amount = (entropy % balance) + 1;
        try actorB.transfer(address(actorA), amount) {} catch {}
    }

    function actionRoundTrip(uint256 entropy) external {
        actionTransfer(entropy);
        actionReverseTransfer(entropy >> 1);
    }

    function actionInvalid() external {
        uint256 supplyBefore = token.totalSupply();
        try token.transfer(address(0), 0) {} catch {}
        require(token.totalSupply() == supplyBefore, "invalid transfer changed supply");
    }

    function actionExtreme() external {
        try actorA.transfer(address(actorB), type(uint256).max) {} catch {}
        try actorB.transferFrom(address(actorA), address(actorB), type(uint256).max) {} catch {}
    }
}

/// @title CustomToken stateful invariants
/// @notice Checks balance conservation and allowance-driven transfer chains on
/// local proxy/mocks only.
contract CustomTokenStatefulInvariant is CustomTokenTestBase {
    CustomTokenHandler internal handler;
    CustomTokenActor internal actorA;
    CustomTokenActor internal actorB;
    uint256 internal constant INITIAL_SUPPLY = 1e24;

    function setUp() public {
        deployCustomTokenInfrastructure();
        actorA = new CustomTokenActor(IERC20(address(customTokenHarness)));
        actorB = new CustomTokenActor(IERC20(address(customTokenHarness)));
        handler = new CustomTokenHandler(IERC20(address(customTokenHarness)), actorA, actorB);

        // The `true` flag updates totalSupply along with the seeded balance.
        deal(address(customTokenHarness), address(actorA), INITIAL_SUPPLY, true);
        targetContract(address(handler));
    }

    function testFuzz_statefulCustomTokenFlow(uint256 seed) public {
        for (uint256 i; i < 256; ++i) {
            uint256 entropy = uint256(keccak256(abi.encode(seed, i)));
            uint256 branch = entropy % 6;
            if (branch == 0) handler.actionTransfer(entropy);
            else if (branch == 1) handler.actionApproveAndPull(entropy);
            else if (branch == 2) handler.actionReverseTransfer(entropy);
            else if (branch == 3) handler.actionRoundTrip(entropy);
            else if (branch == 4) handler.actionInvalid();
            else handler.actionExtreme();

            _assertTechnicalInvariants();
            _assertBusinessInvariants();
        }
    }

    function _assertTechnicalInvariants() internal view {
        assertEq(tokenTotalSupply(), actorABalance() + actorBBalance());
        assertLe(actorABalance(), tokenTotalSupply());
        assertLe(actorBBalance(), tokenTotalSupply());
    }

    function _assertBusinessInvariants() internal view {
        assertEq(tokenTotalSupply(), INITIAL_SUPPLY, "unexpected mint or burn");
        assertEq(tokenTotalSupply(), actorABalance() + actorBBalance(), "token balance not conserved");
    }

    function tokenTotalSupply() internal view returns (uint256) {
        return customTokenHarness.totalSupply();
    }

    function actorABalance() internal view returns (uint256) {
        return customTokenHarness.balanceOf(address(actorA));
    }

    function actorBBalance() internal view returns (uint256) {
        return customTokenHarness.balanceOf(address(actorB));
    }

    function invariant_supplyConserved() external view {
        assertEq(tokenTotalSupply(), actorABalance() + actorBBalance());
    }

    function invariant_supplyStable() external view {
        assertEq(tokenTotalSupply(), INITIAL_SUPPLY);
    }

    function invariant_actorBalancesBounded() external view {
        assertLe(actorABalance(), tokenTotalSupply());
        assertLe(actorBBalance(), tokenTotalSupply());
    }
}
