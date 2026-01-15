// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {StableSwapper} from "../../src/StableSwapper.sol";
import {StableSwapperBase} from "./StableSwapperBase.sol";

/**
 * @title AllowlistTest
 * @notice Tests for the StableSwapper allowlist functionality
 */
contract AllowlistTest is StableSwapperBase {
    /*//////////////////////////////////////////////////////////////
                              REVERT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_addToAllowlist_reverts_whenUnauthorizedUser() public {
        address unauthorized = makeAddr("unauthorized");

        vm.prank(unauthorized);
        vm.expectRevert();
        swapper.addToAllowlist(unauthorized);
    }

    function test_addToAllowlist_reverts_whenAddressIsZeroAddress() public {
        vm.prank(configureAuthority);
        vm.expectRevert(StableSwapper.CannotBeZeroAddress.selector);
        swapper.addToAllowlist(address(0));
    }

    function test_addToAllowlist_reverts_whenAddingDuplicateAddress() public {
        vm.startPrank(configureAuthority);
        swapper.addToAllowlist(wallet1);

        vm.expectRevert(abi.encodeWithSelector(StableSwapper.AddressAlreadyInAllowlist.selector, wallet1));
        swapper.addToAllowlist(wallet1);
        vm.stopPrank();
    }

    function test_removeFromAllowlist_reverts_whenUnauthorizedUser() public {
        address unauthorized = makeAddr("unauthorized");

        vm.prank(unauthorized);
        vm.expectRevert();
        swapper.removeFromAllowlist(unauthorized);
    }

    function test_removeFromAllowlist_reverts_whenAddressIsZeroAddress() public {
        vm.prank(configureAuthority);
        vm.expectRevert(StableSwapper.CannotBeZeroAddress.selector);
        swapper.removeFromAllowlist(address(0));
    }

    function test_enableAllowlist_reverts_whenUnauthorizedUser() public {
        address unauthorized = makeAddr("unauthorized");

        vm.prank(unauthorized);
        vm.expectRevert();
        swapper.setFeatureFlag(StableSwapper.FeatureFlag.ALLOWLIST, true);
    }

    function test_disableAllowlist_reverts_whenUnauthorizedUser() public {
        address unauthorized = makeAddr("unauthorized");

        vm.prank(unauthorized);
        vm.expectRevert();
        swapper.setFeatureFlag(StableSwapper.FeatureFlag.ALLOWLIST, false);
    }

    function test_removeFromAllowlist_reverts_whenAddressNotInAllowlist() public {
        address missingAddress = makeAddr("missingAddress");

        vm.prank(configureAuthority);
        vm.expectRevert(abi.encodeWithSelector(StableSwapper.AddressNotInAllowlist.selector, missingAddress));
        swapper.removeFromAllowlist(missingAddress);
    }

    function test_swap_reverts_whenNonAllowlistedUser() public {
        setupBasicSwapEnvironment();

        // Add wallet1 to allowlist and enable allowlist
        vm.startPrank(configureAuthority);
        swapper.addToAllowlist(wallet1);
        swapper.setFeatureFlag(StableSwapper.FeatureFlag.ALLOWLIST, true);
        vm.stopPrank();
        vm.stopPrank();

        // Mint tokens to wallet2 (not allowlisted)
        usdc.mint(wallet2, 100 * 10 ** 6);

        uint64 swapAmount = 10 * 10 ** 6;

        vm.startPrank(wallet2);
        usdc.approve(address(swapper), swapAmount);
        vm.expectRevert(abi.encodeWithSelector(StableSwapper.AddressNotInAllowlist.selector, wallet2));
        swapper.swap(address(usdc), address(appStable), swapAmount, swapAmount, wallet1);
        vm.stopPrank();
    }

    function test_swap_reverts_whenPreviouslyAllowlistedUserRemovedFromAllowlist() public {
        setupBasicSwapEnvironment();

        // Add wallet1 to allowlist, enable allowlist, then remove wallet1
        vm.startPrank(configureAuthority);
        swapper.addToAllowlist(wallet1);
        swapper.setFeatureFlag(StableSwapper.FeatureFlag.ALLOWLIST, true);
        swapper.removeFromAllowlist(wallet1);
        vm.stopPrank();

        // Mint tokens to wallet1
        usdc.mint(wallet1, 100 * 10 ** 6);

        uint64 swapAmount = 10 * 10 ** 6;

        vm.startPrank(wallet1);
        usdc.approve(address(swapper), swapAmount);
        vm.expectRevert(abi.encodeWithSelector(StableSwapper.AddressNotInAllowlist.selector, wallet1));
        swapper.swap(address(usdc), address(appStable), swapAmount, swapAmount, wallet1);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                            SUCCESS TESTS
    //////////////////////////////////////////////////////////////*/

    function test_addToAllowlist_addsUserToAllowlist() public {
        vm.prank(configureAuthority);
        swapper.addToAllowlist(wallet1);

        assertTrue(swapper.isAllowlisted(wallet1));
    }

    function test_removeFromAllowlist_removesUserFromAllowlist() public {
        vm.startPrank(configureAuthority);
        swapper.addToAllowlist(wallet1);
        swapper.removeFromAllowlist(wallet1);
        vm.stopPrank();

        assertFalse(swapper.isAllowlisted(wallet1));
    }

    function test_enableAllowlist_enablesAllowlist() public {
        vm.prank(configureAuthority);
        swapper.setFeatureFlag(StableSwapper.FeatureFlag.ALLOWLIST, true);

        assertTrue(swapper.isFeatureEnabled(StableSwapper.FeatureFlag.ALLOWLIST));
    }

    function test_disableAllowlist_disablesAllowlist() public {
        vm.startPrank(configureAuthority);
        swapper.setFeatureFlag(StableSwapper.FeatureFlag.ALLOWLIST, true);
        swapper.setFeatureFlag(StableSwapper.FeatureFlag.ALLOWLIST, false);
        vm.stopPrank();

        assertFalse(swapper.isFeatureEnabled(StableSwapper.FeatureFlag.ALLOWLIST));
    }

    function test_swap_allowsAnyUser_whenAllowlistDisabled() public {
        setupBasicSwapEnvironment();

        // Mint tokens to wallet2
        usdc.mint(wallet2, 100 * 10 ** 6);

        uint64 swapAmount = 10 * 10 ** 6;

        vm.startPrank(wallet2);
        usdc.approve(address(swapper), swapAmount);
        swapper.swap(address(usdc), address(appStable), swapAmount, swapAmount, wallet1);
        vm.stopPrank();

        assertEq(appStable.balanceOf(wallet1), swapAmount);
    }

    function test_swap_allowsAllowlistedUser() public {
        setupBasicSwapEnvironment();

        // Add wallet1 to allowlist and enable allowlist
        vm.startPrank(configureAuthority);
        swapper.addToAllowlist(wallet1);
        swapper.setFeatureFlag(StableSwapper.FeatureFlag.ALLOWLIST, true);
        vm.stopPrank();
        vm.stopPrank();

        // Mint tokens to wallet1
        usdc.mint(wallet1, 100 * 10 ** 6);

        uint64 swapAmount = 10 * 10 ** 6;

        vm.startPrank(wallet1);
        usdc.approve(address(swapper), swapAmount);
        swapper.swap(address(usdc), address(appStable), swapAmount, swapAmount, wallet1);
        vm.stopPrank();

        assertEq(appStable.balanceOf(wallet1), swapAmount);
    }

    function test_swap_allowsAnyUser_afterAllowlistDisabled() public {
        setupBasicSwapEnvironment();

        // Enable then disable allowlist
        vm.startPrank(configureAuthority);
        swapper.setFeatureFlag(StableSwapper.FeatureFlag.ALLOWLIST, true);
        swapper.setFeatureFlag(StableSwapper.FeatureFlag.ALLOWLIST, false);
        vm.stopPrank();

        // Mint tokens to wallet2
        usdc.mint(wallet2, 100 * 10 ** 6);

        uint64 swapAmount = 1 * 10 ** 6;

        vm.startPrank(wallet2);
        usdc.approve(address(swapper), swapAmount);
        swapper.swap(address(usdc), address(appStable), swapAmount, swapAmount, wallet1);
        vm.stopPrank();

        assertTrue(appStable.balanceOf(wallet1) > 0);
    }
}
