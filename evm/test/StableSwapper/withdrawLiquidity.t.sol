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
        swapper.listToken(address(usdc));

        address unauthorized = makeAddr("unauthorized");

        vm.prank(unauthorized);
        vm.expectRevert();
        swapper.withdrawLiquidity(address(usdc), liquidityAmount, unauthorized);
    }

    function test_withdrawLiquidity_reverts_whenTokenIsZeroAddress() public {
        uint256 liquidityAmount = 100 * 10 ** 6;
        vm.prank(withdrawalAuthority);
        vm.expectRevert(StableSwapper.CannotBeZeroAddress.selector);
        swapper.withdrawLiquidity(address(0), liquidityAmount, withdrawalAuthority);
    }

    function test_withdrawLiquidity_reverts_whenRecipientIsZeroAddress() public {
        uint256 liquidityAmount = 100 * 10 ** 6;
        vm.prank(configureAuthority);
        swapper.listToken(address(usdc));

        vm.prank(withdrawalAuthority);
        vm.expectRevert(StableSwapper.CannotBeZeroAddress.selector);
        swapper.withdrawLiquidity(address(usdc), liquidityAmount, address(0));
    }

    function test_withdrawLiquidity_reverts_whenLiquidityPaused() public {
        vm.prank(configureAuthority);
        swapper.listToken(address(usdc));

        uint256 depositAmount = 500 * 10 ** 6;
        vm.prank(withdrawalAuthority);
        usdc.transfer(address(swapper), depositAmount);

        // Disable liquidity
        vm.prank(pauseAuthority);
        swapper.setFeatureFlag(StableSwapper.FeatureFlag.WITHDRAW, false);

        uint256 withdrawAmount = 10 * 10 ** 6;

        vm.prank(withdrawalAuthority);
        vm.expectRevert(StableSwapper.WithdrawalCannotBePaused.selector);
        swapper.withdrawLiquidity(address(usdc), withdrawAmount, withdrawalAuthority);

        // Enable liquidity
        vm.prank(pauseAuthority);
        swapper.setFeatureFlag(StableSwapper.FeatureFlag.WITHDRAW, true);
    }

    function test_withdrawLiquidity_reverts_whenTokenNotListed() public {
        uint256 liquidityAmount = 100 * 10 ** 6;
        vm.prank(withdrawalAuthority);
        vm.expectRevert(abi.encodeWithSelector(StableSwapper.TokenNotListed.selector, address(usdc)));
        swapper.withdrawLiquidity(address(usdc), liquidityAmount, withdrawalAuthority);
    }

    function test_withdrawLiquidity_reverts_whenWithdrawingZeroAmount() public {
        vm.prank(configureAuthority);
        swapper.listToken(address(usdc));

        vm.prank(withdrawalAuthority);
        vm.expectRevert(StableSwapper.CannotBeZeroAmount.selector);
        swapper.withdrawLiquidity(address(usdc), 0, withdrawalAuthority);
    }

    function testFuzz_withdrawLiquidity_reverts_whenWithdrawingMoreThanBalance(uint256 withdrawAmountSeed) public {
        uint256 liquidityAmount = 100 * 10 ** 6;
        uint256 withdrawAmount = bound(withdrawAmountSeed, liquidityAmount + 1, type(uint256).max);

        vm.prank(configureAuthority);
        swapper.listToken(address(usdc));

        vm.prank(withdrawalAuthority);
        usdc.transfer(address(swapper), liquidityAmount);

        vm.prank(withdrawalAuthority);
        vm.expectRevert(); // ERC20 will revert with insufficient balance
        swapper.withdrawLiquidity(address(usdc), withdrawAmount, withdrawalAuthority);
    }

    /*//////////////////////////////////////////////////////////////
                            SUCCESS TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_withdrawLiquidity_withdrawsUsdcLiquidity(uint256 withdrawAmountSeed) public {
        uint256 liquidityAmount = 100 * 10 ** 6;
        uint256 withdrawAmount = bound(withdrawAmountSeed, 1, liquidityAmount);

        vm.prank(configureAuthority);
        swapper.listToken(address(usdc));

        vm.prank(withdrawalAuthority);
        usdc.transfer(address(swapper), liquidityAmount);

        uint256 initialBalance = usdc.balanceOf(withdrawalAuthority);

        vm.prank(withdrawalAuthority);
        swapper.withdrawLiquidity(address(usdc), withdrawAmount, withdrawalAuthority);

        assertEq(usdc.balanceOf(address(swapper)), liquidityAmount - withdrawAmount);
        assertEq(usdc.balanceOf(withdrawalAuthority), initialBalance + withdrawAmount);
    }

    function testFuzz_withdrawLiquidity_allowsWithdrawal_regardlessOfReservedAmount(uint256 withdrawAmountSeed) public {
        uint256 liquidityAmount = 100 * 10 ** 6;
        uint256 reservedAmount = 100 * 10 ** 6;
        uint256 withdrawAmount = bound(withdrawAmountSeed, 1, liquidityAmount);

        vm.prank(configureAuthority);
        swapper.listToken(address(usdc));

        vm.prank(withdrawalAuthority);
        usdc.transfer(address(swapper), liquidityAmount);

        uint256 initialBalance = usdc.balanceOf(withdrawalAuthority);

        vm.prank(withdrawalAuthority);
        swapper.updateReservedAmount(address(usdc), reservedAmount);

        vm.prank(withdrawalAuthority);
        swapper.withdrawLiquidity(address(usdc), withdrawAmount, withdrawalAuthority);

        assertEq(usdc.balanceOf(address(swapper)), liquidityAmount - withdrawAmount);
        assertEq(usdc.balanceOf(withdrawalAuthority), initialBalance + withdrawAmount);
    }

    function testFuzz_withdrawLiquidity_allowsWithdrawalToArbitraryRecipient(uint256 withdrawAmountSeed) public {
        uint256 liquidityAmount = 100 * 10 ** 6;
        uint256 withdrawAmount = bound(withdrawAmountSeed, 1, liquidityAmount);

        vm.prank(configureAuthority);
        swapper.listToken(address(usdc));

        vm.prank(withdrawalAuthority);
        usdc.transfer(address(swapper), liquidityAmount);

        address recipient = makeAddr("recipient");
        uint256 initialRecipientBalance = usdc.balanceOf(recipient);
        uint256 initialWithdrawalAuthorityBalance = usdc.balanceOf(withdrawalAuthority);

        vm.prank(withdrawalAuthority);
        swapper.withdrawLiquidity(address(usdc), withdrawAmount, recipient);

        assertEq(usdc.balanceOf(address(swapper)), liquidityAmount - withdrawAmount);
        assertEq(usdc.balanceOf(recipient), initialRecipientBalance + withdrawAmount);
        assertEq(
            usdc.balanceOf(withdrawalAuthority),
            initialWithdrawalAuthorityBalance,
            "Withdrawal authority balance should not change"
        );
    }
}
