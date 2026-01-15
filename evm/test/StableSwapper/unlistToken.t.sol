// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {StableSwapper} from "../../src/StableSwapper.sol";
import {MockERC20, StableSwapperBase} from "./StableSwapperBase.sol";

/**
 * @title UnlistTokenTest
 * @notice Tests for the StableSwapper unlistToken function
 */
contract UnlistTokenTest is StableSwapperBase {
    /*//////////////////////////////////////////////////////////////
                              REVERT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_unlistToken_reverts_whenUnauthorizedUser() public {
        MockERC20 testToken = new MockERC20("Test Token", "TEST", 6);

        vm.prank(configureAuthority);
        swapper.listToken(address(testToken));

        vm.prank(pauseAuthority);
        swapper.updateTokenStatus(address(testToken), false);

        address unauthorized = makeAddr("unauthorized");

        vm.prank(unauthorized);
        vm.expectRevert();
        swapper.unlistToken(address(testToken));
    }

    function test_unlistToken_reverts_whenTokenIsZeroAddress() public {
        vm.prank(configureAuthority);
        vm.expectRevert(StableSwapper.CannotBeZeroAddress.selector);
        swapper.unlistToken(address(0));
    }

    function test_unlistToken_reverts_whenTokenNotListed() public {
        vm.prank(configureAuthority);
        vm.expectRevert(abi.encodeWithSelector(StableSwapper.TokenNotListed.selector, address(usdc)));
        swapper.unlistToken(address(usdc));
    }

    function test_unlistToken_reverts_whenTokenIsNotDisabled() public {
        MockERC20 testToken = new MockERC20("Test Token", "TEST", 6);

        vm.prank(configureAuthority);
        swapper.listToken(address(testToken));

        // Enable the token
        vm.prank(pauseAuthority);
        swapper.updateTokenStatus(address(testToken), true);

        // Try to unlist while enabled
        vm.prank(configureAuthority);
        vm.expectRevert(abi.encodeWithSelector(StableSwapper.TokenMustBeDisabled.selector, address(testToken)));
        swapper.unlistToken(address(testToken));
    }

    /*//////////////////////////////////////////////////////////////
                            SUCCESS TESTS
    //////////////////////////////////////////////////////////////*/

    function test_unlistToken_unlistsDisabledToken() public {
        MockERC20 testToken = new MockERC20("Test Token", "TEST", 6);

        vm.prank(configureAuthority);
        swapper.listToken(address(testToken));

        // Disable token first
        vm.prank(pauseAuthority);
        swapper.updateTokenStatus(address(testToken), false);

        // Unlist token (balance not required to be zero)
        vm.prank(configureAuthority);
        swapper.unlistToken(address(testToken));

        assertEq(swapper.getListedTokensCount(), 0);
    }
}
