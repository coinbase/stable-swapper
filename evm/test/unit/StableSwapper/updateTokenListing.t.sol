// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {StableSwapper} from "../../../src/StableSwapper.sol";

import {MockERC20, StableSwapperBase} from "../../lib/StableSwapperBase.sol";

/**
 * @title UpdateTokenListingTest
 * @notice Tests for the StableSwapper updateTokenListing function
 */
contract UpdateTokenListingTest is StableSwapperBase {
    /*//////////////////////////////////////////////////////////////
                              REVERT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_updateTokenListing_reverts_whenUnauthorizedUser() public {
        address unauthorized = makeAddr("unauthorized");

        vm.prank(unauthorized);
        vm.expectRevert();
        swapper.updateTokenListing(address(usdc), true);
    }

    function test_updateTokenListing_reverts_whenTokenIsZeroAddress_listing() public {
        vm.prank(configureAuthority);
        vm.expectRevert(StableSwapper.CannotBeZeroAddress.selector);
        swapper.updateTokenListing(address(0), true);
    }

    function test_updateTokenListing_reverts_whenTokenIsZeroAddress_unlisting() public {
        vm.prank(configureAuthority);
        vm.expectRevert(StableSwapper.CannotBeZeroAddress.selector);
        swapper.updateTokenListing(address(0), false);
    }

    function test_updateTokenListing_enable_reverts_whenTokenAlreadyListed() public {
        vm.startPrank(configureAuthority);
        swapper.updateTokenListing(address(usdc), true);
        vm.expectRevert(abi.encodeWithSelector(StableSwapper.InvalidTokenListingState.selector, address(usdc), true));
        swapper.updateTokenListing(address(usdc), true);
        vm.stopPrank();
    }

    function test_updateTokenListing_disable_reverts_whenTokenNotListed() public {
        vm.prank(configureAuthority);
        vm.expectRevert(abi.encodeWithSelector(StableSwapper.InvalidTokenListingState.selector, address(usdc), false));
        swapper.updateTokenListing(address(usdc), false);
    }

    function test_updateTokenListing_disable_reverts_whenTokenIsSwappable() public {
        MockERC20 testToken = new MockERC20("Test Token", "TEST", 6);

        vm.prank(configureAuthority);
        swapper.updateTokenListing(address(testToken), true);

        vm.prank(pauseAuthority);
        swapper.updateTokenStatus(address(testToken), true);

        vm.prank(configureAuthority);
        vm.expectRevert(abi.encodeWithSelector(StableSwapper.TokenMustNotBeSwappable.selector, address(testToken)));
        swapper.updateTokenListing(address(testToken), false);
    }

    /*//////////////////////////////////////////////////////////////
                            SUCCESS TESTS
    //////////////////////////////////////////////////////////////*/

    function test_updateTokenListing_listsToken() public {
        vm.prank(configureAuthority);
        swapper.updateTokenListing(address(usdc), true);

        assertEq(swapper.getListedTokensCount(), 1);

        address[] memory listedTokens = swapper.getListedTokens();
        assertEq(listedTokens[0], address(usdc));

        assertFalse(swapper.isTokenSwappable(address(usdc)));
        assertEq(swapper.getReservedAmount(address(usdc)), 0);
        assertEq(swapper.getTokenDecimals(address(usdc)), 6);
    }

    function test_updateTokenListing_unlistsToken() public {
        MockERC20 testToken = new MockERC20("Test Token", "TEST", 6);

        vm.prank(configureAuthority);
        swapper.updateTokenListing(address(testToken), true);

        vm.prank(configureAuthority);
        swapper.updateTokenListing(address(testToken), false);

        assertEq(swapper.getListedTokensCount(), 0);

        // getTokenDecimals should revert for unlisted tokens
        vm.expectRevert(abi.encodeWithSelector(StableSwapper.TokenNotListed.selector, address(testToken)));
        swapper.getTokenDecimals(address(testToken));
    }

    function test_updateTokenListing_canRelistToken() public {
        MockERC20 testToken = new MockERC20("Test Token", "TEST", 6);

        vm.prank(configureAuthority);
        swapper.updateTokenListing(address(testToken), true);

        vm.prank(configureAuthority);
        swapper.updateTokenListing(address(testToken), false);

        assertEq(swapper.getListedTokensCount(), 0);

        vm.prank(configureAuthority);
        swapper.updateTokenListing(address(testToken), true);

        assertEq(swapper.getListedTokensCount(), 1);
        assertFalse(swapper.isTokenSwappable(address(testToken)));
        assertEq(swapper.getReservedAmount(address(testToken)), 0);
        assertEq(swapper.getTokenDecimals(address(testToken)), 6);
    }
}

