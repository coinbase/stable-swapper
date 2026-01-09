// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/// @title SingleRoleAuthority
/// @notice A minimal access control system that enforces exactly one address per role
/// @dev Unlike AccessControl, this prevents multiple addresses from holding the same role
/// @author Coinbase
abstract contract SingleRoleAuthority is Initializable {
    /// @dev Mapping from role identifier to the single address that holds that role
    mapping(bytes32 => address) private _roleHolders;

    /// @notice Emitted when a role was granted to an address
    ///
    /// @param role The role identifier
    /// @param account The address that was granted the role
    /// @param sender The address that performed the grant
    event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);

    /// @notice Emitted when a role was revoked from an address
    ///
    /// @param role The role identifier
    /// @param account The address that had the role revoked
    /// @param sender The address that performed the revoke
    event RoleRevoked(bytes32 indexed role, address indexed account, address indexed sender);

    error UnauthorizedAccess(bytes32 role, address account);

    /// @dev Initializer for SingleRoleAuthority
    function __SingleRoleAuthority_init() internal onlyInitializing {
        __SingleRoleAuthority_init_unchained();
    }

    function __SingleRoleAuthority_init_unchained() internal onlyInitializing {
        // No initialization needed
    }

    /// @notice Modifier to restrict access to addresses holding a specific role
    /// @param role The role identifier to check
    modifier onlyRole(bytes32 role) {
        _checkRole(role, msg.sender);
        _;
    }

    /// @notice Checks if an account has a specific role
    ///
    /// @param role The role identifier to check
    /// @param account The address to check
    ///
    /// @return True if the account has the role, false otherwise
    function hasRole(bytes32 role, address account) public view virtual returns (bool) {
        return _roleHolders[role] == account;
    }

    /// @notice Gets the address that holds a specific role
    ///
    /// @param role The role identifier to query
    ///
    /// @return The address holding the role, or address(0) if no one holds it
    function getRoleHolder(bytes32 role) public view virtual returns (address) {
        return _roleHolders[role];
    }

    /// @dev Internal function to check if msg.sender has the required role
    ///
    /// @param role The role identifier to check
    /// @param account The address to check
    function _checkRole(bytes32 role, address account) internal view virtual {
        if (!hasRole(role, account)) {
            revert UnauthorizedAccess(role, account);
        }
    }

    /// @dev Internal function to grant a role to an account
    /// @dev This will automatically revoke the role from any previous holder
    ///
    /// @param role The role identifier to grant
    /// @param account The address to grant the role to
    function _grantRole(bytes32 role, address account) internal virtual {
        address previousHolder = _roleHolders[role];

        // Only emit events and update if there's an actual change
        if (previousHolder != account) {
            // Revoke from previous holder if exists
            if (previousHolder != address(0)) {
                emit RoleRevoked(role, previousHolder, msg.sender);
            }

            // Grant to new holder
            _roleHolders[role] = account;
            emit RoleGranted(role, account, msg.sender);
        }
    }

    /// @dev Internal function to revoke a role from an account
    ///
    /// @param role The role identifier to revoke
    /// @param account The address to revoke the role from
    function _revokeRole(bytes32 role, address account) internal virtual {
        if (_roleHolders[role] == account) {
            delete _roleHolders[role];
            emit RoleRevoked(role, account, msg.sender);
        }
    }

    /// @dev This empty reserved space is put in place to allow future versions to add new
    /// variables without shifting down storage in the inheritance chain.
    uint256[49] private __gap;
}

