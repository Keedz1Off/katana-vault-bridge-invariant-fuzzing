// SPDX-License-Identifier: LicenseRef-PolygonLabs-Source-Available
pragma solidity 0.8.29;

import {
    GenericCustomTokenAgglayerTestBase,
    GenericCustomTokenAgglayer
} from "test/base/secondary-chain/GenericCustomTokenAgglayerTestBase.sol";
import {MockAgglayerBridge} from "test/utils/mocks/MockAgglayerBridge.sol";
import {MockNativeConverter} from "test/utils/mocks/MockNativeConverter.sol";

/// @dev Stateful driver for the Agglayer custom-token permissions and ERC-20
/// transitions.  Bridge/native-converter calls are forwarded by their mocks so
/// the token observes the correct msg.sender.
contract GenericCustomTokenAgglayerHandler {
    GenericCustomTokenAgglayer internal immutable token;
    MockAgglayerBridge internal immutable bridge;
    MockNativeConverter internal immutable nativeConverter;
    address internal immutable recipient;

    constructor(
        GenericCustomTokenAgglayer token_,
        MockAgglayerBridge bridge_,
        MockNativeConverter nativeConverter_,
        address recipient_
    ) {
        token = token_;
        bridge = bridge_;
        nativeConverter = nativeConverter_;
        recipient = recipient_;
    }

    function _bridgeMint(address account, uint256 amount) internal returns (bool success) {
        (success,) = bridge.execute(
            address(token),
            abi.encodeCall(token.mint, (account, amount))
        );
    }

    function _nativeMint(address account, uint256 amount) internal returns (bool success) {
        (success,) = nativeConverter.execute(
            address(token),
            abi.encodeCall(token.mint, (account, amount))
        );
    }

    function _bridgeBurn(address account, uint256 amount) internal returns (bool success) {
        (success,) = bridge.execute(
            address(token),
            abi.encodeCall(token.burn, (account, amount))
        );
    }

    function _nativeBurn(address account, uint256 amount) internal returns (bool success) {
        (success,) = nativeConverter.execute(
            address(token),
            abi.encodeCall(token.burn, (account, amount))
        );
    }

    function actionBridgeMint(uint256 entropy) public {
        uint256 amount = (entropy % 1e18) + 1;
        require(_bridgeMint(address(this), amount), "bridge mint failed");
    }

    function actionNativeMint(uint256 entropy) public {
        uint256 amount = (entropy % 1e18) + 1;
        require(_nativeMint(address(this), amount), "native converter mint failed");
    }

    function actionTransfer(uint256 entropy) public {
        uint256 balance = token.balanceOf(address(this));
        if (balance == 0) return;
        uint256 amount = (entropy % balance) + 1;
        require(token.transfer(recipient, amount), "transfer failed");
    }

    function actionBridgeBurn(uint256 entropy) public {
        uint256 handlerBalance = token.balanceOf(address(this));
        uint256 recipientBalance = token.balanceOf(recipient);
        address holder = (entropy & 1) == 0 ? address(this) : recipient;
        uint256 balance = holder == address(this) ? handlerBalance : recipientBalance;
        if (balance == 0) return;
        uint256 amount = (entropy % balance) + 1;
        require(_bridgeBurn(holder, amount), "bridge burn failed");
    }

    function actionNativeBurn(uint256 entropy) public {
        uint256 handlerBalance = token.balanceOf(address(this));
        uint256 recipientBalance = token.balanceOf(recipient);
        address holder = (entropy & 1) == 0 ? address(this) : recipient;
        uint256 balance = holder == address(this) ? handlerBalance : recipientBalance;
        if (balance == 0) return;
        uint256 amount = (entropy % balance) + 1;
        require(_nativeBurn(holder, amount), "native converter burn failed");
    }

    function actionRoundTrip(uint256 entropy) external {
        uint256 amount = (entropy % 1e18) + 1;
        require(_bridgeMint(address(this), amount), "round-trip mint failed");
        uint256 balance = token.balanceOf(address(this));
        uint256 moved = (entropy % balance) + 1;
        require(token.transfer(recipient, moved), "round-trip transfer failed");
        require(_bridgeBurn(recipient, moved), "round-trip burn failed");
    }

    function actionAlreadyMinted(uint256 entropy) external {
        uint256 amount = (entropy % 1e18) + 1;
        (bool success,) = bridge.execute(
            address(token),
            abi.encodeCall(token.mint, (address(0), amount))
        );
        require(success, "already-minted branch failed");
    }

    function actionInvalid() external {
        uint256 supplyBefore = token.totalSupply();
        (bool success,) = address(token).call(abi.encodeCall(token.mint, (address(this), 1)));
        require(!success, "unauthorized mint succeeded");
        require(token.totalSupply() == supplyBefore, "invalid mint changed supply");
    }

    function actionExtreme() external {
        (bool ignored,) = bridge.execute(
            address(token),
            abi.encodeCall(token.mint, (address(this), type(uint256).max))
        );
        (ignored,) = bridge.execute(
            address(token),
            abi.encodeCall(token.burn, (address(this), type(uint256).max))
        );
    }
}

