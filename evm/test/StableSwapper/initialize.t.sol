// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {StableSwapper} from "../../src/StableSwapper.sol";
import {StableSwapperBase} from "./StableSwapperBase.sol";

/**
 * @title InitializeTest
 * @notice Tests for the StableSwapper initialize function
 */
contract InitializeTest is StableSwapperBase {
    /*//////////////////////////////////////////////////////////////
                              REVERT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_initialize_reverts_whenCalledTwice() public {
        // Try to initialize again on already initialized contract
        vm.expectRevert();
        swapper.initialize(defaultAdmin, withdrawalAuthority, configureAuthority, pauseAuthority, feeRecipient, 0, 0);
    }

    function test_initialize_reverts_whenDefaultAdminIsZeroAddress() public {
        // Deploy new implementation
        StableSwapper newImplementation = new StableSwapper();

        // OpenZeppelin's AccessControlDefaultAdminRules does not allow zero address for DEFAULT_ADMIN_ROLE
        bytes memory initData = abi.encodeWithSelector(
            StableSwapper.initialize.selector,
            address(0), // defaultAdmin - not allowed
            withdrawalAuthority,
            configureAuthority,
            pauseAuthority,
            feeRecipient,
            uint64(0),
            uint48(0)
        );

        // Should revert with AccessControlInvalidDefaultAdmin
        vm.expectRevert();
        new ERC1967Proxy(address(newImplementation), initData);
    }

    /*//////////////////////////////////////////////////////////////
                            SUCCESS TESTS
    //////////////////////////////////////////////////////////////*/

    function test_initialize_setsAllInitialValues() public view {
        assertTrue(swapper.hasRole(swapper.DEFAULT_ADMIN_ROLE(), defaultAdmin));
        assertTrue(swapper.hasRole(swapper.WITHDRAW_ROLE(), withdrawalAuthority));
        assertTrue(swapper.hasRole(swapper.CONFIGURE_ROLE(), configureAuthority));
        assertTrue(swapper.hasRole(swapper.PAUSE_ROLE(), pauseAuthority));
        assertEq(swapper.feeRecipient(), feeRecipient);
        assertEq(swapper.feeBasisPoints(), 0);
        assertTrue(swapper.isFeatureEnabled(StableSwapper.FeatureFlag.SWAP));
        assertTrue(swapper.isFeatureEnabled(StableSwapper.FeatureFlag.WITHDRAW));
        assertEq(swapper.getListedTokensCount(), 0);
        assertFalse(swapper.isFeatureEnabled(StableSwapper.FeatureFlag.ALLOWLIST));
    }

    function test_initialize_allowsZeroAddressForOtherAuthorities() public {
        // Deploy new implementation
        StableSwapper newImplementation = new StableSwapper();

        // Zero addresses for non-admin authorities should be allowed (they just won't have permissions)
        bytes memory initData = abi.encodeWithSelector(
            StableSwapper.initialize.selector,
            defaultAdmin,
            address(0), // withdrawalAuthority - allowed
            address(0), // configureAuthority - allowed
            address(0), // pauseAuthority - allowed
            address(0), // feeRecipient - allowed
            uint64(0),
            uint48(0)
        );

        // Should not revert
        ERC1967Proxy newProxy = new ERC1967Proxy(address(newImplementation), initData);
        StableSwapper newSwapper = StableSwapper(address(newProxy));

        assertEq(newSwapper.feeRecipient(), address(0));
    }

    function test_initialize_setsContractVersion() public view {
        assertEq(swapper.contractVersion(), 1);
    }
}
