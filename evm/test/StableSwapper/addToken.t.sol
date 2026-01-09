// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {StableSwapper} from "../../src/StableSwapper.sol";
import {MockERC20, StableSwapperBase} from "./StableSwapperBase.sol";

// Mock ERC20 token that doesn't implement the decimals() function
contract MockERC20WithoutDecimals is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    // Override decimals to always revert, simulating a token that doesn't implement it
    function decimals() public pure override returns (uint8) {
        revert("decimals() not implemented");
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/**
 * @title AddTokenTest
 * @notice Tests for the StableSwapper addToken function
 */
contract AddTokenTest is StableSwapperBase {
    /*//////////////////////////////////////////////////////////////
                              REVERT TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_addToken_reverts_whenUnauthorizedUser() public {
        address unauthorized = makeAddr("unauthorized");
        
        vm.prank(unauthorized);
        vm.expectRevert();
        swapper.addToken(address(usdc));
    }

    function test_addToken_reverts_whenTokenIsZeroAddress() public {
        vm.prank(operationsAuthority);
        vm.expectRevert(abi.encodeWithSelector(StableSwapper.CannotBeZeroAddress.selector, address(0)));
        swapper.addToken(address(0));
    }

    function test_addToken_reverts_whenTokenAlreadySupported() public {
        vm.startPrank(operationsAuthority);
        swapper.addToken(address(usdc));
        vm.expectRevert(abi.encodeWithSelector(StableSwapper.TokenAlreadySupported.selector, address(usdc)));
        swapper.addToken(address(usdc));
        vm.stopPrank();
    }

    function test_addToken_reverts_whenMaxSupportedTokensReached() public {
        uint256 maxTokens = 50;
        // Add tokens up to the limit (50)
        vm.startPrank(operationsAuthority);
        for (uint256 i = 0; i < maxTokens; i++) {
            MockERC20 token = new MockERC20(
                string(abi.encodePacked("Token", vm.toString(i))),
                string(abi.encodePacked("TOK", vm.toString(i))),
                6
            );
            swapper.addToken(address(token));
        }
        
        // Try to add 51st token
        MockERC20 extraToken = new MockERC20("Extra Token", "EXTRA", 6);
        vm.expectRevert(abi.encodeWithSelector(StableSwapper.SupportedTokensExceedsMaximum.selector, uint64(maxTokens)));
        swapper.addToken(address(extraToken));
        vm.stopPrank();
    }

    function test_addToken_reverts_whenTokenDoesNotImplementDecimals() public {
        MockERC20WithoutDecimals token = new MockERC20WithoutDecimals("Token", "TOK");
        vm.prank(operationsAuthority);
        vm.expectRevert(abi.encodeWithSelector(StableSwapper.TokenDoesNotImplementDecimals.selector, address(token)));
        swapper.addToken(address(token));
    }

    function test_addToken_reverts_whenTokenDecimalsLessThan6() public {
        MockERC20 invalidToken = new MockERC20("Invalid Token", "INV", 5);
        
        vm.prank(operationsAuthority);
        vm.expectRevert(abi.encodeWithSelector(StableSwapper.DecimalsOutOfRange.selector, address(invalidToken), 5));
        swapper.addToken(address(invalidToken));
    }
    
    function test_addToken_reverts_whenTokenDecimalsGreaterThan9() public {
        MockERC20 invalidToken = new MockERC20("Invalid Token", "INV", 12);
        
        vm.prank(operationsAuthority);
        vm.expectRevert(abi.encodeWithSelector(StableSwapper.DecimalsOutOfRange.selector, address(invalidToken), 12));
        swapper.addToken(address(invalidToken));
    }
    
    /*//////////////////////////////////////////////////////////////
                            SUCCESS TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_addToken_addsSupportedTokens() public {
        vm.startPrank(operationsAuthority);
        swapper.addToken(address(usdc));
        swapper.addToken(address(appStable));
        vm.stopPrank();
        
        uint256 expectedTokenCount = 2;
        uint8 expectedDecimalsUsdc = 6;
        uint8 expectedDecimalsAppStable = 6;
        uint64 expectedReservedAmount = 0;
        
        assertEq(swapper.getSupportedTokensCount(), expectedTokenCount);
        address[] memory tokens = swapper.getSupportedTokens();
        assertEq(tokens[0], address(usdc));
        assertEq(tokens[1], address(appStable));
        
        StableSwapper.TokenVault memory usdcVault = swapper.getVault(address(usdc));
        assertTrue(usdcVault.isEnabled);
        assertEq(usdcVault.decimals, expectedDecimalsUsdc);
        assertEq(usdcVault.reservedAmount, expectedReservedAmount);
        StableSwapper.TokenVault memory appStableVault = swapper.getVault(address(appStable));
        assertTrue(appStableVault.isEnabled);
        assertEq(appStableVault.decimals, expectedDecimalsAppStable);
        assertEq(appStableVault.reservedAmount, expectedReservedAmount);
    }
    
    function test_addToken_acceptsTokensWithValidDecimalsInRange() public {
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
        
        uint256 expectedTokenCount = 4;
        uint8 expectedDecimals6 = 6;
        uint8 expectedDecimals7 = 7;
        uint8 expectedDecimals8 = 8;
        uint8 expectedDecimals9 = 9;
        
        // Verify all were added
        assertEq(swapper.getSupportedTokensCount(), expectedTokenCount);
        
        // Verify vault decimals are stored correctly
        assertEq(swapper.getVault(address(token6Dec)).decimals, expectedDecimals6);
        assertEq(swapper.getVault(address(token7Dec)).decimals, expectedDecimals7);
        assertEq(swapper.getVault(address(token8Dec)).decimals, expectedDecimals8);
        assertEq(swapper.getVault(address(token9Dec)).decimals, expectedDecimals9);
    }
}

