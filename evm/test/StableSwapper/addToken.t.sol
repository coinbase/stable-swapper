// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {StableSwapperBase, MockERC20} from "./StableSwapperBase.sol";
import {StableSwapper} from "../../src/StableSwapper.sol";

/**
 * @title AddTokenTest
 * @notice Tests for the StableSwapper addToken function
 */
contract AddTokenTest is StableSwapperBase {
    /*//////////////////////////////////////////////////////////////
                              REVERT TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_revertsWhenUnauthorizedUserTriesToAddToken() public {
        address unauthorized = makeAddr("unauthorized");
        
        vm.prank(unauthorized);
        vm.expectRevert();
        swapper.addToken(address(usdc));
    }
    
    function test_revertsWhenTokenDecimalsLessThan6() public {
        MockERC20 invalidToken = new MockERC20("Invalid Token", "INV", 5);
        
        vm.prank(operationsAuthority);
        vm.expectRevert(abi.encodeWithSelector(StableSwapper.DecimalsOutOfRange.selector, address(invalidToken), 5));
        swapper.addToken(address(invalidToken));
    }
    
    function test_revertsWhenTokenDecimalsGreaterThan9() public {
        MockERC20 invalidToken = new MockERC20("Invalid Token", "INV", 12);
        
        vm.prank(operationsAuthority);
        vm.expectRevert(abi.encodeWithSelector(StableSwapper.DecimalsOutOfRange.selector, address(invalidToken), 12));
        swapper.addToken(address(invalidToken));
    }
    
    function test_revertsWhenMaxSupportedTokensReached() public {
        // Add tokens up to the limit (50)
        vm.startPrank(operationsAuthority);
        for (uint256 i = 0; i < 50; i++) {
            MockERC20 token = new MockERC20(
                string(abi.encodePacked("Token", vm.toString(i))),
                string(abi.encodePacked("TOK", vm.toString(i))),
                6
            );
            swapper.addToken(address(token));
        }
        
        // Try to add 51st token
        MockERC20 extraToken = new MockERC20("Extra Token", "EXTRA", 6);
        vm.expectRevert(abi.encodeWithSelector(StableSwapper.SupportedTokensExceedsMaximum.selector, uint64(50)));
        swapper.addToken(address(extraToken));
        vm.stopPrank();
    }
    
    /*//////////////////////////////////////////////////////////////
                            SUCCESS TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_addsUsdcAsSupportedToken() public {
        vm.prank(operationsAuthority);
        swapper.addToken(address(usdc));
        
        assertEq(swapper.getSupportedTokensCount(), 1);
        address[] memory tokens = swapper.getSupportedTokens();
        assertEq(tokens[0], address(usdc));
        
        StableSwapper.TokenVault memory vault = swapper.getVault(address(usdc));
        assertTrue(vault.isEnabled);
        assertEq(vault.decimals, 6);
        assertEq(vault.reservedAmount, 0);
    }
    
    function test_addsAppStableAsSupportedToken() public {
        vm.prank(operationsAuthority);
        swapper.addToken(address(usdc));
        
        vm.prank(operationsAuthority);
        swapper.addToken(address(appStable));
        
        assertEq(swapper.getSupportedTokensCount(), 2);
    }
    
    function test_addsNewTestToken() public {
        MockERC20 testToken = new MockERC20("Test Token", "TEST", 6);
        
        vm.prank(operationsAuthority);
        swapper.addToken(address(testToken));
        
        assertEq(swapper.getSupportedTokensCount(), 1);
    }
    
    function test_acceptsTokensWithValidDecimalsInRange() public {
        // Test that tokens with 6, 7, 8, and 9 decimals are all accepted
        MockERC20 token6Dec = new MockERC20("6 Decimal Token", "TOK6", 6);
        MockERC20 token7Dec = new MockERC20("7 Decimal Token", "TOK7", 7);
        MockERC20 token8Dec = new MockERC20("8 Decimal Token", "TOK8", 8);
        MockERC20 token9Dec = new MockERC20("9 Decimal Token", "TOK9", 9);
        
        vm.startPrank(operationsAuthority);
        
        // Should all succeed - valid decimal range
        swapper.addToken(address(token6Dec));
        swapper.addToken(address(token7Dec));
        swapper.addToken(address(token8Dec));
        swapper.addToken(address(token9Dec));
        
        vm.stopPrank();
        
        // Verify all were added
        assertEq(swapper.getSupportedTokensCount(), 4);
        
        // Verify vault decimals are stored correctly
        assertEq(swapper.getVault(address(token6Dec)).decimals, 6);
        assertEq(swapper.getVault(address(token7Dec)).decimals, 7);
        assertEq(swapper.getVault(address(token8Dec)).decimals, 8);
        assertEq(swapper.getVault(address(token9Dec)).decimals, 9);
    }
}

