// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {StableSwapperBase, MockERC20} from "./StableSwapperBase.sol";
import {StableSwapper} from "../../src/StableSwapper.sol";

/**
 * @title RemoveTokenTest
 * @notice Tests for the StableSwapper removeToken function
 */
contract RemoveTokenTest is StableSwapperBase {
    /*//////////////////////////////////////////////////////////////
                              REVERT TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_revertsWhenUnauthorizedUserTriesToRemoveToken() public {
        MockERC20 testToken = new MockERC20("Test Token", "TEST", 6);
        
        vm.prank(operationsAuthority);
        swapper.addToken(address(testToken));
        
        vm.prank(pauseAuthority);
        swapper.updateTokenStatus(address(testToken), false);
        
        address unauthorized = makeAddr("unauthorized");
        
        vm.prank(unauthorized);
        vm.expectRevert();
        swapper.removeToken(address(testToken));
    }
    
    function test_revertsWhenTokenIsNotDisabled() public {
        MockERC20 testToken = new MockERC20("Test Token", "TEST", 6);
        
        vm.startPrank(operationsAuthority);
        swapper.addToken(address(testToken));
        
        vm.expectRevert(abi.encodeWithSelector(StableSwapper.TokenMustBeDisabled.selector, address(testToken)));
        swapper.removeToken(address(testToken));
        vm.stopPrank();
    }
    
    function test_revertsWhenTokenHasNonZeroBalance() public {
        MockERC20 testToken = new MockERC20("Test Token", "TEST", 6);
        testToken.mint(operationsAuthority, 1000000);
        
        vm.startPrank(operationsAuthority);
        swapper.addToken(address(testToken));
        
        // Deposit liquidity
        testToken.approve(address(swapper), 100000);
        swapper.deposit_liquidity(address(testToken), 100000);
        vm.stopPrank();
        
        // Disable token
        vm.prank(pauseAuthority);
        swapper.updateTokenStatus(address(testToken), false);
        
        // Try to remove with balance
        vm.prank(operationsAuthority);
        vm.expectRevert(abi.encodeWithSelector(StableSwapper.TokenHasBalance.selector, address(testToken)));
        swapper.removeToken(address(testToken));
    }
    
    /*//////////////////////////////////////////////////////////////
                            SUCCESS TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_removesTokenAfterWithdrawingAllLiquidity() public {
        MockERC20 testToken = new MockERC20("Test Token", "TEST", 6);
        testToken.mint(operationsAuthority, 1000000);
        
        vm.startPrank(operationsAuthority);
        swapper.addToken(address(testToken));
        
        // Deposit liquidity
        testToken.approve(address(swapper), 100000);
        swapper.deposit_liquidity(address(testToken), 100000);
        vm.stopPrank();
        
        // Disable token
        vm.prank(pauseAuthority);
        swapper.updateTokenStatus(address(testToken), false);
        
        // Withdraw all liquidity
        vm.prank(operationsAuthority);
        swapper.withdraw_liquidity(address(testToken), 100000);
        
        // Now remove token
        vm.prank(operationsAuthority);
        swapper.removeToken(address(testToken));
        
        assertEq(swapper.getSupportedTokensCount(), 0);
    }
}

