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
        swapper.updateFeeBasisPoints(50);
    }

    /*//////////////////////////////////////////////////////////////
                            SUCCESS TESTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Fuzz test: Any fee rate should be accepted
     * @dev Tests that fee rates can be set to any uint16 value
     */
    function testFuzz_updateFeeRate_acceptsValidFeeRates(uint256 feeRateSeed) public {
        uint16 feeRate = uint16(bound(feeRateSeed, 0, type(uint16).max));

        vm.prank(configureAuthority);
        swapper.updateFeeBasisPoints(feeRate);

        // Verify fee rate was set correctly
        assertEq(swapper.feeBasisPoints(), feeRate, "Fee rate not set correctly");

        // Reset
        vm.prank(configureAuthority);
        swapper.updateFeeBasisPoints(0);
    }
}
