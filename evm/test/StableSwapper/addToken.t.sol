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
        vm.prank(configureAuthority);
        vm.expectRevert(StableSwapper.CannotBeZeroAddress.selector);
        swapper.addToken(address(0));
    }

    function test_addToken_reverts_whenTokenAlreadySupported() public {
        vm.startPrank(configureAuthority);
        swapper.addToken(address(usdc));
        vm.expectRevert(abi.encodeWithSelector(StableSwapper.TokenAlreadySupported.selector, address(usdc)));
        swapper.addToken(address(usdc));
        vm.stopPrank();
    }

    function test_addToken_reverts_whenMaxSupportedTokensReached() public {
        uint256 maxTokens = 50;
        // Add tokens up to the limit (50)
        vm.startPrank(configureAuthority);
        for (uint256 i = 0; i < maxTokens; i++) {
            MockERC20 token = new MockERC20(
                string(abi.encodePacked("Token", vm.toString(i))), string(abi.encodePacked("TOK", vm.toString(i))), 6
            );
            swapper.addToken(address(token));
        }

        // Try to add 51st token
        MockERC20 extraToken = new MockERC20("Extra Token", "EXTRA", 6);
        // casting to 'uint64' is safe because maxTokens is 50, well within uint64 range
        // forge-lint: disable-next-line(unsafe-typecast)
        vm.expectRevert(abi.encodeWithSelector(StableSwapper.SupportedTokensExceedsMaximum.selector, uint64(maxTokens)));
        swapper.addToken(address(extraToken));
        vm.stopPrank();
    }

    function test_addToken_reverts_whenTokenDoesNotImplementDecimals() public {
        MockERC20WithoutDecimals token = new MockERC20WithoutDecimals("Token", "TOK");
        vm.prank(configureAuthority);
        vm.expectRevert(abi.encodeWithSelector(StableSwapper.TokenDoesNotImplementDecimals.selector, address(token)));
        swapper.addToken(address(token));
    }

    function testFuzz_addToken_reverts_whenTokenDecimalsLessThan6(uint8 decimalsSeed) public {
        // Fuzz decimals from 0 to 5 (all invalid, below MIN_DECIMALS)
        uint8 invalidDecimals = uint8(bound(decimalsSeed, 0, 5));
        MockERC20 invalidToken = new MockERC20("Invalid Token", "INV", invalidDecimals);

        vm.prank(configureAuthority);
        vm.expectRevert(
            abi.encodeWithSelector(StableSwapper.DecimalsOutOfRange.selector, address(invalidToken), invalidDecimals)
        );
        swapper.addToken(address(invalidToken));
    }

    function testFuzz_addToken_reverts_whenTokenDecimalsGreaterThan18(uint8 decimalsSeed) public {
        // Fuzz decimals from 19 to 255 (all invalid, above MAX_DECIMALS)
        uint8 invalidDecimals = uint8(bound(decimalsSeed, 19, 255));
        MockERC20 invalidToken = new MockERC20("Invalid Token", "INV", invalidDecimals);

        vm.prank(configureAuthority);
        vm.expectRevert(
            abi.encodeWithSelector(StableSwapper.DecimalsOutOfRange.selector, address(invalidToken), invalidDecimals)
        );
        swapper.addToken(address(invalidToken));
    }

    /*//////////////////////////////////////////////////////////////
                            SUCCESS TESTS
    //////////////////////////////////////////////////////////////*/

    function test_addToken_addsSupportedTokens() public {
        vm.startPrank(configureAuthority);
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

    function testFuzz_addToken_acceptsTokensWithValidDecimalsInRange(uint8 decimalsSeed) public {
        // Fuzz decimals from 6 to 18 (all valid, within MIN_DECIMALS and MAX_DECIMALS)
        uint8 validDecimals = uint8(bound(decimalsSeed, 6, 18));

        MockERC20 token = new MockERC20(
            string(abi.encodePacked(vm.toString(validDecimals), " Decimal Token")),
            string(abi.encodePacked("TOK", vm.toString(validDecimals))),
            validDecimals
        );

        vm.prank(configureAuthority);
        swapper.addToken(address(token));

        // Verify token was added successfully
        assertEq(swapper.getSupportedTokensCount(), 1);

        // Verify vault information is stored correctly
        StableSwapper.TokenVault memory vault = swapper.getVault(address(token));
        assertTrue(vault.isEnabled, "Token should be enabled");
        assertEq(vault.decimals, validDecimals, "Decimals should match");
        assertEq(vault.reservedAmount, 0, "Reserved amount should be 0");

        // Verify token is in the supported tokens list
        address[] memory supportedTokens = swapper.getSupportedTokens();
        assertEq(supportedTokens[0], address(token), "Token should be in supported list");
    }
}