/// @title GenericCustomTokenAgglayer stateful invariants
/// @notice Checks bridge/native-converter authorization, zero-address migration
/// handling and ERC-20 supply conservation using local mocks only.
contract GenericCustomTokenAgglayerStatefulInvariant is GenericCustomTokenAgglayerTestBase {
    GenericCustomTokenAgglayerHandler internal handler;

    function setUp() public {
        deployGenericCustomTokenAgglayerInfrastructure();
        handler = new GenericCustomTokenAgglayerHandler(
            genericCustomTokenAgglayer,
            mockAgglayerBridge,
            mockNativeConverter,
            recipient
        );
        targetContract(address(handler));
    }

    function testFuzz_statefulAgglayerTokenFlow(uint256 seed) public {
        for (uint256 i; i < 256; ++i) {
            uint256 entropy = uint256(keccak256(abi.encode(seed, i)));
            uint256 branch = entropy % 9;
            if (branch == 0) handler.actionBridgeMint(entropy);
            else if (branch == 1) handler.actionNativeMint(entropy);
            else if (branch == 2) handler.actionTransfer(entropy);
            else if (branch == 3) handler.actionBridgeBurn(entropy);
            else if (branch == 4) handler.actionNativeBurn(entropy);
            else if (branch == 5) handler.actionRoundTrip(entropy);
            else if (branch == 6) handler.actionAlreadyMinted(entropy);
            else if (branch == 7) handler.actionExtreme();
            else handler.actionInvalid();

            _assertTechnicalInvariants();
            _assertBusinessInvariants();
        }
    }

    function _assertTechnicalInvariants() internal view {
        assertEq(genericCustomTokenAgglayer.bridge(), address(mockAgglayerBridge));
        assertEq(genericCustomTokenAgglayer.nativeConverter(), address(mockNativeConverter));
        assertLe(genericCustomTokenAgglayer.balanceOf(address(handler)), genericCustomTokenAgglayer.totalSupply());
        assertLe(genericCustomTokenAgglayer.balanceOf(recipient), genericCustomTokenAgglayer.totalSupply());
    }

    function _assertBusinessInvariants() internal view {
        assertEq(
            genericCustomTokenAgglayer.totalSupply(),
            genericCustomTokenAgglayer.balanceOf(address(handler))
                + genericCustomTokenAgglayer.balanceOf(recipient),
            "custom-token supply is not conserved"
        );
    }

    function invariant_supplyConserved() external view {
        assertEq(
            genericCustomTokenAgglayer.totalSupply(),
            genericCustomTokenAgglayer.balanceOf(address(handler))
                + genericCustomTokenAgglayer.balanceOf(recipient)
        );
    }

    function invariant_authoritiesRemainConfigured() external view {
        assertEq(genericCustomTokenAgglayer.bridge(), address(mockAgglayerBridge));
        assertEq(genericCustomTokenAgglayer.nativeConverter(), address(mockNativeConverter));
    }

    function invariant_balancesBoundedBySupply() external view {
        assertLe(genericCustomTokenAgglayer.balanceOf(address(handler)), genericCustomTokenAgglayer.totalSupply());
        assertLe(genericCustomTokenAgglayer.balanceOf(recipient), genericCustomTokenAgglayer.totalSupply());
    }
}
