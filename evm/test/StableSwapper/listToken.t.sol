// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {StableSwapper} from "../../src/StableSwapper.sol";
import {MockERC20, StableSwapperBase} from "./StableSwapperBase.sol";

/**
 * @title ListTokenTest
 * @notice Tests for the StableSwapper listToken function
 */
contract ListTokenTest is StableSwapperBase {
    /*//////////////////////////////////////////////////////////////
                              REVERT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_listToken_reverts_whenUnauthorizedUser() public {
        address unauthorized = makeAddr("unauthorized");

        vm.prank(unauthorized);
        vm.expectRevert();
        swapper.listToken(address(usdc));
    }

    function test_listToken_reverts_whenTokenIsZeroAddress() public {
        vm.prank(configureAuthority);
        vm.expectRevert(StableSwapper.CannotBeZeroAddress.selector);
        swapper.listToken(address(0));
    }

    function test_listToken_reverts_whenTokenAlreadyListed() public {
        vm.startPrank(configureAuthority);
        swapper.listToken(address(usdc));
        vm.expectRevert(abi.encodeWithSelector(StableSwapper.TokenAlreadyListed.selector, address(usdc)));
        swapper.listToken(address(usdc));
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                            SUCCESS TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_listToken_listsSupportedTokens(uint8 decimals) public {
        vm.assume(decimals <= 30);

        MockERC20 token = new MockERC20(
            string(abi.encodePacked(vm.toString(decimals), " Decimal Token")),
            string(abi.encodePacked("TOK", vm.toString(decimals))),
            decimals
        );

        vm.prank(configureAuthority);
        swapper.listToken(address(token));

        // Verify token was listed successfully
        assertEq(swapper.getListedTokensCount(), 1);

        // Verify token is in the listed tokens array
        address[] memory listedTokens = swapper.getListedTokens();
        assertEq(listedTokens[0], address(token), "Token should be in listed tokens array");

        // Verify token information is stored correctly
        assertFalse(swapper.isTokenEnabled(address(token)), "Token should be disabled by default");
        assertEq(token.decimals(), decimals, "Decimals should match");
        assertEq(swapper.getReservedAmount(address(token)), 0, "Reserved amount should be 0");
    }
}
