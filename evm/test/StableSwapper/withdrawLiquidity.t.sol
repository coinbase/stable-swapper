// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {StableSwapper} from "../../src/StableSwapper.sol";
import {StableSwapperBase} from "./StableSwapperBase.sol";

/**
 * @title WithdrawLiquidityTest
 * @notice Tests for the StableSwapper withdrawLiquidity function
 */
contract WithdrawLiquidityTest is StableSwapperBase {
    /*//////////////////////////////////////////////////////////////
                              REVERT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_withdrawLiquidity_reverts_whenUnauthorizedUser() public {
        uint256 liquidityAmount = 100 * 10 ** 6;
        vm.prank(configureAuthority);
        swapper.addToken(address(usdc));

        address unauthorized = makeAddr("unauthorized");

        vm.prank(unauthorized);
        vm.expectRevert();
        swapper.withdrawLiquidity(address(usdc), unauthorized, liquidityAmount);
    }

    function test_withdrawLiquidity_reverts_whenTokenIsZeroAddress() public {
        uint256 liquidityAmount = 100 * 10 ** 6;
        vm.prank(treasuryAuthority);
        vm.expectRevert(StableSwapper.CannotBeZeroAddress.selector);
        swapper.withdrawLiquidity(address(0), treasuryAuthority, liquidityAmount);
    }

    function test_withdrawLiquidity_reverts_whenRecipientIsZeroAddress() public {
        uint256 liquidityAmount = 100 * 10 ** 6;
        vm.prank(configureAuthority);
        swapper.addToken(address(usdc));

        vm.prank(treasuryAuthority);
        vm.expectRevert(StableSwapper.CannotBeZeroAddress.selector);
        swapper.withdrawLiquidity(address(usdc), address(0), liquidityAmount);
    }

    function test_withdrawLiquidity_reverts_whenLiquidityPaused() public {
        vm.prank(configureAuthority);
        swapper.addToken(address(usdc));

        uint256 depositAmount = 500 * 10 ** 6;
        vm.prank(treasuryAuthority);
        usdc.transfer(address(swapper), depositAmount);

        // Disable liquidity
        vm.prank(pauseAuthority);
        swapper.updateLiquidityStatus(false);

        uint256 withdrawAmount = 10 * 10 ** 6;

        vm.prank(treasuryAuthority);
        vm.expectRevert(StableSwapper.LiquidityCannotBePaused.selector);
        swapper.withdrawLiquidity(address(usdc), treasuryAuthority, withdrawAmount);

        // Enable liquidity
        vm.prank(pauseAuthority);
        swapper.updateLiquidityStatus(true);
    }

    function test_withdrawLiquidity_reverts_whenTokenNotSupported() public {
        uint256 liquidityAmount = 100 * 10 ** 6;
        vm.prank(treasuryAuthority);
        vm.expectRevert(abi.encodeWithSelector(StableSwapper.TokenNotSupported.selector, address(usdc)));
        swapper.withdrawLiquidity(address(usdc), treasuryAuthority, liquidityAmount);
    }

    function test_withdrawLiquidity_reverts_whenWithdrawingZeroAmount() public {
        vm.prank(configureAuthority);
        swapper.addToken(address(usdc));

        vm.prank(treasuryAuthority);
        vm.expectRevert(StableSwapper.CannotBeZeroAmount.selector);
        swapper.withdrawLiquidity(address(usdc), treasuryAuthority, 0);
    }

    function testFuzz_withdrawLiquidity_reverts_whenWithdrawingMoreThanBalance(uint256 withdrawAmountSeed) public {
        uint256 liquidityAmount = 100 * 10 ** 6;
        uint256 withdrawAmount = bound(withdrawAmountSeed, liquidityAmount + 1, type(uint256).max);

        vm.prank(configureAuthority);
        swapper.addToken(address(usdc));

        vm.prank(treasuryAuthority);
        usdc.transfer(address(swapper), liquidityAmount);

        vm.prank(treasuryAuthority);
        vm.expectRevert(
            abi.encodeWithSelector(
                StableSwapper.LiquidityWithdrawExceedsBalance.selector, address(usdc), withdrawAmount, liquidityAmount
            )
        );
        swapper.withdrawLiquidity(address(usdc), treasuryAuthority, withdrawAmount);
    }

    /*//////////////////////////////////////////////////////////////
                            SUCCESS TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_withdrawLiquidity_withdrawsUsdcLiquidity(uint256 withdrawAmountSeed) public {
        uint256 liquidityAmount = 100 * 10 ** 6;
        uint256 withdrawAmount = bound(withdrawAmountSeed, 1, liquidityAmount);

        vm.prank(configureAuthority);
        swapper.addToken(address(usdc));

        vm.prank(treasuryAuthority);
        usdc.transfer(address(swapper), liquidityAmount);

        uint256 initialBalance = usdc.balanceOf(treasuryAuthority);

        vm.prank(treasuryAuthority);
        swapper.withdrawLiquidity(address(usdc), treasuryAuthority, withdrawAmount);

        assertEq(usdc.balanceOf(address(swapper)), liquidityAmount - withdrawAmount);
        assertEq(usdc.balanceOf(treasuryAuthority), initialBalance + withdrawAmount);
    }

    function testFuzz_withdrawLiquidity_allowsWithdrawal_regardlessOfReservedAmount(uint256 withdrawAmountSeed) public {
        uint256 liquidityAmount = 100 * 10 ** 6;
        uint256 reservedAmount = 100 * 10 ** 6;
        uint256 withdrawAmount = bound(withdrawAmountSeed, 1, liquidityAmount);

        vm.prank(configureAuthority);
        swapper.addToken(address(usdc));

        vm.prank(treasuryAuthority);
        usdc.transfer(address(swapper), liquidityAmount);

        uint256 initialBalance = usdc.balanceOf(treasuryAuthority);

        vm.prank(treasuryAuthority);
        swapper.updateReservedAmount(address(usdc), reservedAmount);

        vm.prank(treasuryAuthority);
        swapper.withdrawLiquidity(address(usdc), treasuryAuthority, withdrawAmount);

        assertEq(usdc.balanceOf(address(swapper)), liquidityAmount - withdrawAmount);
        assertEq(usdc.balanceOf(treasuryAuthority), initialBalance + withdrawAmount);
    }

    function testFuzz_withdrawLiquidity_allowsWithdrawalToArbitraryRecipient(uint256 withdrawAmountSeed) public {
        uint256 liquidityAmount = 100 * 10 ** 6;
        uint256 withdrawAmount = bound(withdrawAmountSeed, 1, liquidityAmount);

        vm.prank(configureAuthority);
        swapper.addToken(address(usdc));

        vm.prank(treasuryAuthority);
        usdc.transfer(address(swapper), liquidityAmount);

        address recipient = makeAddr("recipient");
        uint256 initialRecipientBalance = usdc.balanceOf(recipient);
        uint256 initialTreasuryBalance = usdc.balanceOf(treasuryAuthority);

        vm.prank(treasuryAuthority);
        swapper.withdrawLiquidity(address(usdc), recipient, withdrawAmount);

        assertEq(usdc.balanceOf(address(swapper)), liquidityAmount - withdrawAmount);
        assertEq(usdc.balanceOf(recipient), initialRecipientBalance + withdrawAmount);
        assertEq(
            usdc.balanceOf(treasuryAuthority), initialTreasuryBalance, "Treasury authority balance should not change"
        );
    }
}
