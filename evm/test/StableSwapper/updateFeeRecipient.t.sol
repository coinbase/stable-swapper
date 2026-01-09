// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {StableSwapperBase} from "./StableSwapperBase.sol";

/**
 * @title UpdateFeeRecipientTest
 * @notice Tests for the StableSwapper updateFeeRecipient function
 */
contract UpdateFeeRecipientTest is StableSwapperBase {
    function test_updatesFeeRecipientAndCollectsFeesToNewRecipient() public {
        address newFeeRecipient = makeAddr("newFeeRecipient");
        
        vm.startPrank(operationsAuthority);
        swapper.addToken(address(usdc));
        swapper.addToken(address(appStable));
        
        usdc.approve(address(swapper), 500 * 10 ** 6);
        swapper.deposit_liquidity(address(usdc), 500 * 10 ** 6);
        
        appStable.approve(address(swapper), 500 * 10 ** 6);
        swapper.deposit_liquidity(address(appStable), 500 * 10 ** 6);
        
        // Update fee recipient and set 1% fee
        swapper.updateFeeRecipient(newFeeRecipient);
        swapper.updateFeeRate(100);
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
        vm.startPrank(operationsAuthority);
        swapper.updateFeeRecipient(feeRecipient);
        swapper.updateFeeRate(0);
        vm.stopPrank();
    }
}

