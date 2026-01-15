// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {StableSwapper} from "../../src/StableSwapper.sol";
import {MockERC20, StableSwapperBase} from "./StableSwapperBase.sol";

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
        swapper.setFeatureFlag(StableSwapper.FeatureFlag.SWAP, false);

        uint256 swapAmount = 10 * 10 ** 6;

        vm.startPrank(wallet0);
        usdc.approve(address(swapper), swapAmount);
        vm.expectRevert(StableSwapper.SwapsCannotBePaused.selector);
        swapper.swap(address(usdc), address(appStable), swapAmount, swapAmount, wallet0);
        vm.stopPrank();

        vm.prank(pauseAuthority);
        swapper.setFeatureFlag(StableSwapper.FeatureFlag.SWAP, true);
    }

    function test_swap_reverts_whenTokenInIsZeroAddress() public {
        uint256 swapAmount = 10 * 10 ** 6;

        vm.startPrank(wallet0);
        usdc.approve(address(swapper), swapAmount);
        vm.expectRevert(StableSwapper.CannotBeZeroAddress.selector);
        swapper.swap(address(0), address(appStable), swapAmount, swapAmount, wallet0);
        vm.stopPrank();
    }

    function test_swap_reverts_whenTokenOutIsZeroAddress() public {
        uint256 swapAmount = 10 * 10 ** 6;

        vm.startPrank(wallet0);
        usdc.approve(address(swapper), swapAmount);
        vm.expectRevert(StableSwapper.CannotBeZeroAddress.selector);
        swapper.swap(address(usdc), address(0), swapAmount, swapAmount, wallet0);
        vm.stopPrank();
    }

    function test_swap_reverts_whenSwappingSameToken() public {
        uint256 liquidityAmount = 500 * 10 ** 6;
        uint256 swapAmount = 10 * 10 ** 6;

        vm.prank(configureAuthority);
        swapper.listToken(address(usdc));

        vm.prank(withdrawalAuthority);
        usdc.transfer(address(swapper), liquidityAmount);

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
        uint256 swapAmount = 10 * 10 ** 6;

        vm.startPrank(wallet0);
        usdc.approve(address(swapper), swapAmount);
        vm.expectRevert(abi.encodeWithSelector(StableSwapper.TokenMustBeSwappable.selector, address(usdc)));
        swapper.swap(address(usdc), address(appStable), swapAmount, swapAmount, wallet0);
        vm.stopPrank();
    }

    function test_swap_reverts_whenOutputTokenDisabled() public {
        setupBasicSwapEnvironment();

        // Disable USDC
        vm.prank(pauseAuthority);
        swapper.updateTokenStatus(address(usdc), false);

        // Try to swap to disabled output token
        uint256 swapAmount = 10 * 10 ** 6;

        vm.startPrank(wallet0);
        appStable.approve(address(swapper), swapAmount);
        vm.expectRevert(abi.encodeWithSelector(StableSwapper.TokenMustBeSwappable.selector, address(usdc)));
        swapper.swap(address(appStable), address(usdc), swapAmount, swapAmount, wallet0);
        vm.stopPrank();
    }

    function test_swap_reverts_whenAmountInIsZero() public {
        setupBasicSwapEnvironment();

        uint256 swapAmount = 10 * 10 ** 6;
        uint256 minAmountOut = 10 * 10 ** 6;

        vm.startPrank(wallet0);
        usdc.approve(address(swapper), swapAmount);
        vm.expectRevert(StableSwapper.CannotBeZeroAmount.selector);
        swapper.swap(address(usdc), address(appStable), 0, minAmountOut, wallet0);
        vm.stopPrank();
    }

    function test_swap_reverts_whenMinAmountOutIsZero() public {
        setupBasicSwapEnvironment();

        uint256 swapAmount = 10 * 10 ** 6;

        vm.startPrank(wallet0);
        usdc.approve(address(swapper), swapAmount);
        vm.expectRevert(StableSwapper.CannotBeZeroAmount.selector);
        swapper.swap(address(usdc), address(appStable), swapAmount, 0, wallet0);
        vm.stopPrank();
    }

    function test_swap_reverts_whenTokenInVaultIsNotEnabled() public {
        setupBasicSwapEnvironment();

        // Disable USDC
        vm.prank(pauseAuthority);
        swapper.updateTokenStatus(address(usdc), false);

        // Try to swap with disabled input token
        uint256 swapAmount = 10 * 10 ** 6;

        vm.startPrank(wallet0);
        usdc.approve(address(swapper), swapAmount);
        vm.expectRevert(abi.encodeWithSelector(StableSwapper.TokenMustBeSwappable.selector, address(usdc)));
        swapper.swap(address(usdc), address(appStable), swapAmount, swapAmount, wallet0);
        vm.stopPrank();
    }

    function test_swap_reverts_whenTokenOutVaultIsNotEnabled() public {
        setupBasicSwapEnvironment();

        // Disable USDC
        vm.prank(pauseAuthority);
        swapper.updateTokenStatus(address(usdc), false);

        // Try to swap to disabled output token
        uint256 swapAmount = 10 * 10 ** 6;

        vm.startPrank(wallet0);
        appStable.approve(address(swapper), swapAmount);
        vm.expectRevert(abi.encodeWithSelector(StableSwapper.TokenMustBeSwappable.selector, address(usdc)));
        swapper.swap(address(appStable), address(usdc), swapAmount, swapAmount, wallet0);
        vm.stopPrank();
    }

    function testFuzz_swap_reverts_whenFeeNumeratorOverflows(uint256 feeRateSeed, uint256 amountSeed) public {
        setupBasicSwapEnvironment();

        // Bound fee rate to valid range [2, MAX_FEE_RATE]
        // Must be at least 2 to avoid edge case where (max/1)+1 wraps to 0
        uint16 feeRate = uint16(bound(feeRateSeed, 2, 1000));

        vm.prank(configureAuthority);
        swapper.updateFeeBasisPoints(feeRate);

        // To cause overflow in feeNumerator calculation (line 348):
        // feeNumerator = amountIn * feeRate
        // We need: amountIn * feeRate > type(uint256).max
        // Calculate the maximum safe amount, then use any value above it
        uint256 maxSafeAmount = type(uint256).max / feeRate;
        uint256 amountThatCausesOverflow = bound(amountSeed, maxSafeAmount + 1, type(uint256).max);

        // Deal tokens to wallet0 (we can't actually transfer this much, but we can mock the balance)
        deal(address(usdc), wallet0, amountThatCausesOverflow);

        // Expect panic with code 0x11 (arithmetic overflow) when swap tries to calculate feeNumerator
        vm.startPrank(wallet0);
        usdc.approve(address(swapper), amountThatCausesOverflow);
        vm.expectRevert(abi.encodeWithSignature("Panic(uint256)", 0x11));
        swapper.swap(address(usdc), address(appStable), amountThatCausesOverflow, 1, wallet0);
        vm.stopPrank();
    }

    function testFuzz_swap_reverts_whenBalanceBelowReservedAmount(
        uint256 initialLiquiditySeed,
        uint256 reservedAmountSeed,
        uint256 withdrawAmountSeed,
        uint256 swapAmountSeed
    ) public {
        // Setup: Add tokens and deposit liquidity
        // Bound to realistic token amounts (1 to 1000 tokens with 6 decimals)
        uint256 initialLiquidity = bound(initialLiquiditySeed, 100 * 10 ** 6, 1000 * 10 ** 6);

        // Reserved amount must be less than initial liquidity
        uint256 reservedAmount = bound(reservedAmountSeed, 1, initialLiquidity - 1);

        // Withdraw amount must leave balance < reserved amount
        // Calculate: initialLiquidity - withdrawAmount < reservedAmount
        // Therefore: withdrawAmount > initialLiquidity - reservedAmount
        uint256 minWithdraw = initialLiquidity - reservedAmount + 1;
        uint256 withdrawAmount = bound(withdrawAmountSeed, minWithdraw, initialLiquidity);

        // Swap amount can be any reasonable amount
        uint256 swapAmount = bound(swapAmountSeed, 1, 100 * 10 ** 6);

        vm.startPrank(configureAuthority);
        swapper.listToken(address(usdc));
        swapper.listToken(address(appStable));
        vm.stopPrank();

        vm.startPrank(pauseAuthority);
        swapper.updateTokenStatus(address(usdc), true);
        swapper.updateTokenStatus(address(appStable), true);
        vm.stopPrank();

        vm.startPrank(withdrawalAuthority);
        usdc.transfer(address(swapper), initialLiquidity);
        appStable.transfer(address(swapper), initialLiquidity);

        // Set reserved amount on appStable
        swapper.updateReservedAmount(address(appStable), reservedAmount);

        // Withdraw liquidity below the reserved amount
        // This leaves balance < reservedAmount, triggering the check at line 364
        swapper.withdrawLiquidity(address(appStable), withdrawAmount, withdrawalAuthority);
        vm.stopPrank();

        // Verify the balance is now below reserved amount
        uint256 currentBalance = appStable.balanceOf(address(swapper));
        assertLt(currentBalance, reservedAmount, "Balance should be less than reserved amount");

        // Try to swap USDC -> APPSTABLE, should revert because balance <= reserved amount
        vm.startPrank(wallet0);
        usdc.approve(address(swapper), swapAmount);
        vm.expectRevert(
            abi.encodeWithSelector(StableSwapper.TokenOutBalanceLessThanReservedAmount.selector, address(appStable))
        );
        swapper.swap(address(usdc), address(appStable), swapAmount, swapAmount, wallet0);
        vm.stopPrank();
    }

    function testFuzz_swap_reverts_whenSwapAmountResultsInZeroOutput(
        uint256 feeRateSeed,
        uint256 liquidityAmountSeed,
        uint256 tinyAmountSeed
    ) public {
        uint256 liquidityAmount = bound(liquidityAmountSeed, 10000, 1000 * 10 ** 6);
        uint16 feeRateBps = uint16(bound(feeRateSeed, 1, 1000));

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
        uint256 maxTinyAmount = 9999 / (10000 - feeRateBps);

        // Ensure maxTinyAmount is at least 1
        if (maxTinyAmount < 1) maxTinyAmount = 1;

        uint256 tinyAmount = bound(tinyAmountSeed, 1, maxTinyAmount);

        vm.startPrank(configureAuthority);
        swapper.listToken(address(usdc));
        swapper.listToken(address(appStable));
        swapper.updateFeeBasisPoints(feeRateBps);
        vm.stopPrank();

        vm.startPrank(pauseAuthority);
        swapper.updateTokenStatus(address(usdc), true);
        swapper.updateTokenStatus(address(appStable), true);
        vm.stopPrank();

        vm.startPrank(withdrawalAuthority);
        usdc.transfer(address(swapper), liquidityAmount);
        appStable.transfer(address(swapper), liquidityAmount);
        vm.stopPrank();

        vm.startPrank(wallet0);
        usdc.approve(address(swapper), tinyAmount);
        vm.expectRevert(StableSwapper.AmountOutCannotBeZero.selector);
        swapper.swap(address(usdc), address(appStable), tinyAmount, 1, wallet0);
        vm.stopPrank();

        // Reset fee
        vm.prank(configureAuthority);
        swapper.updateFeeBasisPoints(0);
    }

    function testFuzz_swap_reverts_whenSlippageProtectionTriggered(
        uint256 swapAmountSeed,
        uint256 feeRateSeed,
        uint256 minAmountOutSeed
    ) public {
        setupBasicSwapEnvironment();

        uint16 feeRateBps = uint16(bound(feeRateSeed, 1, 1000));
        // Ensure swapAmount is large enough that after max fee (1000 bps = 10%), amountOut > 0
        // Min value: 10001 ensures even at 10% fee, we get at least 1 token out
        uint256 swapAmount = bound(swapAmountSeed, 10001, 1000 * 10 ** 6);

        // Calculate the actual amount out after fees: amountOut = swapAmount * (10000 - feeRateBps) / 10000
        uint256 expectedAmountOut = (swapAmount * (10000 - feeRateBps)) / 10000;

        // Set minAmountOut to be greater than expectedAmountOut to trigger slippage protection
        // Bound it between expectedAmountOut + 1 and swapAmount (the theoretical maximum)
        uint256 minAmountOut = bound(minAmountOutSeed, expectedAmountOut + 1, swapAmount);

        vm.prank(configureAuthority);
        swapper.updateFeeBasisPoints(feeRateBps);

        vm.startPrank(wallet0);
        usdc.approve(address(swapper), swapAmount);
        vm.expectRevert(StableSwapper.SlippageExceeded.selector);
        swapper.swap(address(usdc), address(appStable), swapAmount, minAmountOut, wallet0);
        vm.stopPrank();

        // Reset fee
        vm.prank(configureAuthority);
        swapper.updateFeeBasisPoints(0);
    }

    function testFuzz_swap_reverts_whenInsufficientLiquidity(
        uint256 limitedLiquiditySeed,
        uint256 excessiveSwapAmountSeed
    ) public {
        uint256 limitedLiquidity = bound(limitedLiquiditySeed, 1, 1000 * 10 ** 6);
        uint256 excessiveSwapAmount = bound(excessiveSwapAmountSeed, limitedLiquidity + 1, 10000 * 10 ** 6);

        // Add tokens
        vm.startPrank(configureAuthority);
        swapper.listToken(address(usdc));
        swapper.listToken(address(appStable));
        vm.stopPrank();

        vm.startPrank(pauseAuthority);
        swapper.updateTokenStatus(address(usdc), true);
        swapper.updateTokenStatus(address(appStable), true);
        vm.stopPrank();

        // Deposit limited liquidity
        vm.startPrank(withdrawalAuthority);
        usdc.transfer(address(swapper), limitedLiquidity);
        appStable.transfer(address(swapper), limitedLiquidity);
        vm.stopPrank();

        // Try to swap more than available
        vm.startPrank(wallet0);
        usdc.approve(address(swapper), excessiveSwapAmount);
        vm.expectRevert(
            abi.encodeWithSelector(
                StableSwapper.AmountOutExceedsAvailableLiquidity.selector, excessiveSwapAmount, limitedLiquidity
            )
        );
        swapper.swap(address(usdc), address(appStable), excessiveSwapAmount, excessiveSwapAmount, wallet0);
        vm.stopPrank();
    }

    function testFuzz_swap_reverts_whenTokenOutExceedsReservedAmount(
        uint256 depositedLiquiditySeed,
        uint256 reservedAmountSeed,
        uint256 swapAmountSeed
    ) public {
        uint256 depositedLiquidity = bound(depositedLiquiditySeed, 1, 1000 * 10 ** 6);
        uint256 reservedAmount = bound(reservedAmountSeed, 1, depositedLiquidity);
        uint256 availableLiquidity = depositedLiquidity - reservedAmount;
        uint256 swapAmount = bound(swapAmountSeed, availableLiquidity + 1, type(uint256).max);

        // Add tokens
        vm.startPrank(configureAuthority);
        swapper.listToken(address(usdc));
        swapper.listToken(address(appStable));
        vm.stopPrank();

        vm.startPrank(pauseAuthority);
        swapper.updateTokenStatus(address(usdc), true);
        swapper.updateTokenStatus(address(appStable), true);
        vm.stopPrank();

        vm.startPrank(withdrawalAuthority);
        usdc.transfer(address(swapper), depositedLiquidity);
        appStable.transfer(address(swapper), depositedLiquidity);

        // Set reserved amount on USDC
        swapper.updateReservedAmount(address(usdc), reservedAmount);
        vm.stopPrank();

        // Try to swap more than available (balance - reserved)
        vm.startPrank(wallet0);
        appStable.approve(address(swapper), swapAmount);
        vm.expectRevert(
            abi.encodeWithSelector(
                StableSwapper.AmountOutExceedsAvailableLiquidity.selector, swapAmount, availableLiquidity
            )
        );
        swapper.swap(address(appStable), address(usdc), swapAmount, swapAmount, wallet0);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                            SUCCESS TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_swap_transfersTokensCorrectly_usdcToAppStable(uint256 swapAmountSeed, uint256 minAmountOutSeed)
        public
    {
        setupBasicSwapEnvironment();

        uint256 swapAmount = bound(swapAmountSeed, 1, 500 * 10 ** 6);
        uint256 minAmountOut = bound(minAmountOutSeed, 1, swapAmount);

        uint256 initialUserUsdc = usdc.balanceOf(wallet0);
        uint256 initialUserAppStable = appStable.balanceOf(wallet0);

        vm.startPrank(wallet0);
        usdc.approve(address(swapper), swapAmount);
        swapper.swap(address(usdc), address(appStable), swapAmount, minAmountOut, wallet0);
        vm.stopPrank();

        assertEq(usdc.balanceOf(wallet0), initialUserUsdc - swapAmount);
        assertEq(appStable.balanceOf(wallet0), initialUserAppStable + swapAmount);
    }

    function testFuzz_swap_transfersTokensCorrectly_appStableToUsdc(uint256 swapAmountSeed, uint256 minAmountOutSeed)
        public
    {
        setupBasicSwapEnvironment();

        uint256 swapAmount = bound(swapAmountSeed, 1, 500 * 10 ** 6);
        uint256 minAmountOut = bound(minAmountOutSeed, 1, swapAmount);

        uint256 initialUserUsdc = usdc.balanceOf(wallet0);
        uint256 initialUserAppStable = appStable.balanceOf(wallet0);

        vm.startPrank(wallet0);
        appStable.approve(address(swapper), swapAmount);
        swapper.swap(address(appStable), address(usdc), swapAmount, minAmountOut, wallet0);
        vm.stopPrank();

        assertEq(appStable.balanceOf(wallet0), initialUserAppStable - swapAmount);
        assertEq(usdc.balanceOf(wallet0), initialUserUsdc + swapAmount);
    }

    function testFuzz_swap_scalesUpCorrectly(uint8 decimalsInSeed, uint8 decimalsOutSeed, uint256 swapAmountSeed)
        public
    {
        uint8 decimalsIn = uint8(bound(decimalsInSeed, 6, 17)); // Max 17 so decimalsOut can be at least 18
        uint8 decimalsOut = uint8(bound(decimalsOutSeed, decimalsIn + 1, 18));

        // Fuzz the swap amount between 1 and 100 tokens
        uint256 swapAmountInTokens = bound(swapAmountSeed, 1, 100);

        // Use amounts appropriate for each token's decimals
        uint256 liquidityAmountIn = 500 * 10 ** decimalsIn; // 500 tokens (in decimals)
        uint256 liquidityAmountOut = 500 * 10 ** decimalsOut; // 500 tokens (out decimals)
        uint256 swapAmount = swapAmountInTokens * 10 ** decimalsIn; // Fuzzed tokens (in decimals)

        // Calculate expected output based on the REAL TOKEN VALUE being equal
        // If we swap 100 tokens worth $100, we should get 100 tokens worth $100 in the other denomination
        // The token value is: swapAmountInTokens (e.g., 100 tokens)
        // Expected output in different decimals: same token count, different representation
        uint256 minAmountOut = swapAmountInTokens * 10 ** decimalsOut; // Expect exact 1:1 value swap
        uint256 expectedOutput = swapAmountInTokens * 10 ** decimalsOut;

        MockERC20 tokenIn = new MockERC20("In Token", "IN", decimalsIn);
        // Mint enough for liquidity + swap amount to both treasury and wallet0
        tokenIn.mint(withdrawalAuthority, liquidityAmountIn);
        tokenIn.mint(wallet0, swapAmount);

        MockERC20 tokenOut = new MockERC20("Out Token", "OUT", decimalsOut);
        tokenOut.mint(withdrawalAuthority, liquidityAmountOut);

        vm.startPrank(configureAuthority);
        swapper.listToken(address(tokenIn));
        swapper.listToken(address(tokenOut));
        vm.stopPrank();

        vm.startPrank(pauseAuthority);
        swapper.updateTokenStatus(address(tokenIn), true);
        swapper.updateTokenStatus(address(tokenOut), true);
        vm.stopPrank();

        vm.startPrank(withdrawalAuthority);
        tokenIn.transfer(address(swapper), liquidityAmountIn);
        tokenOut.transfer(address(swapper), liquidityAmountOut);
        vm.stopPrank();

        uint256 initialUserIn = tokenIn.balanceOf(wallet0);

        vm.startPrank(wallet0);
        tokenIn.approve(address(swapper), swapAmount);
        swapper.swap(address(tokenIn), address(tokenOut), swapAmount, minAmountOut, wallet0);
        vm.stopPrank();

        assertEq(tokenIn.balanceOf(wallet0), initialUserIn - swapAmount);
        assertEq(tokenOut.balanceOf(wallet0), expectedOutput);
    }

    function testFuzz_swap_scalesDownCorrectly(
        uint256 decimalsInSeed,
        uint256 decimalsOutSeed,
        uint256 inDustAmountSeed,
        uint256 swapAmountSeed
    ) public {
        uint8 decimalsIn = uint8(bound(decimalsInSeed, 7, 18)); // Min 7 so decimalsOut can be at least 6
        uint8 decimalsOut = uint8(bound(decimalsOutSeed, 6, decimalsIn - 1));

        // Calculate the maximum dust amount (fractional part that will be rounded away)
        // For example: 6 decimals → 2 decimals means 4 decimals will be lost
        // 100999999 (100.999999) / 10^4 = 10099.9999 → floors to 10099 (100.99)
        // The dust (9999, representing 0.009999) gets discarded
        uint8 decimalsDelta = decimalsIn - decimalsOut;
        uint256 maxDust = (10 ** decimalsDelta) - 1;
        uint256 inDustAmount = bound(inDustAmountSeed, 0, maxDust);

        // Fuzz the swap amount between 1 and 100 tokens
        uint256 swapAmountInTokens = bound(swapAmountSeed, 1, 100);

        // Use amounts appropriate for each token's decimals
        uint256 liquidityAmountIn = 500 * 10 ** decimalsIn; // 500 tokens (in decimals)
        uint256 liquidityAmountOut = 500 * 10 ** decimalsOut; // 500 tokens (out decimals)
        uint256 swapAmount = swapAmountInTokens * 10 ** decimalsIn + inDustAmount; // Fuzzed tokens with dust

        // Calculate expected output based on the REAL TOKEN VALUE being equal
        // If we swap 100 tokens worth $100, we should get 100 tokens worth $100 in the other denomination
        // The token value is: swapAmountInTokens (e.g., 100 tokens)
        // Expected output in different decimals: same token count, different representation
        uint256 expectedOutput = swapAmountInTokens * 10 ** decimalsOut;
        uint256 minAmountOut = expectedOutput; // Expect exact 1:1 value swap

        MockERC20 tokenIn = new MockERC20("In Token", "IN", decimalsIn);
        // Mint enough for liquidity + swap amount to both treasury and wallet0
        tokenIn.mint(withdrawalAuthority, liquidityAmountIn);
        tokenIn.mint(wallet0, swapAmount);

        MockERC20 tokenOut = new MockERC20("Out Token", "OUT", decimalsOut);
        tokenOut.mint(withdrawalAuthority, liquidityAmountOut);

        vm.startPrank(configureAuthority);
        swapper.listToken(address(tokenIn));
        swapper.listToken(address(tokenOut));
        vm.stopPrank();

        vm.startPrank(pauseAuthority);
        swapper.updateTokenStatus(address(tokenIn), true);
        swapper.updateTokenStatus(address(tokenOut), true);
        vm.stopPrank();

        vm.startPrank(withdrawalAuthority);
        tokenIn.transfer(address(swapper), liquidityAmountIn);
        tokenOut.transfer(address(swapper), liquidityAmountOut);
        vm.stopPrank();

        uint256 initialUserIn = tokenIn.balanceOf(wallet0);

        vm.startPrank(wallet0);
        tokenIn.approve(address(swapper), swapAmount);
        swapper.swap(address(tokenIn), address(tokenOut), swapAmount, minAmountOut, wallet0);
        vm.stopPrank();

        assertEq(tokenIn.balanceOf(wallet0), initialUserIn - swapAmount);
        assertEq(tokenOut.balanceOf(wallet0), expectedOutput);
    }

    function test_swap_collectsFeesCorrectly_whenFeeRateNonZero() public {
        setupBasicSwapEnvironment();

        uint16 feeRateBps = 100; // 1% fee in basis points
        uint256 swapAmount = 100 * 10 ** 6;
        uint256 expectedFee = 1 * 10 ** 6; // 1%
        uint256 expectedNetOutput = 99 * 10 ** 6;
        uint256 minAmountOut = 99 * 10 ** 6;

        vm.prank(configureAuthority);
        swapper.updateFeeBasisPoints(feeRateBps);

        uint256 initialFeeRecipientBalance = usdc.balanceOf(feeRecipient);
        uint256 initialUserAppStable = appStable.balanceOf(wallet0);

        vm.startPrank(wallet0);
        usdc.approve(address(swapper), swapAmount);
        swapper.swap(address(usdc), address(appStable), swapAmount, minAmountOut, wallet0);
        vm.stopPrank();

        assertEq(usdc.balanceOf(feeRecipient), initialFeeRecipientBalance + expectedFee);
        assertEq(appStable.balanceOf(wallet0), initialUserAppStable + expectedNetOutput);

        // Reset fee
        vm.prank(configureAuthority);
        swapper.updateFeeBasisPoints(0);
    }

    function test_swap_skipsFees_whenFeeRateIsZero() public {
        setupBasicSwapEnvironment();

        uint256 swapAmount = 50 * 10 ** 6;
        uint256 minAmountOut = 50 * 10 ** 6;
        uint256 expectedOutput = 50 * 10 ** 6;

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

        uint16 feeRateBps = 100; // 1% fee in basis points
        // 99_999 units with 1% fee = 99_999 * 100 / 10000 = 999.99
        // Without ceiling: 999 units fee
        // With ceiling: (99_999 * 100 + 9999) / 10000 = 1000 units fee
        // User receives: 99_999 - 1000 = 98_999 units
        uint256 swapAmount = 99_999;
        uint256 minAmountOut = 98_900;
        uint256 expectedFee = 1000;

        vm.prank(configureAuthority);
        swapper.updateFeeBasisPoints(feeRateBps);

        uint256 initialFeeRecipientBalance = usdc.balanceOf(feeRecipient);

        vm.startPrank(wallet0);
        usdc.approve(address(swapper), swapAmount);
        swapper.swap(address(usdc), address(appStable), swapAmount, minAmountOut, wallet0);
        vm.stopPrank();

        uint256 feeCollected = usdc.balanceOf(feeRecipient) - initialFeeRecipientBalance;

        assertEq(feeCollected, expectedFee, "Fee should round up to 1000 units from 999.99 units");

        // Reset fee
        vm.prank(configureAuthority);
        swapper.updateFeeBasisPoints(0);
    }

    function test_swap_doesNotOverChargeFees_whenPerfectFeeAmount() public {
        setupBasicSwapEnvironment();

        uint16 feeRateBps = 100; // 1% fee in basis points
        // Amount that creates perfect fee: 100 * 10^6 * 1% = 1 * 10^6 exactly
        uint256 swapAmount = 100 * 10 ** 6;
        uint256 minAmountOut = 99 * 10 ** 6;
        uint256 expectedFee = 1 * 10 ** 6;

        vm.prank(configureAuthority);
        swapper.updateFeeBasisPoints(feeRateBps);

        uint256 initialFeeRecipientBalance = usdc.balanceOf(feeRecipient);

        vm.startPrank(wallet0);
        usdc.approve(address(swapper), swapAmount);
        swapper.swap(address(usdc), address(appStable), swapAmount, minAmountOut, wallet0);
        vm.stopPrank();

        uint256 feeCollected = usdc.balanceOf(feeRecipient) - initialFeeRecipientBalance;
        assertEq(feeCollected, expectedFee);

        // Reset
        vm.prank(configureAuthority);
        swapper.updateFeeBasisPoints(0);
    }
}
