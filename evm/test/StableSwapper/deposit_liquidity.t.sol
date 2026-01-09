// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {StableSwapperBase} from "./StableSwapperBase.sol";
import {StableSwapper} from "../../src/StableSwapper.sol";

/**
 * @title DepositLiquidityTest
 * @notice Tests for the StableSwapper deposit_liquidity function
 */
contract DepositLiquidityTest is StableSwapperBase {
    /*//////////////////////////////////////////////////////////////
                              REVERT TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_revertsWhenUnauthorizedUserTriesToDeposit() public {
        vm.prank(operationsAuthority);
        swapper.addToken(address(usdc));
        
        address unauthorized = makeAddr("unauthorized");
        usdc.mint(unauthorized, 100 * 10 ** 6);
        
        vm.startPrank(unauthorized);
        usdc.approve(address(swapper), 10 * 10 ** 6);
        vm.expectRevert();
        swapper.deposit_liquidity(address(usdc), 10 * 10 ** 6);
        vm.stopPrank();
    }
    
    function test_revertsWhenLiquidityPaused() public {
        vm.prank(operationsAuthority);
        swapper.addToken(address(usdc));
        
        // Pause liquidity
        vm.prank(pauseAuthority);
        swapper.pauseLiquidity();
        
        uint64 depositAmount = 10 * 10 ** 6;
        
        vm.startPrank(operationsAuthority);
        usdc.approve(address(swapper), depositAmount);
        vm.expectRevert(StableSwapper.LiquidityCannotBePaused.selector);
        swapper.deposit_liquidity(address(usdc), depositAmount);
        vm.stopPrank();
        
        // Unpause liquidity
        vm.prank(pauseAuthority);
        swapper.unpauseLiquidity();
    }
    
    function test_revertsWhenDepositingZeroAmount() public {
        vm.prank(operationsAuthority);
        swapper.addToken(address(usdc));
        
        vm.prank(operationsAuthority);
        vm.expectRevert(StableSwapper.CannotBeZeroAmount.selector);
        swapper.deposit_liquidity(address(usdc), 0);
    }
    
    /*//////////////////////////////////////////////////////////////
                            SUCCESS TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_depositsUsdcLiquidity() public {
        vm.prank(operationsAuthority);
        swapper.addToken(address(usdc));
        
        uint64 depositAmount = 500 * 10 ** 6; // 500 USDC
        
        vm.startPrank(operationsAuthority);
        usdc.approve(address(swapper), depositAmount);
        swapper.deposit_liquidity(address(usdc), depositAmount);
        vm.stopPrank();
        
        assertEq(usdc.balanceOf(address(swapper)), depositAmount);
    }
    
    function test_depositsAppStableLiquidity() public {
        vm.prank(operationsAuthority);
        swapper.addToken(address(appStable));
        
        uint64 depositAmount = 500 * 10 ** 6; // 500 AppStable
        
        vm.startPrank(operationsAuthority);
        appStable.approve(address(swapper), depositAmount);
        swapper.deposit_liquidity(address(appStable), depositAmount);
        vm.stopPrank();
        
        assertEq(appStable.balanceOf(address(swapper)), depositAmount);
    }
}

