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
        uint64 liquidityAmount = 100 * 10 ** 6;
        vm.prank(operationsAuthority);
        swapper.addToken(address(usdc));

        address unauthorized = makeAddr("unauthorized");

        vm.prank(unauthorized);
        vm.expectRevert();
        swapper.withdrawLiquidity(address(usdc), liquidityAmount);
    }

    function test_withdrawLiquidity_reverts_whenTokenIsZeroAddress() public {
        uint64 liquidityAmount = 100 * 10 ** 6;
        vm.prank(operationsAuthority);
        vm.expectRevert(abi.encodeWithSelector(StableSwapper.CannotBeZeroAddress.selector, address(0)));
        swapper.withdrawLiquidity(address(0), liquidityAmount);
    }

    function test_withdrawLiquidity_reverts_whenLiquidityPaused() public {
        vm.prank(operationsAuthority);
        swapper.addToken(address(usdc));

        uint64 depositAmount = 500 * 10 ** 6;
        vm.startPrank(operationsAuthority);
        usdc.approve(address(swapper), depositAmount);
        swapper.depositLiquidity(address(usdc), depositAmount);
        vm.stopPrank();

        // Disable liquidity
        vm.prank(pauseAuthority);
        swapper.updateLiquidityStatus(false);

        uint64 withdrawAmount = 10 * 10 ** 6;

        vm.prank(operationsAuthority);
        vm.expectRevert(StableSwapper.LiquidityCannotBePaused.selector);
        swapper.withdrawLiquidity(address(usdc), withdrawAmount);

        // Enable liquidity
        vm.prank(pauseAuthority);
        swapper.updateLiquidityStatus(true);
    }

    function test_withdrawLiquidity_reverts_whenTokenNotSupported() public {
        uint64 liquidityAmount = 100 * 10 ** 6;
        vm.prank(operationsAuthority);
        vm.expectRevert(abi.encodeWithSelector(StableSwapper.TokenNotSupported.selector, address(usdc)));
        swapper.withdrawLiquidity(address(usdc), liquidityAmount);
    }

    function test_withdrawLiquidity_reverts_whenWithdrawingZeroAmount() public {
        vm.prank(operationsAuthority);
        swapper.addToken(address(usdc));

        vm.prank(operationsAuthority);
        vm.expectRevert(StableSwapper.CannotBeZeroAmount.selector);
        swapper.withdrawLiquidity(address(usdc), 0);
    }

    function testFuzz_withdrawLiquidity_reverts_whenWithdrawingMoreThanBalance(uint256 withdrawAmountSeed) public {
        uint64 liquidityAmount = 100 * 10 ** 6;
        uint64 withdrawAmount = uint64(bound(withdrawAmountSeed, liquidityAmount + 1, type(uint64).max));

        vm.prank(operationsAuthority);
        swapper.addToken(address(usdc));

        vm.startPrank(operationsAuthority);
        usdc.approve(address(swapper), liquidityAmount);
        swapper.depositLiquidity(address(usdc), liquidityAmount);

        vm.expectRevert(
            abi.encodeWithSelector(
                StableSwapper.LiquidityWithdrawExceedsBalance.selector, address(usdc), withdrawAmount, liquidityAmount
            )
        );
        swapper.withdrawLiquidity(address(usdc), withdrawAmount);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                            SUCCESS TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_withdrawLiquidity_withdrawsUsdcLiquidity(uint256 withdrawAmountSeed) public {
        uint64 liquidityAmount = 100 * 10 ** 6;
        uint64 withdrawAmount = uint64(bound(withdrawAmountSeed, 1, liquidityAmount));

        vm.prank(operationsAuthority);
        swapper.addToken(address(usdc));

        vm.startPrank(operationsAuthority);
        usdc.approve(address(swapper), liquidityAmount);
        swapper.depositLiquidity(address(usdc), liquidityAmount);
        vm.stopPrank();

        uint256 initialBalance = usdc.balanceOf(operationsAuthority);

        vm.prank(operationsAuthority);
        swapper.withdrawLiquidity(address(usdc), withdrawAmount);

        assertEq(usdc.balanceOf(address(swapper)), liquidityAmount - withdrawAmount);
        assertEq(usdc.balanceOf(operationsAuthority), initialBalance + withdrawAmount);
    }

    function testFuzz_withdrawLiquidity_allowsWithdrawal_regardlessOfReservedAmount(uint256 withdrawAmountSeed) public {
        uint64 liquidityAmount = 100 * 10 ** 6;
        uint64 reservedAmount = 100 * 10 ** 6;
        uint64 withdrawAmount = uint64(bound(withdrawAmountSeed, 1, liquidityAmount));

        vm.prank(operationsAuthority);
        swapper.addToken(address(usdc));

        vm.startPrank(operationsAuthority);
        usdc.approve(address(swapper), liquidityAmount);
        swapper.depositLiquidity(address(usdc), liquidityAmount);
        vm.stopPrank();

        uint256 initialBalance = usdc.balanceOf(operationsAuthority);

        vm.prank(operationsAuthority);
        swapper.updateReservedAmount(address(usdc), reservedAmount);

        vm.prank(operationsAuthority);
        swapper.withdrawLiquidity(address(usdc), withdrawAmount);

        assertEq(usdc.balanceOf(address(swapper)), liquidityAmount - withdrawAmount);
        assertEq(usdc.balanceOf(operationsAuthority), initialBalance + withdrawAmount);
    }
}
