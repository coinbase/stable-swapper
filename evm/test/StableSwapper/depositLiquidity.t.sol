// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {StableSwapper} from "../../src/StableSwapper.sol";
import {StableSwapperBase} from "./StableSwapperBase.sol";

/**
 * @title DepositLiquidityTest
 * @notice Tests for the StableSwapper depositLiquidity function
 */
contract DepositLiquidityTest is StableSwapperBase {
    /*//////////////////////////////////////////////////////////////
                              REVERT TESTS
    //////////////////////////////////////////////////////////////*/
    function test_depositLiquidity_reverts_whenUnauthorizedUser() public {
        vm.prank(operationsAuthority);
        swapper.addToken(address(usdc));

        address unauthorized = makeAddr("unauthorized");
        usdc.mint(unauthorized, 100 * 10 ** 6);

        vm.startPrank(unauthorized);
        usdc.approve(address(swapper), 10 * 10 ** 6);
        vm.expectRevert();
        swapper.depositLiquidity(address(usdc), 10 * 10 ** 6);
        vm.stopPrank();
    }

    function test_depositLiquidity_reverts_whenTokenIsZeroAddress() public {
        vm.prank(operationsAuthority);
        vm.expectRevert(StableSwapper.CannotBeZeroAddress.selector);
        swapper.depositLiquidity(address(0), 10 * 10 ** 6);
    }

    function test_depositLiquidity_reverts_whenLiquidityPaused() public {
        vm.prank(operationsAuthority);
        swapper.addToken(address(usdc));

        // Pause liquidity
        vm.prank(pauseAuthority);
        swapper.pauseLiquidity();

        uint64 depositAmount = 10 * 10 ** 6;

        vm.startPrank(operationsAuthority);
        usdc.approve(address(swapper), depositAmount);
        vm.expectRevert(StableSwapper.LiquidityCannotBePaused.selector);
        swapper.depositLiquidity(address(usdc), depositAmount);
        vm.stopPrank();

        // Unpause liquidity
        vm.prank(pauseAuthority);
        swapper.unpauseLiquidity();
    }

    function test_depositLiquidity_reverts_whenTokenNotSupported() public {
        vm.prank(operationsAuthority);
        vm.expectRevert(abi.encodeWithSelector(StableSwapper.TokenNotSupported.selector, address(usdc)));
        swapper.depositLiquidity(address(usdc), 10 * 10 ** 6);
    }

    function test_depositLiquidity_reverts_whenDepositingZeroAmount() public {
        vm.prank(operationsAuthority);
        swapper.addToken(address(usdc));

        vm.prank(operationsAuthority);
        vm.expectRevert(StableSwapper.CannotBeZeroAmount.selector);
        swapper.depositLiquidity(address(usdc), 0);
    }

    /*//////////////////////////////////////////////////////////////
                            SUCCESS TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_depositLiquidity_depositsUsdcLiquidity(uint256 depositAmountSeed) public {
        uint64 maxBalance = 1000 * 10 ** 6; // Amount minted to operationsAuthority in setUp
        uint64 depositAmount = uint64(bound(depositAmountSeed, 1, maxBalance));

        vm.prank(operationsAuthority);
        swapper.addToken(address(usdc));

        vm.startPrank(operationsAuthority);
        usdc.approve(address(swapper), depositAmount);
        swapper.depositLiquidity(address(usdc), depositAmount);
        vm.stopPrank();

        assertEq(usdc.balanceOf(address(swapper)), depositAmount);
    }

    function testFuzz_depositLiquidity_depositsAppStableLiquidity(uint256 depositAmountSeed) public {
        uint64 maxBalance = 1000 * 10 ** 6; // Amount minted to operationsAuthority in setUp
        uint64 depositAmount = uint64(bound(depositAmountSeed, 1, maxBalance));

        vm.prank(operationsAuthority);
        swapper.addToken(address(appStable));

        vm.startPrank(operationsAuthority);
        appStable.approve(address(swapper), depositAmount);
        swapper.depositLiquidity(address(appStable), depositAmount);
        vm.stopPrank();

        assertEq(appStable.balanceOf(address(swapper)), depositAmount);
    }
}
