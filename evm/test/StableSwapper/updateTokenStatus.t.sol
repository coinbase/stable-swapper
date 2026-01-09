// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {StableSwapperBase} from "./StableSwapperBase.sol";
import {StableSwapper} from "../../src/StableSwapper.sol";

/**
 * @title UpdateTokenStatusTest
 * @notice Tests for the StableSwapper updateTokenStatus function
 */
contract UpdateTokenStatusTest is StableSwapperBase {
    /*//////////////////////////////////////////////////////////////
                              REVERT TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_revertsWhenUnauthorizedUserTriesToDisableToken() public {
        vm.prank(operationsAuthority);
        swapper.addToken(address(usdc));
        
        address unauthorized = makeAddr("unauthorized");
        
        vm.prank(unauthorized);
        vm.expectRevert();
        swapper.updateTokenStatus(address(usdc), false);
    }
    
    /*//////////////////////////////////////////////////////////////
                            SUCCESS TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_disablesTokenAndPreventsSwaps() public {
        setupBasicSwapEnvironment();
        
        // Disable USDC
        vm.prank(pauseAuthority);
        swapper.updateTokenStatus(address(usdc), false);
        
        StableSwapper.TokenVault memory vault = swapper.getVault(address(usdc));
        assertFalse(vault.isEnabled);
    }
    
    function test_reEnablesTokenAndAllowsSwapsAgain() public {
        setupBasicSwapEnvironment();
        
        // Disable then re-enable USDC
        vm.startPrank(pauseAuthority);
        swapper.updateTokenStatus(address(usdc), false);
        swapper.updateTokenStatus(address(usdc), true);
        vm.stopPrank();
        
        StableSwapper.TokenVault memory vault = swapper.getVault(address(usdc));
        assertTrue(vault.isEnabled);
        
        // Swap should succeed
        uint64 swapAmount = 10 * 10 ** 6;
        
        vm.startPrank(wallet0);
        usdc.approve(address(swapper), swapAmount);
        swapper.swap(address(usdc), address(appStable), swapAmount, swapAmount, wallet0);
        vm.stopPrank();
    }
}

