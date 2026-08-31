// SPDX-License-Identifier: LicenseRef-PolygonLabs-Source-Available
pragma solidity 0.8.29;

import {MigrationManagerTestBase} from "test/base/primary-chain/MigrationManagerTestBase.sol";
import {MigrationManager} from "src/primary-chain/MigrationManager.sol";
import {MockAgglayerBridge} from "test/utils/mocks/MockAgglayerBridge.sol";
import {MockVbToken} from "test/utils/mocks/MockVbToken.sol";
import {MockWETH} from "test/utils/mocks/MockWETH.sol";

/// @dev Stateful driver for MigrationManager.  The bridge mock forwards calls
/// so the target sees the bridge as msg.sender, just like production.
contract MigrationManagerHandler {
    MigrationManager internal immutable manager;
    MockAgglayerBridge internal immutable bridge;
    MockVbToken internal immutable vbToken;
    MockWETH internal immutable wrappedGasToken;
    address internal immutable nativeConverter;
    uint32 internal immutable originNetwork;

    constructor(
        MigrationManager manager_,
        MockAgglayerBridge bridge_,
        MockVbToken vbToken_,
        MockWETH wrappedGasToken_,
        address nativeConverter_,
        uint32 originNetwork_
    ) {
        manager = manager_;
        bridge = bridge_;
        vbToken = vbToken_;
        wrappedGasToken = wrappedGasToken_;
        nativeConverter = nativeConverter_;
        originNetwork = originNetwork_;
    }

    function _message(MigrationManager.CrossChainInstruction instruction, uint256 shares, uint256 assets)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encode(instruction, abi.encode(shares, assets));
    }

    function _callback(address origin, uint32 network, bytes memory data)
        internal
        returns (bool success, bytes memory returndata)
    {
        return bridge.execute(
            address(manager),
            abi.encodeCall(manager.onMessageReceived, (origin, network, data))
        );
    }

    function actionComplete(uint256 entropy) public {
        uint256 shares = (entropy % 1e18) + 1;
        uint256 assets = ((entropy >> 64) % 1e18) + 1;
        (bool success,) = _callback(
            nativeConverter,
            originNetwork,
            _message(MigrationManager.CrossChainInstruction._0_COMPLETE_MIGRATION, shares, assets)
        );
        require(success, "valid migration callback failed");
    }

    function actionWrapGas(uint256 entropy) public {
        uint256 assets = (entropy % 1e15) + 1;
        (bool success,) = bridge.execute{value: assets}(
            address(manager),
            abi.encodeCall(
                manager.onMessageReceived,
                (
                    nativeConverter,
                    originNetwork,
                    _message(MigrationManager.CrossChainInstruction._1_WRAP_GAS_TOKEN_AND_COMPLETE_MIGRATION, assets, assets)
                )
            )
        );
        require(success, "wrapped-gas migration callback failed");
    }

    function actionInvalidOrigin(uint256 entropy) external {
        address origin = address(uint160(entropy));
        if (origin == address(0) || origin == nativeConverter) origin = address(0xBEEF);
        (bool success,) = _callback(
            origin,
            originNetwork,
            _message(MigrationManager.CrossChainInstruction._0_COMPLETE_MIGRATION, 1, 1)
        );
        require(!success, "unknown converter was accepted");
    }

    function actionInvalidNetwork(uint256 entropy) external {
        uint32 network = uint32(entropy);
        if (network == originNetwork) network++;
        (bool success,) = _callback(
            nativeConverter,
            network,
            _message(MigrationManager.CrossChainInstruction._0_COMPLETE_MIGRATION, 1, 1)
        );
        require(!success, "unknown network was accepted");
    }

    function actionMalformed() external {
        (bool success,) = _callback(nativeConverter, originNetwork, hex"1234");
        require(!success, "malformed callback was accepted");
    }

    function actionExtreme() external {
        (bool success,) = _callback(
            nativeConverter,
            originNetwork,
            _message(
                MigrationManager.CrossChainInstruction._0_COMPLETE_MIGRATION,
                type(uint256).max,
                type(uint256).max
            )
        );
        require(success, "maximum-width migration callback failed");
    }

    function wrappedBalance() external view returns (uint256) {
        return wrappedGasToken.balanceOf(address(manager));
    }

    function configuredVbToken() external view returns (address) {
        return address(vbToken);
    }
}

/// @title MigrationManager stateful invariants
/// @notice Exercises valid callbacks, wrapped gas-token callbacks and malformed
/// or unauthorized messages against local mocks only.
contract MigrationManagerStatefulInvariant is MigrationManagerTestBase {
    MigrationManagerHandler internal handler;

    function setUp() public {
        deployMigrationManagerInfrastructure();

        // Make the configured vbToken compatible with the wrapped-gas branch.
        vbToken.setUnderlyingToken(address(wrappedGasToken));
        uint32[] memory ids = new uint32[](1);
        ids[0] = NETWORK_ID_L2;
        address[] memory converters = new address[](1);
        converters[0] = nativeConverter;
        vm.prank(owner);
        migrationManager.configureNativeConverters(ids, converters, payable(address(vbToken)));

        handler = new MigrationManagerHandler(
            migrationManager,
            MockAgglayerBridge(agglayerBridge),
            vbToken,
            wrappedGasToken,
            nativeConverter,
            NETWORK_ID_L2
        );
        vm.deal(address(handler), 100 ether);
        targetContract(address(handler));
    }

    function testFuzz_statefulMigrationFlow(uint256 seed) public {
        for (uint256 i; i < 256; ++i) {
            uint256 entropy = uint256(keccak256(abi.encode(seed, i)));
            uint256 branch = entropy % 7;
            if (branch == 0) handler.actionComplete(entropy);
            else if (branch == 1) handler.actionWrapGas(entropy);
            else if (branch == 2) handler.actionInvalidOrigin(entropy);
            else if (branch == 3) handler.actionInvalidNetwork(entropy);
            else if (branch == 4) handler.actionMalformed();
            else handler.actionExtreme();

            _assertTechnicalInvariants();
            _assertBusinessInvariants();
        }
    }

    function _assertTechnicalInvariants() internal view {
        assertEq(address(migrationManager.agglayerBridge()), agglayerBridge);
        MigrationManager.TokenPair memory pair =
            migrationManager.nativeConvertersConfiguration(NETWORK_ID_L2, nativeConverter);
        assertEq(address(pair.vbToken), address(vbToken));
        assertEq(address(pair.underlyingToken), address(wrappedGasToken));
    }

    function _assertBusinessInvariants() internal view {
        uint256 calls = vbToken.completeMigrationCalls();
        if (calls > 0) {
            assertEq(vbToken.lastOriginNetwork(), NETWORK_ID_L2);
        }
        assertGe(handler.wrappedBalance(), 0);
    }

    function invariant_configurationIsStable() external view {
        MigrationManager.TokenPair memory pair =
            migrationManager.nativeConvertersConfiguration(NETWORK_ID_L2, nativeConverter);
        assertEq(address(pair.vbToken), address(vbToken));
        assertEq(address(pair.underlyingToken), address(wrappedGasToken));
    }

    function invariant_bridgeOnlyDispatchesConfiguredPair() external view {
        assertEq(address(migrationManager.agglayerBridge()), agglayerBridge);
    }

    function invariant_completedMessagesUseConfiguredNetwork() external view {
        if (vbToken.completeMigrationCalls() > 0) {
            assertEq(vbToken.lastOriginNetwork(), NETWORK_ID_L2);
        }
    }
}
