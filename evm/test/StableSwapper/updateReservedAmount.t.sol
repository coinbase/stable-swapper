// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {StableSwapperBase} from "./StableSwapperBase.sol";
import {StableSwapper} from "../../src/StableSwapper.sol";

/**
 * @title UpdateReservedAmountTest
 * @notice Tests for the StableSwapper updateReservedAmount function
 */
contract UpdateReservedAmountTest is StableSwapperBase {
    /*//////////////////////////////////////////////////////////////
                              REVERT TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_revertsWhenUnauthorizedUserTriesToUpdateReservedAmount() public {
        vm.prank(operationsAuthority);
        swapper.addToken(address(usdc));
        
        address unauthorized = makeAddr("unauthorized");
        
        vm.prank(unauthorized);
        vm.expectRevert();
        swapper.updateReservedAmount(address(usdc), 100 * 10 ** 6);
    }
    
    /*//////////////////////////////////////////////////////////////
                            SUCCESS TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_updatesReservedAmount() public {
        vm.prank(operationsAuthority);
        swapper.addToken(address(usdc));
        
        vm.startPrank(operationsAuthority);
        usdc.approve(address(swapper), 500 * 10 ** 6);
        swapper.deposit_liquidity(address(usdc), 500 * 10 ** 6);
        vm.stopPrank();
        
        uint64 reservedAmount = 50 * 10 ** 6;
        
        vm.prank(operationsAuthority);
        swapper.updateReservedAmount(address(usdc), reservedAmount);
        
        StableSwapper.TokenVault memory vault = swapper.getVault(address(usdc));
        assertEq(vault.reservedAmount, reservedAmount);
    }
}

