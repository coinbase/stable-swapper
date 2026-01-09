// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {StableSwapperBase} from "./StableSwapperBase.sol";
import {StableSwapper} from "../../src/StableSwapper.sol";

/**
 * @title UpdateFeeRateTest
 * @notice Tests for the StableSwapper updateFeeRate function
 */
contract UpdateFeeRateTest is StableSwapperBase {
    /*//////////////////////////////////////////////////////////////
                              REVERT TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_updateFeeRate_reverts_whenUnauthorizedUser() public {
        address unauthorized = makeAddr("unauthorized");
        
        vm.prank(unauthorized);
        vm.expectRevert();
        swapper.updateFeeRate(50);
    }
    
    function test_updateFeeRate_reverts_whenFeeRateExceedsMaximum() public {
        uint64 excessiveFeeRate = 1001; // > 10%
        
        vm.prank(operationsAuthority);
        vm.expectRevert(abi.encodeWithSelector(StableSwapper.FeeRateExceedsMaximum.selector, excessiveFeeRate));
        swapper.updateFeeRate(excessiveFeeRate);
    }
    
    /*//////////////////////////////////////////////////////////////
                            SUCCESS TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_updateFeeRate_updatesFeeRate() public {
        uint64 newFeeRate = 25; // 0.25%
        
        vm.prank(operationsAuthority);
        swapper.updateFeeRate(newFeeRate);
        
        assertEq(swapper.feeRate(), newFeeRate);
        
        // Reset
        uint64 resetFeeRate = 0;
        vm.prank(operationsAuthority);
        swapper.updateFeeRate(resetFeeRate);
    }
    
    function test_updateFeeRate_allowsMaximumFeeRate() public {
        uint64 maxFeeRate = 1000; // 10%
        
        vm.prank(operationsAuthority);
        swapper.updateFeeRate(maxFeeRate);
        
        assertEq(swapper.feeRate(), maxFeeRate);
        
        // Reset
        uint64 resetFeeRate = 0;
        vm.prank(operationsAuthority);
        swapper.updateFeeRate(resetFeeRate);
    }
}

