// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {StableSwapperBase} from "./StableSwapperBase.sol";
import {StableSwapper} from "../../src/StableSwapper.sol";

/**
 * @title WithdrawLiquidityTest
 * @notice Tests for the StableSwapper withdraw_liquidity function
 */
contract WithdrawLiquidityTest is StableSwapperBase {
    /*//////////////////////////////////////////////////////////////
                              REVERT TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_revertsWhenUnauthorizedUserTriesToWithdraw() public {
        vm.prank(operationsAuthority);
        swapper.addToken(address(usdc));
        
        address unauthorized = makeAddr("unauthorized");
        
        vm.prank(unauthorized);
        vm.expectRevert();
        swapper.withdraw_liquidity(address(usdc), 10 * 10 ** 6);
    }
    
    function test_revertsWhenLiquidityPaused() public {
        vm.prank(operationsAuthority);
        swapper.addToken(address(usdc));
        
        uint64 depositAmount = 500 * 10 ** 6;
        vm.startPrank(operationsAuthority);
        usdc.approve(address(swapper), depositAmount);
        swapper.deposit_liquidity(address(usdc), depositAmount);
        vm.stopPrank();
        
        // Pause liquidity
        vm.prank(pauseAuthority);
        swapper.pauseLiquidity();
        
        uint64 withdrawAmount = 10 * 10 ** 6;
        
        vm.prank(operationsAuthority);
        vm.expectRevert(StableSwapper.LiquidityCannotBePaused.selector);
        swapper.withdraw_liquidity(address(usdc), withdrawAmount);
        
        // Unpause liquidity
        vm.prank(pauseAuthority);
        swapper.unpauseLiquidity();
    }
    
    function test_revertsWhenWithdrawingZeroAmount() public {
        vm.prank(operationsAuthority);
        swapper.addToken(address(usdc));
        
        vm.prank(operationsAuthority);
        vm.expectRevert(StableSwapper.CannotBeZeroAmount.selector);
        swapper.withdraw_liquidity(address(usdc), 0);
    }
    
    function test_revertsWhenWithdrawingMoreThanBalance() public {
        vm.prank(operationsAuthority);
        swapper.addToken(address(usdc));
        
        vm.startPrank(operationsAuthority);
        usdc.approve(address(swapper), 100 * 10 ** 6);
        swapper.deposit_liquidity(address(usdc), 100 * 10 ** 6);
        
        vm.expectRevert();
        swapper.withdraw_liquidity(address(usdc), 200 * 10 ** 6);
        vm.stopPrank();
    }
    
    /*//////////////////////////////////////////////////////////////
                            SUCCESS TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_withdrawsUsdcLiquidity() public {
        vm.prank(operationsAuthority);
        swapper.addToken(address(usdc));
        
        uint64 depositAmount = 500 * 10 ** 6;
        vm.startPrank(operationsAuthority);
        usdc.approve(address(swapper), depositAmount);
        swapper.deposit_liquidity(address(usdc), depositAmount);
        vm.stopPrank();
        
        uint64 withdrawAmount = 50 * 10 ** 6;
        uint256 initialBalance = usdc.balanceOf(operationsAuthority);
        
        vm.prank(operationsAuthority);
        swapper.withdraw_liquidity(address(usdc), withdrawAmount);
        
        assertEq(usdc.balanceOf(address(swapper)), depositAmount - withdrawAmount);
        assertEq(usdc.balanceOf(operationsAuthority), initialBalance + withdrawAmount);
    }
    
    function test_allowsWithdrawalRegardlessOfReservedAmount() public {
        vm.prank(operationsAuthority);
        swapper.addToken(address(usdc));
        
        uint64 depositAmount = 500 * 10 ** 6;
        vm.startPrank(operationsAuthority);
        usdc.approve(address(swapper), depositAmount);
        swapper.deposit_liquidity(address(usdc), depositAmount);
        vm.stopPrank();
        
        // Set reserved amount
        vm.prank(operationsAuthority);
        swapper.updateReservedAmount(address(usdc), 100 * 10 ** 6);
        
        // Operations authority can withdraw even into reserved amount
        uint64 withdrawAmount = 50 * 10 ** 6;
        
        vm.prank(operationsAuthority);
        swapper.withdraw_liquidity(address(usdc), withdrawAmount);
        
        assertEq(usdc.balanceOf(address(swapper)), depositAmount - withdrawAmount);
    }
}

