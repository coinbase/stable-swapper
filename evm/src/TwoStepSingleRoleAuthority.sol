// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {SingleRoleAuthority} from "./SingleRoleAuthority.sol";

/// @title TwoStepSingleRoleAuthority
/// @notice Extends SingleRoleAuthority with 2-step role transfer functionality
/// @dev Adds propose/accept/cancel pattern for safer role transfers
/// @author Coinbase
abstract contract TwoStepSingleRoleAuthority is SingleRoleAuthority {
    /// @dev Mapping from role identifier to pending authority in 2-step transfer process
    mapping(bytes32 => address) private _pendingAuthorities;

    /// @notice Emitted when a transfer of an authority role is proposed
    ///
    /// @param role The role identifier being transferred
    /// @param currentAuthority Address of the current authority proposing the transfer
    /// @param pendingAuthority Address that will receive authority if they accept
    event AuthorityTransferProposed(
        bytes32 indexed role, address indexed currentAuthority, address indexed pendingAuthority
    );

    /// @notice Emitted when an authority role is transferred to a new address
    ///
    /// @param role The role identifier that was transferred
    /// @param previousAuthority Address of the previous authority
    /// @param newAuthority Address of the new authority
    event AuthorityTransferred(bytes32 indexed role, address indexed previousAuthority, address indexed newAuthority);

    /// @notice Emitted when a pending authority transfer is cancelled
    ///
    /// @param role The role identifier for which the transfer was cancelled
    /// @param cancelledAuthority Address of the pending authority that was cancelled
    event AuthorityTransferCancelled(bytes32 indexed role, address indexed cancelledAuthority);

    error InvalidAddress();
    error NoPendingAuthorityTransfer();
    error NotPendingAuthority();
    error PendingAuthorityAlreadySet();

    /// @notice Proposes a transfer of an authority role to a new address (step 1 of 2)
    /// @dev The new authority must call acceptAuthority() to complete the transfer
    ///
    /// @param role The role identifier to transfer (e.g., UPGRADE_AUTHORITY, OPERATIONS_AUTHORITY, PAUSE_AUTHORITY)
    /// @param newAuthority New address to receive the authority role
    function proposeAuthorityTransfer(bytes32 role, address newAuthority) external virtual onlyRole(role) {
        if (newAuthority == address(0)) revert InvalidAddress();
        if (_pendingAuthorities[role] != address(0)) revert PendingAuthorityAlreadySet();
        _pendingAuthorities[role] = newAuthority;
        emit AuthorityTransferProposed(role, msg.sender, newAuthority);
    }

    /// @notice Accepts an authority role transfer (step 2 of 2)
    /// @dev Can only be called by the pending authority for the specified role
    ///
    /// @param role The role identifier to accept (e.g., UPGRADE_AUTHORITY, OPERATIONS_AUTHORITY, PAUSE_AUTHORITY)
    function acceptAuthority(bytes32 role) external virtual {
        address pendingAuthority = _pendingAuthorities[role];
        if (pendingAuthority == address(0)) revert NoPendingAuthorityTransfer();
        if (msg.sender != pendingAuthority) revert NotPendingAuthority();

        address previousAuthority = getRoleHolder(role);

        // Clear pending state first (CEI pattern)
        delete _pendingAuthorities[role];

        // Transfer role (automatically revokes from previous holder via _grantRole)
        _grantRole(role, msg.sender);

        emit AuthorityTransferred(role, previousAuthority, msg.sender);
    }

    /// @notice Cancels a pending authority transfer
    /// @dev Can only be called by the current authority for the specified role
    ///
    /// @param role The role identifier for which to cancel the pending transfer
    function cancelAuthorityTransfer(bytes32 role) external virtual onlyRole(role) {
        address pendingAuthority = _pendingAuthorities[role];
        if (pendingAuthority == address(0)) revert NoPendingAuthorityTransfer();
        delete _pendingAuthorities[role];
        emit AuthorityTransferCancelled(role, pendingAuthority);
    }

    /// @notice Gets the pending authority for a specific role
    ///
    /// @param role The role identifier to query
    ///
    /// @return The address of the pending authority, or address(0) if none
    function getPendingAuthority(bytes32 role) external view returns (address) {
        return _pendingAuthorities[role];
    }

    /// @dev This empty reserved space is put in place to allow future versions to add new
    /// variables without shifting down storage in the inheritance chain.
    uint256[49] private __gap;
}

