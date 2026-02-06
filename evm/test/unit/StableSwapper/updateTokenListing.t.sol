// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {StableSwapper} from "../../../src/StableSwapper.sol";

import {MockERC20, StableSwapperBase} from "../../lib/StableSwapperBase.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @notice Mock ERC20 token that does not implement the decimals() function
 * @dev This token only implements the core ERC20 interface, not the metadata extension
 */
contract MockERC20NoDecimals {
    string public name = "No Decimals Token";
    string public symbol = "NODEC";
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        if (allowance[from][msg.sender] != type(uint256).max) {
            allowance[from][msg.sender] -= amount;
        }
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
        return true;
    }

    function mint(address to, uint256 amount) external {
        totalSupply += amount;
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    // Note: decimals() is intentionally NOT implemented
}

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

    function test_updateTokenListing_listsTokenWithoutDecimals() public {
        MockERC20NoDecimals noDecToken = new MockERC20NoDecimals();

        vm.prank(configureAuthority);
        swapper.updateTokenListing(address(noDecToken), true);

        assertEq(swapper.getListedTokensCount(), 1);

        address[] memory listedTokens = swapper.getListedTokens();
        assertEq(listedTokens[0], address(noDecToken));

        assertFalse(swapper.isTokenSwappable(address(noDecToken)));
        assertEq(swapper.getReservedAmount(address(noDecToken)), 0);
        // Should default to 18 decimals when decimals() is not implemented
        assertEq(swapper.getTokenDecimals(address(noDecToken)), 18);
    }
}

