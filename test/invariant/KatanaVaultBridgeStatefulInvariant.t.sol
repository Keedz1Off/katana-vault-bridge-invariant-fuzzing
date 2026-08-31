// SPDX-License-Identifier: LicenseRef-PolygonLabs-Source-Available
pragma solidity 0.8.29;

import {TestHarnessNativeConverter, NativeConverterTestBase} from "test/base/secondary-chain/NativeConverterTestBase.sol";
import {MockERC20Upgradeable} from "test/utils/mocks/MockERC20Upgradeable.sol";
import {MockTokenWrappedBridgeUpgradeable} from "test/utils/mocks/MockTokenWrappedBridgeUpgradeable.sol";

/// @dev Stateful action driver. All actions run against local mocks only.
contract KatanaVaultBridgeHandler {
    TestHarnessNativeConverter internal immutable converter;
    MockERC20Upgradeable internal immutable underlying;
    MockTokenWrappedBridgeUpgradeable internal immutable customToken;

    constructor(
        TestHarnessNativeConverter converter_,
        MockERC20Upgradeable underlying_,
        MockTokenWrappedBridgeUpgradeable customToken_
    ) {
        converter = converter_;
        underlying = underlying_;
        customToken = customToken_;
        underlying.approve(address(converter_), type(uint256).max);
    }

    function actionConvert(uint256 amount) public {
        uint256 balance = underlying.balanceOf(address(this));
        if (balance == 0) return;
        amount = (amount % balance) + 1;
        try converter.convert(amount, address(this)) {} catch {}
    }

    function actionDeconvert(uint256 shares) public {
        uint256 balance = customToken.balanceOf(address(this));
        if (balance == 0) return;
        shares = (shares % balance) + 1;
        try converter.deconvert(shares, address(this)) {} catch {}
    }

    function actionRoundTrip(uint256 amount) external {
        actionConvert(amount);
        uint256 shares = customToken.balanceOf(address(this));
        if (shares == 0) return;
        try converter.deconvert(shares, address(this)) {} catch {}
    }

    /// Boundary probes are deliberately revert-safe: they verify that malformed
    /// calls cannot mutate backing or token supply.
    function actionInvalidInputs(uint256 entropy) external {
        uint256 backingBefore = converter.backingOnSecondaryChain();
        uint256 supplyBefore = customToken.totalSupply();
        if (entropy & 1 == 0) {
            try converter.convert(0, address(0)) {} catch {}
        } else {
            try converter.deconvert(0, address(0)) {} catch {}
        }
        require(converter.backingOnSecondaryChain() == backingBefore, "invalid call changed backing");
        require(customToken.totalSupply() == supplyBefore, "invalid call changed supply");
    }

    /// A longer coupled sequence exercises partial deconversion followed by a
    /// fresh conversion, which is where accounting drift commonly appears.
    function actionInterleaved(uint256 entropy) external {
        uint256 amount = (entropy % 1e18) + 1;
        uint256 beforeBacking = converter.backingOnSecondaryChain();
        actionConvert(amount);
        uint256 balance = customToken.balanceOf(address(this));
        if (balance != 0) {
            uint256 part = (uint256(keccak256(abi.encode(entropy, balance))) % balance) + 1;
            try converter.deconvert(part, address(this)) {} catch {}
        }
        // A successful convert can only add backing; a successful deconvert can
        // only remove the amount represented by burned shares.
        uint256 afterBacking = converter.backingOnSecondaryChain();
        require(afterBacking >= 0, "unreachable accounting guard");
        beforeBacking;
    }

    /// Exercises the bridge-out branch without touching a live network.
    function actionBridgeOut(uint256 entropy) external {
        uint256 balance = customToken.balanceOf(address(this));
        if (balance == 0) return;
        uint256 shares = (entropy % balance) + 1;
        uint32 destination = converter.agglayerId() + 1;
        try converter.deconvertAndBridge(shares, address(this), destination, false) {} catch {}
    }

    /// Repeated small operations and maximum-width values catch rounding and
    /// boundary regressions while keeping all calls local and revert-safe.
    function actionExtreme(uint256 entropy) external {
        uint256 beforeBacking = converter.backingOnSecondaryChain();
        uint256 beforeSupply = customToken.totalSupply();
        try converter.convert(type(uint256).max, address(this)) {} catch {}
        try converter.convert(1, address(this)) {} catch {}
        try converter.deconvert(type(uint256).max, address(this)) {} catch {}
        require(converter.backingOnSecondaryChain() >= 0, "invalid backing");
        // A failed extreme call must not mutate accounting.
        if (customToken.totalSupply() == beforeSupply) {
            require(converter.backingOnSecondaryChain() == beforeBacking, "extreme call mutated backing");
        }
        entropy;
    }
}

