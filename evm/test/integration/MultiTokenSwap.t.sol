// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {StableSwapper} from "../../src/StableSwapper.sol";
import {MockERC20, StableSwapperBase} from "../lib/StableSwapperBase.sol";

/// @title MultiTokenSwapTest
/// @notice Integration tests for multi-token swap scenarios with various configurations
/// @dev Tests the full lifecycle: listing tokens with different decimals, enabling swaps with whitelist,
///      disabling whitelist, updating reserved amounts and fees, listing new tokens, pausing, and unlisting
contract MultiTokenSwapTest is StableSwapperBase {
    MockERC20 public usdt; // 6 decimals
    MockERC20 public dai; // 18 decimals
    MockERC20 public busd; // 18 decimals
    MockERC20 public tusd; // 18 decimals - will be listed later

    function setUp() public override {
        super.setUp();

        // Create additional tokens with different decimal places
        usdt = new MockERC20("Tether USD", "USDT", 6);
        dai = new MockERC20("Dai Stablecoin", "DAI", 18);
        busd = new MockERC20("Binance USD", "BUSD", 18);
        tusd = new MockERC20("TrueUSD", "TUSD", 18);

        // Mint tokens to wallet0 for swapping
        usdt.mint(wallet0, 10000 * 10 ** 6); // 10,000 USDT
        dai.mint(wallet0, 10000 * 10 ** 18); // 10,000 DAI
        busd.mint(wallet0, 10000 * 10 ** 18); // 10,000 BUSD
        tusd.mint(wallet0, 10000 * 10 ** 18); // 10,000 TUSD

        // Mint tokens to wallet1 for additional testing
        usdc.mint(wallet1, 5000 * 10 ** 6); // Need USDC for allowlist test
        usdt.mint(wallet1, 5000 * 10 ** 6);
        dai.mint(wallet1, 5000 * 10 ** 18);
        busd.mint(wallet1, 5000 * 10 ** 18);

        // Mint tokens to withdrawal authority for liquidity
        // These amounts need to cover all transfers in the tests
        usdc.mint(withdrawalAuthority, 10000 * 10 ** 6); // Additional USDC for our tests
        usdt.mint(withdrawalAuthority, 20000 * 10 ** 6); // Extra for allowlist test
        dai.mint(withdrawalAuthority, 30000 * 10 ** 18); // Need more for cross-decimal test
        busd.mint(withdrawalAuthority, 10000 * 10 ** 18);
        tusd.mint(withdrawalAuthority, 10000 * 10 ** 18);
    }

    /// @dev Complete integration test covering:
    /// 1. Listing tokens with different decimal places
    /// 2. Enabling swapping with whitelist
    /// 3. Disabling whitelist
    /// 4. Updating reserved amounts
    /// 5. Adding fees
    /// 6. Listing a new token
    /// 7. Pausing swaps
    /// 8. Unlisting an existing token
    function test_multiToken_fullLifecycle() public {
        // ============================================================
        // PHASE 1: List tokens with different decimal places
        // ============================================================
        vm.startPrank(configureAuthority);
        swapper.updateTokenListing(address(usdc), true); // 6 decimals
        swapper.updateTokenListing(address(usdt), true); // 6 decimals
        swapper.updateTokenListing(address(dai), true); // 18 decimals
        swapper.updateTokenListing(address(busd), true); // 18 decimals
        vm.stopPrank();

        // Verify tokens are listed but not swappable yet
        assertEq(swapper.isTokenListed(address(usdc)), true);
        assertEq(swapper.isTokenListed(address(usdt)), true);
        assertEq(swapper.isTokenListed(address(dai)), true);
        assertEq(swapper.isTokenListed(address(busd)), true);
        assertEq(swapper.isTokenSwappable(address(usdc)), false);
        assertEq(swapper.isTokenSwappable(address(usdt)), false);
        assertEq(swapper.isTokenSwappable(address(dai)), false);
        assertEq(swapper.isTokenSwappable(address(busd)), false);
        assertEq(swapper.getListedTokensCount(), 4);

        // Add liquidity for all tokens
        vm.startPrank(withdrawalAuthority);
        usdc.transfer(address(swapper), 10000 * 10 ** 6);
        usdt.transfer(address(swapper), 10000 * 10 ** 6);
        dai.transfer(address(swapper), 10000 * 10 ** 18);
        busd.transfer(address(swapper), 10000 * 10 ** 18);
        vm.stopPrank();

        // ============================================================
        // PHASE 2: Enable swapping with whitelist in place
        // ============================================================

        // Enable allowlist feature
        vm.prank(configureAuthority);
        swapper.setFeatureFlag(StableSwapper.FeatureFlag.ALLOWLIST, true);
        assertEq(swapper.isFeatureEnabled(StableSwapper.FeatureFlag.ALLOWLIST), true);

        // Add wallet0 to allowlist
        vm.prank(configureAuthority);
        swapper.updateAllowlist(wallet0, true);
        assertEq(swapper.isAllowlisted(wallet0), true);
        assertEq(swapper.isAllowlisted(wallet1), false);

        // Enable tokens for swapping
        vm.startPrank(pauseAuthority);
        swapper.updateTokenStatus(address(usdc), true);
        swapper.updateTokenStatus(address(usdt), true);
        swapper.updateTokenStatus(address(dai), true);
        swapper.updateTokenStatus(address(busd), true);
        vm.stopPrank();

        // Verify tokens are now swappable
        assertEq(swapper.isTokenSwappable(address(usdc)), true);
        assertEq(swapper.isTokenSwappable(address(usdt)), true);
        assertEq(swapper.isTokenSwappable(address(dai)), true);
        assertEq(swapper.isTokenSwappable(address(busd)), true);

        // Test swap with allowlist (wallet0 is allowed)
        uint256 swapAmount = 100 * 10 ** 6; // 100 USDC
        uint256 wallet0UsdcBefore = usdc.balanceOf(wallet0);
        uint256 wallet0UsdtBefore = usdt.balanceOf(wallet0);

        vm.startPrank(wallet0);
        usdc.approve(address(swapper), swapAmount);
        swapper.swap(address(usdc), address(usdt), swapAmount, swapAmount, wallet0);
        vm.stopPrank();

        // Verify swap succeeded (6 decimals -> 6 decimals, no fee yet)
        assertEq(usdc.balanceOf(wallet0), wallet0UsdcBefore - swapAmount);
        assertEq(usdt.balanceOf(wallet0), wallet0UsdtBefore + swapAmount);

        // Test that non-allowlisted address cannot swap
        vm.startPrank(wallet1);
        usdt.approve(address(swapper), swapAmount);
        vm.expectRevert(abi.encodeWithSelector(StableSwapper.AddressNotInAllowlist.selector, wallet1));
        swapper.swap(address(usdt), address(usdc), swapAmount, swapAmount, wallet1);
        vm.stopPrank();

        // ============================================================
        // PHASE 3: Disable whitelist
        // ============================================================
        vm.prank(configureAuthority);
        swapper.setFeatureFlag(StableSwapper.FeatureFlag.ALLOWLIST, false);
        assertEq(swapper.isFeatureEnabled(StableSwapper.FeatureFlag.ALLOWLIST), false);

        // Now wallet1 (not in allowlist) should be able to swap
        uint256 wallet1UsdtBefore = usdt.balanceOf(wallet1);
        uint256 wallet1DaiBefore = dai.balanceOf(wallet1);
        uint256 swapAmountUSDT = 50 * 10 ** 6; // 50 USDT
        uint256 expectedDaiOut = 50 * 10 ** 18; // 50 DAI (6 decimals -> 18 decimals)

        vm.startPrank(wallet1);
        usdt.approve(address(swapper), swapAmountUSDT);
        swapper.swap(address(usdt), address(dai), swapAmountUSDT, expectedDaiOut, wallet1);
        vm.stopPrank();

        // Verify swap with decimal conversion (6 -> 18)
        assertEq(usdt.balanceOf(wallet1), wallet1UsdtBefore - swapAmountUSDT);
        assertEq(dai.balanceOf(wallet1), wallet1DaiBefore + expectedDaiOut);

        // ============================================================
        // PHASE 4: Update reserved amounts
        // ============================================================
        uint256 reservedUSDC = 5000 * 10 ** 6; // Reserve 5000 USDC
        uint256 reservedDAI = 3000 * 10 ** 18; // Reserve 3000 DAI

        vm.startPrank(withdrawalAuthority);
        swapper.updateReservedAmount(address(usdc), reservedUSDC);
        swapper.updateReservedAmount(address(dai), reservedDAI);
        vm.stopPrank();

        assertEq(swapper.getReservedAmount(address(usdc)), reservedUSDC);
        assertEq(swapper.getReservedAmount(address(dai)), reservedDAI);

        // Verify that swaps respecting reserved amounts work
        uint256 availableUSDC = usdc.balanceOf(address(swapper)) - reservedUSDC;
        uint256 smallSwapUSDC = availableUSDC / 2; // USDC amount (6 decimals)
        uint256 smallSwapDAI = smallSwapUSDC * 10 ** 12; // Convert to DAI amount (18 decimals)

        vm.startPrank(wallet0);
        dai.approve(address(swapper), smallSwapDAI);
        // Swap DAI for USDC, expecting to receive smallSwapUSDC
        swapper.swap(address(dai), address(usdc), smallSwapDAI, smallSwapUSDC, wallet0);
        vm.stopPrank();

        // Verify that swaps exceeding available liquidity (above reserved amount) fail
        uint256 usdcBalanceInSwapper = usdc.balanceOf(address(swapper));
        uint256 excessiveSwapUSDC = usdcBalanceInSwapper - reservedUSDC + 1; // Try to get 1 more than available
        uint256 excessiveSwapDAI = excessiveSwapUSDC * 10 ** 12; // Convert to DAI amount (18 decimals)

        vm.startPrank(wallet0);
        dai.approve(address(swapper), excessiveSwapDAI);

        // This should revert because it tries to take more than available liquidity
        vm.expectRevert(
            abi.encodeWithSelector(
                StableSwapper.AmountOutExceedsAvailableLiquidity.selector,
                excessiveSwapUSDC,
                usdcBalanceInSwapper - reservedUSDC
            )
        );
        swapper.swap(address(dai), address(usdc), excessiveSwapDAI, excessiveSwapUSDC, wallet0);
        vm.stopPrank();

        // ============================================================
        // PHASE 5: Add fees
        // ============================================================
        uint16 feeBasisPoints = 100; // 1% fee (100 basis points)

        vm.prank(configureAuthority);
        swapper.updateFeeBasisPoints(feeBasisPoints);
        assertEq(swapper.feeBasisPoints(), feeBasisPoints);

        // Test swap with fees
        uint256 swapWithFeeAmount = 1000 * 10 ** 18; // 1000 DAI
        uint256 expectedFee =
            (swapWithFeeAmount * feeBasisPoints + swapper.FEE_DENOMINATOR() - 1) / swapper.FEE_DENOMINATOR(); // Ceiling division: 10 DAI
        uint256 amountAfterFee = swapWithFeeAmount - expectedFee;
        uint256 expectedBUSDOut = amountAfterFee; // 18 decimals -> 18 decimals

        uint256 wallet1DaiBeforeFeeSwap = dai.balanceOf(wallet1);
        uint256 wallet1BusdBeforeFeeSwap = busd.balanceOf(wallet1);
        uint256 feeRecipientDaiBefore = dai.balanceOf(feeRecipient);

        vm.startPrank(wallet1);
        dai.approve(address(swapper), swapWithFeeAmount);
        swapper.swap(address(dai), address(busd), swapWithFeeAmount, expectedBUSDOut, wallet1);
        vm.stopPrank();

        // Verify fee was collected and swap executed correctly
        assertEq(dai.balanceOf(wallet1), wallet1DaiBeforeFeeSwap - swapWithFeeAmount);
        assertEq(busd.balanceOf(wallet1), wallet1BusdBeforeFeeSwap + expectedBUSDOut);
        assertEq(dai.balanceOf(feeRecipient), feeRecipientDaiBefore + expectedFee);

        // ============================================================
        // PHASE 6: List a new token (TUSD)
        // ============================================================
        vm.prank(configureAuthority);
        swapper.updateTokenListing(address(tusd), true);

        assertEq(swapper.isTokenListed(address(tusd)), true);
        assertEq(swapper.isTokenSwappable(address(tusd)), false);
        assertEq(swapper.getListedTokensCount(), 5);

        // Add liquidity for TUSD
        vm.prank(withdrawalAuthority);
        tusd.transfer(address(swapper), 10000 * 10 ** 18);

        // Enable TUSD for swapping
        vm.prank(pauseAuthority);
        swapper.updateTokenStatus(address(tusd), true);

        assertEq(swapper.isTokenSwappable(address(tusd)), true);

        // Test swap with newly listed token
        uint256 tusdSwapAmount = 500 * 10 ** 18;
        // Calculate expected fee (1%)
        uint256 tusdFee = (tusdSwapAmount * feeBasisPoints + swapper.FEE_DENOMINATOR() - 1) / swapper.FEE_DENOMINATOR();
        uint256 tusdAfterFee = tusdSwapAmount - tusdFee;
        uint256 expectedUSDTFromTUSD = tusdAfterFee / 10 ** 12; // 18 decimals -> 6 decimals

        uint256 wallet0TusdBefore = tusd.balanceOf(wallet0);
        uint256 wallet0UsdtBefore2 = usdt.balanceOf(wallet0);

        vm.startPrank(wallet0);
        tusd.approve(address(swapper), tusdSwapAmount);
        swapper.swap(address(tusd), address(usdt), tusdSwapAmount, expectedUSDTFromTUSD, wallet0);
        vm.stopPrank();

        // Verify new token swap with fee and decimal conversion
        assertEq(tusd.balanceOf(wallet0), wallet0TusdBefore - tusdSwapAmount);
        assertEq(usdt.balanceOf(wallet0), wallet0UsdtBefore2 + expectedUSDTFromTUSD);

        // ============================================================
        // PHASE 7: Pause swaps
        // ============================================================
        vm.prank(pauseAuthority);
        swapper.setFeatureFlag(StableSwapper.FeatureFlag.SWAP, false);

        assertEq(swapper.isFeatureEnabled(StableSwapper.FeatureFlag.SWAP), false);

        // Attempt to swap while paused should fail
        vm.startPrank(wallet0);
        dai.approve(address(swapper), 100 * 10 ** 18);
        vm.expectRevert(StableSwapper.SwapsCannotBePaused.selector);
        swapper.swap(address(dai), address(busd), 100 * 10 ** 18, 99 * 10 ** 18, wallet0);
        vm.stopPrank();

        // Re-enable swaps
        vm.prank(pauseAuthority);
        swapper.setFeatureFlag(StableSwapper.FeatureFlag.SWAP, true);

        // ============================================================
        // PHASE 8: Unlist an existing token (BUSD)
        // ============================================================

        // First, disable the token from being swappable
        vm.prank(pauseAuthority);
        swapper.updateTokenStatus(address(busd), false);

        assertEq(swapper.isTokenSwappable(address(busd)), false);

        // Verify that swaps with the disabled token fail (tokenIn)
        vm.startPrank(wallet0);
        busd.approve(address(swapper), 100 * 10 ** 18);
        vm.expectRevert(abi.encodeWithSelector(StableSwapper.TokenMustBeSwappable.selector, address(busd)));
        swapper.swap(address(busd), address(dai), 100 * 10 ** 18, 99 * 10 ** 18, wallet0);
        vm.stopPrank();

        // Verify that swaps with the disabled token fail (tokenOut)
        vm.startPrank(wallet0);
        dai.approve(address(swapper), 100 * 10 ** 18);
        vm.expectRevert(abi.encodeWithSelector(StableSwapper.TokenMustBeSwappable.selector, address(busd)));
        swapper.swap(address(dai), address(busd), 100 * 10 ** 18, 99 * 10 ** 18, wallet0);
        vm.stopPrank();

        // Now unlist the token
        vm.prank(configureAuthority);
        swapper.updateTokenListing(address(busd), false);

        assertEq(swapper.isTokenListed(address(busd)), false);
        assertEq(swapper.getListedTokensCount(), 4);

        // Verify unlisted token cannot be used in swaps
        vm.startPrank(wallet0);
        dai.approve(address(swapper), 100 * 10 ** 18);
        vm.expectRevert(abi.encodeWithSelector(StableSwapper.TokenNotListed.selector, address(busd)));
        swapper.swap(address(dai), address(busd), 100 * 10 ** 18, 99 * 10 ** 18, wallet0);
        vm.stopPrank();

        // Verify final state: 4 tokens listed (USDC, USDT, DAI, TUSD)
        address[] memory listedTokens = swapper.getListedTokens();
        assertEq(listedTokens.length, 4);

        // Verify remaining tokens are still swappable
        assertEq(swapper.isTokenSwappable(address(usdc)), true);
        assertEq(swapper.isTokenSwappable(address(usdt)), true);
        assertEq(swapper.isTokenSwappable(address(dai)), true);
        assertEq(swapper.isTokenSwappable(address(tusd)), true);
    }
}

