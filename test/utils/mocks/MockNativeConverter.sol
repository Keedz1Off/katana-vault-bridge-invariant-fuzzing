// SPDX-License-Identifier: LicenseRef-PolygonLabs-Source-Available
pragma solidity ^0.8.29;

/// @dev Mock NativeConverter for testing
contract MockNativeConverter {
    uint256 public removeMigrationInProgressAmount;

    function removeMigrationInProgress(uint256 amount) external {
        removeMigrationInProgressAmount = amount;
    }

    /// @dev Test-only forwarding helper so a handler can exercise calls that
    /// must originate from the configured Native Converter address.
    function execute(address target, bytes calldata data)
        external
        returns (bool success, bytes memory returndata)
    {
        (success, returndata) = target.call(data);
    }
}
