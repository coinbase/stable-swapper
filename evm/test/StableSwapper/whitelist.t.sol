// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {StableSwapperBase} from "./StableSwapperBase.sol";
import {StableSwapper} from "../../src/StableSwapper.sol";

/**
 * @title WhitelistTest
 * @notice Tests for the StableSwapper whitelist functionality
 */
contract WhitelistTest is StableSwapperBase {
    /*//////////////////////////////////////////////////////////////
                              REVERT TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_addToWhitelist_reverts_whenUnauthorizedUser() public {
        address unauthorized = makeAddr("unauthorized");
        
        vm.prank(unauthorized);
        vm.expectRevert();
        swapper.addToWhitelist(unauthorized);
    }
    
    function test_addToWhitelist_reverts_whenAddingDuplicateAddress() public {
        vm.startPrank(pauseAuthority);
        swapper.addToWhitelist(wallet1);
        
        vm.expectRevert(abi.encodeWithSelector(StableSwapper.AddressAlreadyInWhitelist.selector, wallet1));
        swapper.addToWhitelist(wallet1);
        vm.stopPrank();
    }
    
    function test_addToWhitelist_reverts_whenMaxWhitelistAddressesReached() public {
        vm.startPrank(pauseAuthority);
        
        uint256 maxWhitelistSize = 100;
        // Add 100 addresses
        for (uint256 i = 0; i < maxWhitelistSize; i++) {
            address addr = makeAddr(string(abi.encodePacked("user", vm.toString(i))));
            swapper.addToWhitelist(addr);
        }
        
        // Try to add 101st address
        address extraAddr = makeAddr("extraUser");
        vm.expectRevert(abi.encodeWithSelector(StableSwapper.WhitelistExceedsMaximum.selector, uint64(maxWhitelistSize)));
        swapper.addToWhitelist(extraAddr);
        
        vm.stopPrank();
    }
    
    function test_removeFromWhitelist_reverts_whenAddressNotInWhitelist() public {
        address missingAddress = makeAddr("missingAddress");
        
        vm.prank(pauseAuthority);
        vm.expectRevert(abi.encodeWithSelector(StableSwapper.AddressNotInWhitelist.selector, missingAddress));
        swapper.removeFromWhitelist(missingAddress);
    }
    
    function test_swap_reverts_whenNonWhitelistedUser() public {
        setupBasicSwapEnvironment();
        
        // Add wallet1 to whitelist and enable whitelist
        vm.startPrank(pauseAuthority);
        swapper.addToWhitelist(wallet1);
        swapper.enableWhitelist();
        vm.stopPrank();
        
        // Mint tokens to wallet2 (not whitelisted)
        usdc.mint(wallet2, 100 * 10 ** 6);
        
        uint64 swapAmount = 10 * 10 ** 6;
        
        vm.startPrank(wallet2);
        usdc.approve(address(swapper), swapAmount);
        vm.expectRevert(abi.encodeWithSelector(StableSwapper.AddressNotInWhitelist.selector, wallet2));
        swapper.swap(address(usdc), address(appStable), swapAmount, swapAmount, wallet1);
        vm.stopPrank();
    }
    
    function test_swap_reverts_whenPreviouslyWhitelistedUserRemovedFromWhitelist() public {
        setupBasicSwapEnvironment();
        
        // Add wallet1 to whitelist, enable whitelist, then remove wallet1
        vm.startPrank(pauseAuthority);
        swapper.addToWhitelist(wallet1);
        swapper.enableWhitelist();
        swapper.removeFromWhitelist(wallet1);
        vm.stopPrank();
        
        // Mint tokens to wallet1
        usdc.mint(wallet1, 100 * 10 ** 6);
        
        uint64 swapAmount = 10 * 10 ** 6;
        
        vm.startPrank(wallet1);
        usdc.approve(address(swapper), swapAmount);
        vm.expectRevert(abi.encodeWithSelector(StableSwapper.AddressNotInWhitelist.selector, wallet1));
        swapper.swap(address(usdc), address(appStable), swapAmount, swapAmount, wallet1);
        vm.stopPrank();
    }
    
    /*//////////////////////////////////////////////////////////////
                            SUCCESS TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_addToWhitelist_addsUserToWhitelist() public {
        vm.prank(pauseAuthority);
        swapper.addToWhitelist(wallet1);
        
        uint256 expectedCount = 1;
        assertEq(swapper.getWhitelistedAddressesCount(), expectedCount);
        address[] memory whitelisted = swapper.getWhitelistedAddresses();
        assertEq(whitelisted[0], wallet1);
    }
    
    function test_removeFromWhitelist_removesUserFromWhitelist() public {
        vm.startPrank(pauseAuthority);
        swapper.addToWhitelist(wallet1);
        swapper.removeFromWhitelist(wallet1);
        vm.stopPrank();
        
        uint256 expectedCount = 0;
        assertEq(swapper.getWhitelistedAddressesCount(), expectedCount);
    }
    
    function test_enableWhitelist_enablesWhitelist() public {
        vm.prank(pauseAuthority);
        swapper.enableWhitelist();
        
        assertTrue(swapper.whitelistEnabled());
    }
    
    function test_disableWhitelist_disablesWhitelist() public {
        vm.startPrank(pauseAuthority);
        swapper.enableWhitelist();
        swapper.disableWhitelist();
        vm.stopPrank();
        
        assertFalse(swapper.whitelistEnabled());
    }
    
    function test_swap_allowsAnyUser_whenWhitelistDisabled() public {
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
    
    function test_swap_allowsWhitelistedUser() public {
        setupBasicSwapEnvironment();
        
        // Add wallet1 to whitelist and enable whitelist
        vm.startPrank(pauseAuthority);
        swapper.addToWhitelist(wallet1);
        swapper.enableWhitelist();
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
    
    function test_swap_allowsAnyUser_afterWhitelistDisabled() public {
        setupBasicSwapEnvironment();
        
        // Enable then disable whitelist
        vm.startPrank(pauseAuthority);
        swapper.enableWhitelist();
        swapper.disableWhitelist();
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

