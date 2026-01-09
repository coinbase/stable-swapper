// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {StableSwapperBase, MockERC20} from "./StableSwapperBase.sol";
import {StableSwapper} from "../../src/StableSwapper.sol";

/**
 * @title SwapTest
 * @notice Tests for the StableSwapper swap function
 */
contract SwapTest is StableSwapperBase {
    /*//////////////////////////////////////////////////////////////
                              REVERT TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_swap_reverts_whenSwapsPaused() public {
        setupBasicSwapEnvironment();
        
        vm.prank(pauseAuthority);
        swapper.pauseSwaps();
        
        uint64 swapAmount = 10 * 10 ** 6;
        
        vm.startPrank(wallet0);
        usdc.approve(address(swapper), swapAmount);
        vm.expectRevert(StableSwapper.SwapsCannotBePaused.selector);
        swapper.swap(address(usdc), address(appStable), swapAmount, swapAmount, wallet0);
        vm.stopPrank();
        
        vm.prank(pauseAuthority);
        swapper.unpauseSwaps();
    }
    
    function test_swap_reverts_whenSwappingSameToken() public {
        vm.startPrank(operationsAuthority);
        swapper.addToken(address(usdc));
        
        usdc.approve(address(swapper), 500 * 10 ** 6);
        swapper.depositLiquidity(address(usdc), 500 * 10 ** 6);
        vm.stopPrank();
        
        uint64 swapAmount = 10 * 10 ** 6;
        
        vm.startPrank(wallet0);
        usdc.approve(address(swapper), swapAmount);
        // Should fail - cannot swap a token for itself
        vm.expectRevert(abi.encodeWithSelector(StableSwapper.CannotSwapSameToken.selector, address(usdc)));
        swapper.swap(address(usdc), address(usdc), swapAmount, swapAmount, wallet0);
        vm.stopPrank();
    }
    
    function test_swap_reverts_whenInsufficientLiquidity() public {
        vm.startPrank(operationsAuthority);
        swapper.addToken(address(usdc));
        swapper.addToken(address(appStable));
        
        // Deposit limited liquidity
        usdc.approve(address(swapper), 100 * 10 ** 6);
        swapper.depositLiquidity(address(usdc), 100 * 10 ** 6);
        
        appStable.approve(address(swapper), 100 * 10 ** 6);
        swapper.depositLiquidity(address(appStable), 100 * 10 ** 6);
        vm.stopPrank();
        
        // Try to swap more than available
        uint64 excessiveAmount = 1000 * 10 ** 6;
        
        vm.startPrank(wallet0);
        usdc.approve(address(swapper), excessiveAmount);
        vm.expectRevert();
        swapper.swap(address(usdc), address(appStable), excessiveAmount, excessiveAmount, wallet0);
        vm.stopPrank();
    }
    
    function test_swap_reverts_whenSlippageProtectionTriggered() public {
        setupBasicSwapEnvironment();
        
        // Set 5% fee
        vm.prank(operationsAuthority);
        swapper.updateFeeRate(500); // 5%
        
        uint64 swapAmount = 100 * 10 ** 6;
        uint64 minAmountOut = 98 * 10 ** 6; // Expect only 2% loss, but will get 5%
        
        vm.startPrank(wallet0);
        usdc.approve(address(swapper), swapAmount);
        vm.expectRevert(StableSwapper.SlippageExceeded.selector);
        swapper.swap(address(usdc), address(appStable), swapAmount, minAmountOut, wallet0);
        vm.stopPrank();
        
        // Reset fee
        vm.prank(operationsAuthority);
        swapper.updateFeeRate(0);
    }
    
    function test_swap_reverts_whenSwapAmountResultsInZeroOutput() public {
        vm.startPrank(operationsAuthority);
        swapper.addToken(address(usdc));
        swapper.addToken(address(appStable));
        
        usdc.approve(address(swapper), 500 * 10 ** 6);
        swapper.depositLiquidity(address(usdc), 500 * 10 ** 6);
        
        appStable.approve(address(swapper), 500 * 10 ** 6);
        swapper.depositLiquidity(address(appStable), 500 * 10 ** 6);
        
        // Set 1% fee
        swapper.updateFeeRate(100);
        vm.stopPrank();
        
        // Swap tiny amount that results in zero output
        // With 1% fee on amount 1: fee = (1 * 100 + 9999) / 10000 = 1
        // So amountInAfterFee = 1 - 1 = 0, which is rejected with CannotBeZeroAmount
        uint64 tinyAmount = 1;
        
        vm.startPrank(wallet0);
        usdc.approve(address(swapper), tinyAmount);
        vm.expectRevert(StableSwapper.CannotBeZeroAmount.selector);
        swapper.swap(address(usdc), address(appStable), tinyAmount, 0, wallet0);
        vm.stopPrank();
        
        // Reset fee
        vm.prank(operationsAuthority);
        swapper.updateFeeRate(0);
    }
    
    function test_swap_reverts_whenInputTokenDisabled() public {
        setupBasicSwapEnvironment();
        
        // Disable USDC
        vm.prank(pauseAuthority);
        swapper.updateTokenStatus(address(usdc), false);
        
        // Try to swap with disabled input token
        uint64 swapAmount = 10 * 10 ** 6;
        
        vm.startPrank(wallet0);
        usdc.approve(address(swapper), swapAmount);
        vm.expectRevert(abi.encodeWithSelector(StableSwapper.VaultMustBeEnabled.selector, address(usdc)));
        swapper.swap(address(usdc), address(appStable), swapAmount, swapAmount, wallet0);
        vm.stopPrank();
    }
    
    function test_swap_reverts_whenOutputTokenDisabled() public {
        setupBasicSwapEnvironment();
        
        // Disable USDC
        vm.prank(pauseAuthority);
        swapper.updateTokenStatus(address(usdc), false);
        
        // Try to swap to disabled output token
        uint64 swapAmount = 10 * 10 ** 6;
        
        vm.startPrank(wallet0);
        appStable.approve(address(swapper), swapAmount);
        vm.expectRevert(abi.encodeWithSelector(StableSwapper.VaultMustBeEnabled.selector, address(usdc)));
        swapper.swap(address(appStable), address(usdc), swapAmount, swapAmount, wallet0);
        vm.stopPrank();
    }
    
    /*//////////////////////////////////////////////////////////////
                            SUCCESS TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_swap_transfersTokensCorrectly_usdcToAppStable() public {
        setupBasicSwapEnvironment();
        
        uint64 swapAmount = 100 * 10 ** 6;
        uint64 minAmountOut = 100 * 10 ** 6; // 1:1 with 0% fee
        
        uint256 initialUserUsdc = usdc.balanceOf(wallet0);
        uint256 initialUserAppStable = appStable.balanceOf(wallet0);
        
        vm.startPrank(wallet0);
        usdc.approve(address(swapper), swapAmount);
        swapper.swap(address(usdc), address(appStable), swapAmount, minAmountOut, wallet0);
        vm.stopPrank();
        
        assertEq(usdc.balanceOf(wallet0), initialUserUsdc - swapAmount);
        assertEq(appStable.balanceOf(wallet0), initialUserAppStable + swapAmount);
    }
    
    function test_swap_transfersTokensCorrectly_appStableToUsdc() public {
        setupBasicSwapEnvironment();
        
        uint64 swapAmount = 50 * 10 ** 6;
        uint64 minAmountOut = 50 * 10 ** 6;
        
        uint256 initialUserUsdc = usdc.balanceOf(wallet0);
        uint256 initialUserAppStable = appStable.balanceOf(wallet0);
        
        vm.startPrank(wallet0);
        appStable.approve(address(swapper), swapAmount);
        swapper.swap(address(appStable), address(usdc), swapAmount, minAmountOut, wallet0);
        vm.stopPrank();
        
        assertEq(appStable.balanceOf(wallet0), initialUserAppStable - swapAmount);
        assertEq(usdc.balanceOf(wallet0), initialUserUsdc + swapAmount);
    }
    
    function test_swap_scalesCorrectly_from6To9Decimals() public {
        MockERC20 token9Dec = new MockERC20("9 Decimal Token", "TOK9", 9);
        token9Dec.mint(operationsAuthority, 1000 * 10 ** 9);
        
        vm.startPrank(operationsAuthority);
        swapper.addToken(address(usdc));
        swapper.addToken(address(token9Dec));
        
        usdc.approve(address(swapper), 500 * 10 ** 6);
        swapper.depositLiquidity(address(usdc), 500 * 10 ** 6);
        
        token9Dec.approve(address(swapper), 500 * 10 ** 9);
        swapper.depositLiquidity(address(token9Dec), 500 * 10 ** 9);
        vm.stopPrank();
        
        uint64 swapAmount = 100 * 10 ** 6; // 100 USDC (6 decimals)
        uint64 minAmountOut = 100 * 10 ** 9; // Expect 100 tokens (9 decimals)
        uint64 expectedOutput = 100 * 10 ** 9;
        
        uint256 initialUserUsdc = usdc.balanceOf(wallet0);
        
        vm.startPrank(wallet0);
        usdc.approve(address(swapper), swapAmount);
        swapper.swap(address(usdc), address(token9Dec), swapAmount, minAmountOut, wallet0);
        vm.stopPrank();
        
        assertEq(usdc.balanceOf(wallet0), initialUserUsdc - swapAmount);
        assertEq(token9Dec.balanceOf(wallet0), expectedOutput);
    }
    
    function test_swap_scalesCorrectly_from9To6Decimals() public {
        MockERC20 token9Dec = new MockERC20("9 Decimal Token", "TOK9", 9);
        token9Dec.mint(operationsAuthority, 1000 * 10 ** 9);
        token9Dec.mint(wallet0, 1000 * 10 ** 9);
        
        vm.startPrank(operationsAuthority);
        swapper.addToken(address(usdc));
        swapper.addToken(address(token9Dec));
        
        usdc.approve(address(swapper), 500 * 10 ** 6);
        swapper.depositLiquidity(address(usdc), 500 * 10 ** 6);
        
        token9Dec.approve(address(swapper), 500 * 10 ** 9);
        swapper.depositLiquidity(address(token9Dec), 500 * 10 ** 9);
        vm.stopPrank();
        
        uint64 swapAmount = 100 * 10 ** 9; // 100 tokens (9 decimals)
        uint64 minAmountOut = 100 * 10 ** 6; // Expect 100 USDC (6 decimals)
        uint256 initialUserUsdc = 1000 * 10 ** 6;
        uint256 expectedUsdc = 100 * 10 ** 6;
        
        uint256 initialUser9Dec = token9Dec.balanceOf(wallet0);
        
        vm.startPrank(wallet0);
        token9Dec.approve(address(swapper), swapAmount);
        swapper.swap(address(token9Dec), address(usdc), swapAmount, minAmountOut, wallet0);
        vm.stopPrank();
        
        assertEq(token9Dec.balanceOf(wallet0), initialUser9Dec - swapAmount);
        assertEq(usdc.balanceOf(wallet0), initialUserUsdc + expectedUsdc);
    }
    
    function test_swap_roundsDown_whenScalingFrom9To6Decimals() public {
        MockERC20 token9Dec = new MockERC20("9 Decimal Token", "TOK9", 9);
        token9Dec.mint(operationsAuthority, 1000 * 10 ** 9);
        token9Dec.mint(wallet0, 1000 * 10 ** 9);
        
        vm.startPrank(operationsAuthority);
        swapper.addToken(address(usdc));
        swapper.addToken(address(token9Dec));
        
        usdc.approve(address(swapper), 500 * 10 ** 6);
        swapper.depositLiquidity(address(usdc), 500 * 10 ** 6);
        
        token9Dec.approve(address(swapper), 500 * 10 ** 9);
        swapper.depositLiquidity(address(token9Dec), 500 * 10 ** 9);
        vm.stopPrank();
        
        // Amount with fractional part that will be rounded down
        uint64 swapAmount = 100_000_000_123; // 100.000000123 tokens
        uint64 minAmountOut = 99 * 10 ** 6;
        uint64 expectedRoundedAmount = 100_000_000;
        
        uint256 initialUserUsdc = usdc.balanceOf(wallet0);
        
        vm.startPrank(wallet0);
        token9Dec.approve(address(swapper), swapAmount);
        swapper.swap(address(token9Dec), address(usdc), swapAmount, minAmountOut, wallet0);
        vm.stopPrank();
        
        assertEq(usdc.balanceOf(wallet0), initialUserUsdc + expectedRoundedAmount);
    }
    
    function test_swap_transfersCorrectly_whenSameDecimals() public {
        setupBasicSwapEnvironment();
        
        uint64 swapAmount = 50 * 10 ** 6;
        
        uint256 initialUserUsdc = usdc.balanceOf(wallet0);
        uint256 initialUserAppStable = appStable.balanceOf(wallet0);
        
        vm.startPrank(wallet0);
        usdc.approve(address(swapper), swapAmount);
        swapper.swap(address(usdc), address(appStable), swapAmount, swapAmount, wallet0);
        vm.stopPrank();
        
        assertEq(usdc.balanceOf(wallet0), initialUserUsdc - swapAmount);
        assertEq(appStable.balanceOf(wallet0), initialUserAppStable + swapAmount);
    }
    
    function test_swap_respectsReservedAmount() public {
        vm.startPrank(operationsAuthority);
        swapper.addToken(address(usdc));
        swapper.addToken(address(appStable));
        
        usdc.approve(address(swapper), 500 * 10 ** 6);
        swapper.depositLiquidity(address(usdc), 500 * 10 ** 6);
        
        appStable.approve(address(swapper), 500 * 10 ** 6);
        swapper.depositLiquidity(address(appStable), 500 * 10 ** 6);
        
        // Set reserved amount on USDC
        swapper.updateReservedAmount(address(usdc), 450 * 10 ** 6);
        vm.stopPrank();
        
        // Try to swap more than available (balance - reserved)
        uint64 swapAmount = 100 * 10 ** 6;
        
        vm.startPrank(wallet0);
        appStable.approve(address(swapper), swapAmount);
        vm.expectRevert();
        swapper.swap(address(appStable), address(usdc), swapAmount, swapAmount, wallet0);
        vm.stopPrank();
    }
    
    function test_swap_collectsFeesCorrectly_whenFeeRateNonZero() public {
        setupBasicSwapEnvironment();
        
        // Set 1% fee
        vm.prank(operationsAuthority);
        swapper.updateFeeRate(100);
        
        uint64 swapAmount = 100 * 10 ** 6;
        uint64 expectedFee = 1 * 10 ** 6; // 1%
        uint64 expectedNet = 99 * 10 ** 6;
        uint64 minAmountOut = 99 * 10 ** 6;
        
        uint256 initialFeeRecipientBalance = usdc.balanceOf(feeRecipient);
        uint256 initialUserAppStable = appStable.balanceOf(wallet0);
        
        vm.startPrank(wallet0);
        usdc.approve(address(swapper), swapAmount);
        swapper.swap(address(usdc), address(appStable), swapAmount, minAmountOut, wallet0);
        vm.stopPrank();
        
        assertEq(usdc.balanceOf(feeRecipient), initialFeeRecipientBalance + expectedFee);
        assertEq(appStable.balanceOf(wallet0), initialUserAppStable + expectedNet);
        
        // Reset fee
        vm.prank(operationsAuthority);
        swapper.updateFeeRate(0);
    }
    
    function test_swap_skipsFees_whenFeeRateIsZero() public {
        setupBasicSwapEnvironment();
        
        uint64 swapAmount = 50 * 10 ** 6;
        
        uint256 initialUserUsdc = usdc.balanceOf(wallet0);
        uint256 initialUserAppStable = appStable.balanceOf(wallet0);
        
        vm.startPrank(wallet0);
        usdc.approve(address(swapper), swapAmount);
        swapper.swap(address(usdc), address(appStable), swapAmount, swapAmount, wallet0);
        vm.stopPrank();
        
        assertEq(usdc.balanceOf(wallet0), initialUserUsdc - swapAmount);
        assertEq(appStable.balanceOf(wallet0), initialUserAppStable + swapAmount);
    }
    
    function test_swap_roundsUpFees_whenFractionalAmount() public {
        setupBasicSwapEnvironment();
        
        // Set 1% fee
        vm.prank(operationsAuthority);
        swapper.updateFeeRate(100);
        
        // Test case 2: Another fractional fee example
        // 99_999 units with 1% fee = 99_999 * 100 / 10000 = 999.99
        // Without ceiling: 999 units fee
        // With ceiling: (99_999 * 100 + 9999) / 10000 = 1000 units fee
        // User receives: 99_999 - 1000 = 98_999 units
        uint64 swapAmount = 99_999;
        uint64 minAmountOut = 98_900;
        uint64 expectedFee = 1000;
        
        uint256 initialFeeRecipientBalance = usdc.balanceOf(feeRecipient);
        
        vm.startPrank(wallet0);
        usdc.approve(address(swapper), swapAmount);
        swapper.swap(address(usdc), address(appStable), swapAmount, minAmountOut, wallet0);
        vm.stopPrank();
        
        uint256 feeCollected = usdc.balanceOf(feeRecipient) - initialFeeRecipientBalance;
        
        assertEq(feeCollected, expectedFee, "Fee should round up to 1000 units from 999.99 units");
        
        // Reset fee
        vm.prank(operationsAuthority);
        swapper.updateFeeRate(0);
    }
    
    function test_swap_roundsUpFees_toPreventProtocolLoss() public {
        setupBasicSwapEnvironment();
        
        // Set 1% fee
        vm.prank(operationsAuthority);
        swapper.updateFeeRate(100);
        
        // Amount that creates fractional fee: 10050 * 1% = 100.5, rounds up to 101
        uint64 swapAmount = 10050;
        uint64 minAmountOut = 9900;
        uint64 expectedFee = 101;
        
        uint256 initialFeeRecipientBalance = usdc.balanceOf(feeRecipient);
        
        vm.startPrank(wallet0);
        usdc.approve(address(swapper), swapAmount);
        swapper.swap(address(usdc), address(appStable), swapAmount, minAmountOut, wallet0);
        vm.stopPrank();
        
        uint256 feeCollected = usdc.balanceOf(feeRecipient) - initialFeeRecipientBalance;
        assertEq(feeCollected, expectedFee);
        
        // Reset
        vm.prank(operationsAuthority);
        swapper.updateFeeRate(0);
    }
    
    function test_swap_doesNotOverChargeFees_whenPerfectFeeAmount() public {
        setupBasicSwapEnvironment();
        
        // Set 1% fee
        vm.prank(operationsAuthority);
        swapper.updateFeeRate(100);
        
        // Amount that creates perfect fee: 100 * 10^6 * 1% = 1 * 10^6 exactly
        uint64 swapAmount = 100 * 10 ** 6;
        uint64 minAmountOut = 99 * 10 ** 6;
        uint64 expectedFee = 1 * 10 ** 6;
        
        uint256 initialFeeRecipientBalance = usdc.balanceOf(feeRecipient);
        
        vm.startPrank(wallet0);
        usdc.approve(address(swapper), swapAmount);
        swapper.swap(address(usdc), address(appStable), swapAmount, minAmountOut, wallet0);
        vm.stopPrank();
        
        uint256 feeCollected = usdc.balanceOf(feeRecipient) - initialFeeRecipientBalance;
        assertEq(feeCollected, expectedFee);
        
        // Reset
        vm.prank(operationsAuthority);
        swapper.updateFeeRate(0);
    }
}

