// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {StableSwapper} from "../../../src/StableSwapper.sol";

import {StableSwapperBase} from "../../lib/StableSwapperBase.sol";

/**
 * @title UpdateFeeRecipientTest
 * @notice Tests for the StableSwapper updateFeeRecipient function
 */
contract UpdateFeeRecipientTest is StableSwapperBase {
    /*//////////////////////////////////////////////////////////////
                              REVERT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_updateFeeRecipient_reverts_whenUnauthorizedUser() public {
        address unauthorized = makeAddr("unauthorized");
        vm.expectRevert();
        swapper.updateFeeRecipient(unauthorized);
    }

    function test_updateFeeRecipient_reverts_whenZeroAddress() public {
        vm.prank(configureAuthority);
        vm.expectRevert(StableSwapper.CannotBeZeroAddress.selector);
        swapper.updateFeeRecipient(address(0));
    }

    /*//////////////////////////////////////////////////////////////
                            SUCCESS TESTS
    //////////////////////////////////////////////////////////////*/

    function test_updateFeeRecipient_collectsFeesToNewRecipient() public {
        address newFeeRecipient = makeAddr("newFeeRecipient");

        uint64 liquidityAmount = 500 * 10 ** 6;
        uint16 feeRate = 100; // 1%

        vm.startPrank(configureAuthority);
        swapper.updateTokenListing(address(usdc), true);
        swapper.updateTokenListing(address(appStable), true);

        // Update fee recipient and set 1% fee
        swapper.updateFeeRecipient(newFeeRecipient);
        swapper.updateFeeBasisPoints(feeRate);
        vm.stopPrank();

        vm.startPrank(pauseAuthority);
        swapper.updateTokenStatus(address(usdc), true);
        swapper.updateTokenStatus(address(appStable), true);
        vm.stopPrank();

        vm.startPrank(treasuryAuthority);
        usdc.transfer(address(swapper), liquidityAmount);
        appStable.transfer(address(swapper), liquidityAmount);
        vm.stopPrank();

        uint64 swapAmount = 100 * 10 ** 6;
        uint64 expectedFee = 1 * 10 ** 6;
        uint64 minAmountOut = 99 * 10 ** 6;

        vm.startPrank(wallet0);
        usdc.approve(address(swapper), swapAmount);
        swapper.swap(address(usdc), address(appStable), swapAmount, minAmountOut, wallet0);
        vm.stopPrank();

        assertEq(usdc.balanceOf(newFeeRecipient), expectedFee);

        // Reset
        uint16 resetFeeRate = 0;
        vm.startPrank(configureAuthority);
        swapper.updateFeeRecipient(feeRecipient);
        swapper.updateFeeBasisPoints(resetFeeRate);
        vm.stopPrank();
    }
}