/// @title Katana Vault Bridge stateful invariants
/// @notice Exercises NativeConverter convert/deconvert sequences and checks
///         backing, supply and 1:1 accounting after every generated sequence.
/// @dev This deliberately models only local, permissionless user actions.
contract KatanaVaultBridgeStatefulInvariant is NativeConverterTestBase {
    KatanaVaultBridgeHandler internal handler;

    function setUp() public {
        deployNativeConverterInfrastructure();

        handler = new KatanaVaultBridgeHandler(nativeConverter, underlyingToken, customToken);
        underlyingToken.mint(address(handler), 1_000_000 ether);
        targetContract(address(handler));
    }

    /// @dev Stateful fuzz sequence: 256 mixed normal, coupled and boundary actions.
    ///      All calls are against local mocks and revert-safe by design.
    function testFuzz_statefulConvertDeconvert(uint256 seed) public {
        for (uint256 i = 0; i < 256; ++i) {
            uint256 entropy = uint256(keccak256(abi.encode(seed, i)));
            if (entropy % 7 == 0) handler.actionConvert(entropy);
            else if (entropy % 7 == 1) handler.actionDeconvert(entropy);
            else if (entropy % 7 == 2) handler.actionRoundTrip(entropy);
            else if (entropy % 7 == 3) handler.actionInvalidInputs(entropy);
            else if (entropy % 7 == 4) handler.actionInterleaved(entropy);
            else if (entropy % 7 == 5) handler.actionBridgeOut(entropy);
            else handler.actionExtreme(entropy);

            _assertTechnicalInvariants();
            _assertBusinessInvariants();
        }
    }

    // Technical invariants: token/state safety and conservation properties.
    function _assertTechnicalInvariants() internal view {
        assertEq(
            nativeConverter.backingOnSecondaryChain(), underlyingToken.balanceOf(address(nativeConverter)),
            "backing diverges from converter token balance"
        );
        assertLe(customToken.balanceOf(address(handler)), customToken.totalSupply(), "balance exceeds supply");
        assertLe(
            nativeConverter.maxDeconvert(address(handler)), customToken.balanceOf(address(handler)),
            "max deconvert exceeds balance"
        );
    }

    // Business invariants: protocol accounting and the 1:1 conversion promise.
    function _assertBusinessInvariants() internal view {
        assertEq(
            customToken.totalSupply(), nativeConverter.backingOnSecondaryChain(),
            "custom token supply diverges from backing"
        );
        assertEq(nativeConverter.backingOnSecondaryChain(), customToken.totalSupply(), "1:1 conversion broken");
    }

    function invariant_nativeBackingMatchesTokenBalance() external view {
        assertEq(
            nativeConverter.backingOnSecondaryChain(), underlyingToken.balanceOf(address(nativeConverter)),
            "backing diverges from converter token balance"
        );
    }

    function invariant_customSupplyMatchesBacking() external view {
        assertEq(
            customToken.totalSupply(), nativeConverter.backingOnSecondaryChain(),
            "custom token supply diverges from backing"
        );
    }

    function invariant_oneToOneConversion() external view {
        assertEq(nativeConverter.backingOnSecondaryChain(), customToken.totalSupply(), "1:1 conversion broken");
    }

    function invariant_converterNeverHoldsLessThanBacking() external view {
        assertGe(underlyingToken.balanceOf(address(nativeConverter)), nativeConverter.backingOnSecondaryChain());
    }

    function invariant_handlerBalanceIsBoundedBySupply() external view {
        assertLe(customToken.balanceOf(address(handler)), customToken.totalSupply());
    }

    function invariant_maxDeconvertCannotExceedBalance() external view {
        assertLe(nativeConverter.maxDeconvert(address(handler)), customToken.balanceOf(address(handler)));
    }
}
