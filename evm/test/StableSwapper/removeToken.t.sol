// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {StableSwapper} from "../../src/StableSwapper.sol";
import {MockERC20, StableSwapperBase} from "./StableSwapperBase.sol";

/**
 * @title RemoveTokenTest
 * @notice Tests for the StableSwapper removeToken function
 */
contract RemoveTokenTest is StableSwapperBase {
    /*//////////////////////////////////////////////////////////////
                              REVERT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_removeToken_reverts_whenUnauthorizedUser() public {
        MockERC20 testToken = new MockERC20("Test Token", "TEST", 6);

        vm.prank(configureAuthority);
        swapper.addToken(address(testToken));

        vm.prank(pauseAuthority);
        swapper.updateTokenStatus(address(testToken), false);

        address unauthorized = makeAddr("unauthorized");

        vm.prank(unauthorized);
        vm.expectRevert();
        swapper.removeToken(address(testToken));
    }

    function test_removeToken_reverts_whenTokenIsZeroAddress() public {
        vm.prank(configureAuthority);
        vm.expectRevert(abi.encodeWithSelector(StableSwapper.CannotBeZeroAddress.selector, address(0)));
        swapper.removeToken(address(0));
    }

    function test_removeToken_reverts_whenTokenNotSupported() public {
        vm.prank(configureAuthority);
        vm.expectRevert(abi.encodeWithSelector(StableSwapper.TokenNotSupported.selector, address(usdc)));
        swapper.removeToken(address(usdc));
    }

    function test_removeToken_reverts_whenTokenIsNotDisabled() public {
        MockERC20 testToken = new MockERC20("Test Token", "TEST", 6);

        vm.startPrank(configureAuthority);
        swapper.addToken(address(testToken));

        vm.expectRevert(abi.encodeWithSelector(StableSwapper.TokenMustBeDisabled.selector, address(testToken)));
        swapper.removeToken(address(testToken));
        vm.stopPrank();
    }

    function test_removeToken_reverts_whenTokenHasNonZeroBalance() public {
        MockERC20 testToken = new MockERC20("Test Token", "TEST", 6);
        testToken.mint(treasuryAuthority, 1000000);

        vm.prank(configureAuthority);
        swapper.addToken(address(testToken));

        // Treasury deposits liquidity
        vm.prank(treasuryAuthority);
        testToken.transfer(address(swapper), 100000);

        // Disable token
        vm.prank(pauseAuthority);
        swapper.updateTokenStatus(address(testToken), false);

        // Try to remove with balance
        vm.prank(configureAuthority);
        vm.expectRevert(abi.encodeWithSelector(StableSwapper.TokenHasBalance.selector, address(testToken)));
        swapper.removeToken(address(testToken));
    }

    /*//////////////////////////////////////////////////////////////
                            SUCCESS TESTS
    //////////////////////////////////////////////////////////////*/

    function test_removeToken_removesTokenAfterWithdrawingAllLiquidity() public {
        MockERC20 testToken = new MockERC20("Test Token", "TEST", 6);
        uint256 initialMintAmount = 1000000;
        uint64 depositAmount = 100000;

        testToken.mint(treasuryAuthority, initialMintAmount);

        vm.prank(configureAuthority);
        swapper.addToken(address(testToken));

        // Treasury deposits liquidity (send directly to contract)
        vm.prank(treasuryAuthority);
        testToken.transfer(address(swapper), depositAmount);

        // Disable token
        vm.prank(pauseAuthority);
        swapper.updateTokenStatus(address(testToken), false);

        // Withdraw all liquidity
        vm.prank(treasuryAuthority);
        swapper.withdrawLiquidity(address(testToken), treasuryAuthority, depositAmount);

        // Now remove token
        vm.prank(configureAuthority);
        swapper.removeToken(address(testToken));

        uint256 expectedTokenCount = 0;
        assertEq(swapper.getSupportedTokensCount(), expectedTokenCount);
    }
}
