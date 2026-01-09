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

    function test_swap_reverts_whenTokenInIsZeroAddress() public {
        uint64 swapAmount    = 10 * 10 ** 6;
        
        vm.startPrank(wallet0);
        usdc.approve(address(swapper), swapAmount);
        vm.expectRevert(abi.encodeWithSelector(StableSwapper.CannotBeZeroAddress.selector, address(0)));
        swapper.swap(address(0), address(appStable), swapAmount, swapAmount, wallet0);
        vm.stopPrank();
    }

    function test_swap_reverts_whenTokenOutIsZeroAddress() public {
        uint64 swapAmount = 10 * 10 ** 6;
        
        vm.startPrank(wallet0);
        usdc.approve(address(swapper), swapAmount);
        vm.expectRevert(abi.encodeWithSelector(StableSwapper.CannotBeZeroAddress.selector, address(0)));
        swapper.swap(address(usdc), address(0), swapAmount, swapAmount, wallet0);
        vm.stopPrank();
    }
    
    function test_swap_reverts_whenSwappingSameToken() public {
        uint64 liquidityAmount = 500 * 10 ** 6;
        uint64 swapAmount = 10 * 10 ** 6;
        
        vm.startPrank(operationsAuthority);
        swapper.addToken(address(usdc));
        
        usdc.approve(address(swapper), liquidityAmount);
        swapper.depositLiquidity(address(usdc), liquidityAmount);
        vm.stopPrank();
        
        vm.startPrank(wallet0);
        usdc.approve(address(swapper), swapAmount);
        // Should fail - cannot swap a token for itself
        vm.expectRevert(abi.encodeWithSelector(StableSwapper.CannotSwapSameToken.selector, address(usdc)));
        swapper.swap(address(usdc), address(usdc), swapAmount, swapAmount, wallet0);
        vm.stopPrank();
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

    function test_swap_reverts_whenAmountInIsZero() public {
        setupBasicSwapEnvironment();
        
        uint64 swapAmount = 10 * 10 ** 6;
        uint64 minAmountOut = 10 * 10 ** 6;
        
        vm.startPrank(wallet0);
        usdc.approve(address(swapper), swapAmount);
        vm.expectRevert(abi.encodeWithSelector(StableSwapper.CannotBeZeroAmount.selector));
        swapper.swap(address(usdc), address(appStable), 0, minAmountOut, wallet0);
        vm.stopPrank();
    }
    
    function test_swap_reverts_whenMinAmountOutIsZero() public {
        setupBasicSwapEnvironment();
        
        uint64 swapAmount = 10 * 10 ** 6;
        
        vm.startPrank(wallet0);
        usdc.approve(address(swapper), swapAmount);
        vm.expectRevert(abi.encodeWithSelector(StableSwapper.CannotBeZeroAmount.selector));
        swapper.swap(address(usdc), address(appStable), swapAmount, 0, wallet0);
        vm.stopPrank();
    }

    function test_swap_reverts_whenTokenInVaultIsNotEnabled() public {
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
    
    function test_swap_reverts_whenTokenOutVaultIsNotEnabled() public {
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

    function testFuzz_swap_reverts_whenSwapAmountResultsInZeroOutput(uint256 feeRateSeed, uint256 liquidityAmountSeed, uint256 tinyAmountSeed) public {
        uint64 liquidityAmount = uint64(bound(liquidityAmountSeed, 10000, 1000 * 10 ** 6));
        uint64 feeRateBps = uint64(bound(feeRateSeed, 1, 1000));
        
        // Calculate the maximum tinyAmount that will result in zero output after fees
        // Fee formula: fee = (amountIn * feeRateBps + 9999) / 10000
        // For output to be zero: amountIn - fee = 0, so amountIn = fee
        // This means: amountIn = (amountIn * feeRateBps + 9999) / 10000
        // Solving: amountIn * 10000 = amountIn * feeRateBps + 9999
        // amountIn * 10000 - amountIn * feeRateBps = 9999
        // amountIn * (10000 - feeRateBps) = 9999
        // amountIn = 9999 / (10000 - feeRateBps)
        // 
        // For amountIn to result in zero after fees, we need amountIn <= 9999 / (10000 - feeRateBps)
        uint64 maxTinyAmount = uint64(9999 / (10000 - feeRateBps));
        
        // Ensure maxTinyAmount is at least 1
        if (maxTinyAmount < 1) maxTinyAmount = 1;
        
        uint64 tinyAmount = uint64(bound(tinyAmountSeed, 1, maxTinyAmount));
        
        vm.startPrank(operationsAuthority);
        swapper.addToken(address(usdc));
        swapper.addToken(address(appStable));
        
        usdc.approve(address(swapper), liquidityAmount);
        swapper.depositLiquidity(address(usdc), liquidityAmount);
        
        appStable.approve(address(swapper), liquidityAmount);
        swapper.depositLiquidity(address(appStable), liquidityAmount);
        
        swapper.updateFeeRate(feeRateBps);
        vm.stopPrank();
        
        vm.startPrank(wallet0);
        usdc.approve(address(swapper), tinyAmount);
        vm.expectRevert(StableSwapper.AmountOutCannotBeZero.selector);
        swapper.swap(address(usdc), address(appStable), tinyAmount, 1, wallet0);
        vm.stopPrank();
        
        // Reset fee
        vm.prank(operationsAuthority);
        swapper.updateFeeRate(0);
    }
    
    function testFuzz_swap_reverts_whenSlippageProtectionTriggered(uint256 swapAmountSeed, uint256 feeRateSeed, uint256 minAmountOutSeed) public {
        setupBasicSwapEnvironment();
        
        uint64 feeRateBps = uint64(bound(feeRateSeed, 1, 1000));
        // Ensure swapAmount is large enough that after max fee (1000 bps = 10%), amountOut > 0
        // Min value: 10001 ensures even at 10% fee, we get at least 1 token out
        uint64 swapAmount = uint64(bound(swapAmountSeed, 10001, 1000 * 10 ** 6));
        
        // Calculate the actual amount out after fees: amountOut = swapAmount * (10000 - feeRateBps) / 10000
        uint64 expectedAmountOut = uint64((uint256(swapAmount) * (10000 - feeRateBps)) / 10000);
        
        // Set minAmountOut to be greater than expectedAmountOut to trigger slippage protection
        // Bound it between expectedAmountOut + 1 and swapAmount (the theoretical maximum)
        uint64 minAmountOut = uint64(bound(minAmountOutSeed, expectedAmountOut + 1, swapAmount));
        
        vm.prank(operationsAuthority);
        swapper.updateFeeRate(feeRateBps);
        
        vm.startPrank(wallet0);
        usdc.approve(address(swapper), swapAmount);
        vm.expectRevert(StableSwapper.SlippageExceeded.selector);
        swapper.swap(address(usdc), address(appStable), swapAmount, minAmountOut, wallet0);
        vm.stopPrank();
        
        // Reset fee
        vm.prank(operationsAuthority);
        swapper.updateFeeRate(0);
    }

    function testFuzz_swap_reverts_whenInsufficientLiquidity(uint256 limitedLiquiditySeed, uint256 excessiveSwapAmountSeed) public {
        uint64 limitedLiquidity = uint64(bound(limitedLiquiditySeed, 1, 1000 * 10 ** 6));
        uint64 excessiveSwapAmount = uint64(bound(excessiveSwapAmountSeed, limitedLiquidity + 1, 10000 * 10 ** 6));
        
        vm.startPrank(operationsAuthority);
        swapper.addToken(address(usdc));
        swapper.addToken(address(appStable));
        
        // Deposit limited liquidity
        usdc.approve(address(swapper), limitedLiquidity);
        swapper.depositLiquidity(address(usdc), limitedLiquidity);
        
        appStable.approve(address(swapper), limitedLiquidity);
        swapper.depositLiquidity(address(appStable), limitedLiquidity);
        vm.stopPrank();
        
        // Try to swap more than available
        vm.startPrank(wallet0);
        usdc.approve(address(swapper), excessiveSwapAmount);
        vm.expectRevert(abi.encodeWithSelector(StableSwapper.AmountOutExceedsAvailableLiquidity.selector, excessiveSwapAmount, limitedLiquidity));
        swapper.swap(address(usdc), address(appStable), excessiveSwapAmount, excessiveSwapAmount, wallet0);
        vm.stopPrank();
    }

    function testFuzz_swap_reverts_whenTokenOutExceedsReservedAmount(uint256 depositedLiquiditySeed, uint256 reservedAmountSeed, uint256 swapAmountSeed) public {
        uint64 depositedLiquidity = uint64(bound(depositedLiquiditySeed, 1, 1000 * 10 ** 6));
        uint64 reservedAmount = uint64(bound(reservedAmountSeed, 1, depositedLiquidity));
        uint64 availableLiquidity = depositedLiquidity - reservedAmount;
        uint64 swapAmount = uint64(bound(swapAmountSeed, availableLiquidity + 1, type(uint64).max));
        
        vm.startPrank(operationsAuthority);
        swapper.addToken(address(usdc));
        swapper.addToken(address(appStable));
        
        usdc.approve(address(swapper), depositedLiquidity);
        swapper.depositLiquidity(address(usdc), depositedLiquidity);
        
        appStable.approve(address(swapper), depositedLiquidity);
        swapper.depositLiquidity(address(appStable), depositedLiquidity);
        
        // Set reserved amount on USDC
        swapper.updateReservedAmount(address(usdc), reservedAmount);
        vm.stopPrank();
        
        // Try to swap more than available (balance - reserved)
        vm.startPrank(wallet0);
        appStable.approve(address(swapper), swapAmount);
        vm.expectRevert(abi.encodeWithSelector(StableSwapper.AmountOutExceedsAvailableLiquidity.selector, swapAmount, availableLiquidity));
        swapper.swap(address(appStable), address(usdc), swapAmount, swapAmount, wallet0);
        vm.stopPrank();
    }
    
    /*//////////////////////////////////////////////////////////////
                            SUCCESS TESTS
    //////////////////////////////////////////////////////////////*/
    
    function testFuzz_swap_transfersTokensCorrectly_usdcToAppStable(uint256 swapAmountSeed, uint256 minAmountOutSeed) public {
        setupBasicSwapEnvironment();

        uint64 swapAmount = uint64(bound(swapAmountSeed, 1, 500 * 10 ** 6));
        uint64 minAmountOut = uint64(bound(minAmountOutSeed, 1, swapAmount));
        
        uint256 initialUserUsdc = usdc.balanceOf(wallet0);
        uint256 initialUserAppStable = appStable.balanceOf(wallet0);
        
        vm.startPrank(wallet0);
        usdc.approve(address(swapper), swapAmount);
        swapper.swap(address(usdc), address(appStable), swapAmount, minAmountOut, wallet0);
        vm.stopPrank();
        
        assertEq(usdc.balanceOf(wallet0), initialUserUsdc - swapAmount);
        assertEq(appStable.balanceOf(wallet0), initialUserAppStable + swapAmount);
    }
    
    function testFuzz_swap_transfersTokensCorrectly_appStableToUsdc(uint256 swapAmountSeed, uint256 minAmountOutSeed) public {
        setupBasicSwapEnvironment();
        
        uint64 swapAmount = uint64(bound(swapAmountSeed, 1, 500 * 10 ** 6));
        uint64 minAmountOut = uint64(bound(minAmountOutSeed, 1, swapAmount));
        
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
        uint256 initialMint = 1000 * 10 ** 9;
        uint64 liquidityAmount6Dec = 500 * 10 ** 6;
        uint64 liquidityAmount9Dec = 500 * 10 ** 9;
        uint64 swapAmount = 100 * 10 ** 6; // 100 USDC (6 decimals)
        uint64 minAmountOut = 100 * 10 ** 9; // Expect 100 tokens (9 decimals)
        uint64 expectedOutput = 100 * 10 ** 9;
        
        MockERC20 token9Dec = new MockERC20("9 Decimal Token", "TOK9", 9);
        token9Dec.mint(operationsAuthority, initialMint);
        
        vm.startPrank(operationsAuthority);
        swapper.addToken(address(usdc));
        swapper.addToken(address(token9Dec));
        
        usdc.approve(address(swapper), liquidityAmount6Dec);
        swapper.depositLiquidity(address(usdc), liquidityAmount6Dec);
        
        token9Dec.approve(address(swapper), liquidityAmount9Dec);
        swapper.depositLiquidity(address(token9Dec), liquidityAmount9Dec);
        vm.stopPrank();
        
        uint256 initialUserUsdc = usdc.balanceOf(wallet0);
        
        vm.startPrank(wallet0);
        usdc.approve(address(swapper), swapAmount);
        swapper.swap(address(usdc), address(token9Dec), swapAmount, minAmountOut, wallet0);
        vm.stopPrank();
        
        assertEq(usdc.balanceOf(wallet0), initialUserUsdc - swapAmount);
        assertEq(token9Dec.balanceOf(wallet0), expectedOutput);
    }
    
    function test_swap_scalesCorrectly_from9To6Decimals() public {
        uint256 initialMint = 1000 * 10 ** 9;
        uint64 liquidityAmount6Dec = 500 * 10 ** 6;
        uint64 liquidityAmount9Dec = 500 * 10 ** 9;
        uint64 swapAmount = 100 * 10 ** 9; // 100 tokens (9 decimals)
        uint64 minAmountOut = 100 * 10 ** 6; // Expect 100 USDC (6 decimals)
        uint256 initialUserUsdc = 1000 * 10 ** 6;
        uint256 expectedUsdc = 100 * 10 ** 6;
        
        MockERC20 token9Dec = new MockERC20("9 Decimal Token", "TOK9", 9);
        token9Dec.mint(operationsAuthority, initialMint);
        token9Dec.mint(wallet0, initialMint);
        
        vm.startPrank(operationsAuthority);
        swapper.addToken(address(usdc));
        swapper.addToken(address(token9Dec));
        
        usdc.approve(address(swapper), liquidityAmount6Dec);
        swapper.depositLiquidity(address(usdc), liquidityAmount6Dec);
        
        token9Dec.approve(address(swapper), liquidityAmount9Dec);
        swapper.depositLiquidity(address(token9Dec), liquidityAmount9Dec);
        vm.stopPrank();
        
        uint256 initialUser9Dec = token9Dec.balanceOf(wallet0);
        
        vm.startPrank(wallet0);
        token9Dec.approve(address(swapper), swapAmount);
        swapper.swap(address(token9Dec), address(usdc), swapAmount, minAmountOut, wallet0);
        vm.stopPrank();
        
        assertEq(token9Dec.balanceOf(wallet0), initialUser9Dec - swapAmount);
        assertEq(usdc.balanceOf(wallet0), initialUserUsdc + expectedUsdc);
    }
    
    function test_swap_roundsDown_whenScalingFrom9To6Decimals() public {
        uint256 initialMint = 1000 * 10 ** 9;
        uint64 liquidityAmount6Dec = 500 * 10 ** 6;
        uint64 liquidityAmount9Dec = 500 * 10 ** 9;
        uint64 swapAmount = 100_000_000_123; // 100.000000123 tokens (fractional part will be rounded down)
        uint64 minAmountOut = 99 * 10 ** 6;
        uint64 expectedRoundedAmount = 100_000_000;
        
        MockERC20 token9Dec = new MockERC20("9 Decimal Token", "TOK9", 9);
        token9Dec.mint(operationsAuthority, initialMint);
        token9Dec.mint(wallet0, initialMint);
        
        vm.startPrank(operationsAuthority);
        swapper.addToken(address(usdc));
        swapper.addToken(address(token9Dec));
        
        usdc.approve(address(swapper), liquidityAmount6Dec);
        swapper.depositLiquidity(address(usdc), liquidityAmount6Dec);
        
        token9Dec.approve(address(swapper), liquidityAmount9Dec);
        swapper.depositLiquidity(address(token9Dec), liquidityAmount9Dec);
        vm.stopPrank();
        
        uint256 initialUserUsdc = usdc.balanceOf(wallet0);
        
        vm.startPrank(wallet0);
        token9Dec.approve(address(swapper), swapAmount);
        swapper.swap(address(token9Dec), address(usdc), swapAmount, minAmountOut, wallet0);
        vm.stopPrank();
        
        assertEq(usdc.balanceOf(wallet0), initialUserUsdc + expectedRoundedAmount);
    }
    
    function test_swap_collectsFeesCorrectly_whenFeeRateNonZero() public {
        setupBasicSwapEnvironment();
        
        uint64 feeRateBps = 100; // 1% fee in basis points
        uint64 swapAmount = 100 * 10 ** 6;
        uint64 expectedFee = 1 * 10 ** 6; // 1%
        uint64 expectedNetOutput = 99 * 10 ** 6;
        uint64 minAmountOut = 99 * 10 ** 6;
        
        vm.prank(operationsAuthority);
        swapper.updateFeeRate(feeRateBps);
        
        uint256 initialFeeRecipientBalance = usdc.balanceOf(feeRecipient);
        uint256 initialUserAppStable = appStable.balanceOf(wallet0);
        
        vm.startPrank(wallet0);
        usdc.approve(address(swapper), swapAmount);
        swapper.swap(address(usdc), address(appStable), swapAmount, minAmountOut, wallet0);
        vm.stopPrank();
        
        assertEq(usdc.balanceOf(feeRecipient), initialFeeRecipientBalance + expectedFee);
        assertEq(appStable.balanceOf(wallet0), initialUserAppStable + expectedNetOutput);
        
        // Reset fee
        vm.prank(operationsAuthority);
        swapper.updateFeeRate(0);
    }
    
    function test_swap_skipsFees_whenFeeRateIsZero() public {
        setupBasicSwapEnvironment();
        
        uint64 swapAmount = 50 * 10 ** 6;
        uint64 minAmountOut = 50 * 10 ** 6;
        uint64 expectedOutput = 50 * 10 ** 6;
        
        uint256 initialUserUsdc = usdc.balanceOf(wallet0);
        uint256 initialUserAppStable = appStable.balanceOf(wallet0);
        
        vm.startPrank(wallet0);
        usdc.approve(address(swapper), swapAmount);
        swapper.swap(address(usdc), address(appStable), swapAmount, minAmountOut, wallet0);
        vm.stopPrank();
        
        assertEq(usdc.balanceOf(wallet0), initialUserUsdc - swapAmount);
        assertEq(appStable.balanceOf(wallet0), initialUserAppStable + expectedOutput);
    }
    
    function test_swap_roundsUpFees_whenFractionalAmount() public {
        setupBasicSwapEnvironment();
        
        uint64 feeRateBps = 100; // 1% fee in basis points
        // 99_999 units with 1% fee = 99_999 * 100 / 10000 = 999.99
        // Without ceiling: 999 units fee
        // With ceiling: (99_999 * 100 + 9999) / 10000 = 1000 units fee
        // User receives: 99_999 - 1000 = 98_999 units
        uint64 swapAmount = 99_999;
        uint64 minAmountOut = 98_900;
        uint64 expectedFee = 1000;
        
        vm.prank(operationsAuthority);
        swapper.updateFeeRate(feeRateBps);
        
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
    
    function test_swap_doesNotOverChargeFees_whenPerfectFeeAmount() public {
        setupBasicSwapEnvironment();
        
        uint64 feeRateBps = 100; // 1% fee in basis points
        // Amount that creates perfect fee: 100 * 10^6 * 1% = 1 * 10^6 exactly
        uint64 swapAmount = 100 * 10 ** 6;
        uint64 minAmountOut = 99 * 10 ** 6;
        uint64 expectedFee = 1 * 10 ** 6;
        
        vm.prank(operationsAuthority);
        swapper.updateFeeRate(feeRateBps);
        
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

