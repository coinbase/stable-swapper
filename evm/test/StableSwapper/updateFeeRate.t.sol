// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {StableSwapper} from "../../src/StableSwapper.sol";
import {StableSwapperBase} from "./StableSwapperBase.sol";

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
    
    /**
     * @notice Fuzz test: Any fee rate above maximum should revert
     * @dev Tests that fee rates > 1000 (10%) are always rejected
     */
    function testFuzz_updateFeeRate_revertsOnExcessiveFeeRate(uint256 feeRateSeed) public {
        // Bound to invalid range: anything above MAX_FEE_RATE (1000)
        uint64 excessiveFeeRate = uint64(bound(feeRateSeed, 1001, type(uint64).max));
        
        vm.prank(operationsAuthority);
        vm.expectRevert(
            abi.encodeWithSelector(StableSwapper.FeeRateExceedsMaximum.selector, excessiveFeeRate)
        );
        swapper.updateFeeRate(excessiveFeeRate);
        
        // Verify fee rate wasn't changed
        assertEq(swapper.feeRate(), 0, "Fee rate should remain unchanged");
    }
    
    /*//////////////////////////////////////////////////////////////
                            SUCCESS TESTS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Fuzz test: Any valid fee rate (0-1000) should be accepted
     * @dev Tests that all fee rates within valid range can be set
     */
    function testFuzz_updateFeeRate_acceptsValidFeeRates(uint256 feeRateSeed) public {
        // Bound to valid range: 0-1000 basis points (0-10%)
        uint64 feeRate = uint64(bound(feeRateSeed, 0, 1000));
        
        vm.prank(operationsAuthority);
        swapper.updateFeeRate(feeRate);
        
        // Verify fee rate was set correctly
        assertEq(swapper.feeRate(), feeRate, "Fee rate not set correctly");
        
        // Reset
        vm.prank(operationsAuthority);
        swapper.updateFeeRate(0);
    }
}

