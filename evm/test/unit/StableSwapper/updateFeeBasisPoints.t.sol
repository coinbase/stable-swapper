// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {StableSwapper} from "../../../src/StableSwapper.sol";

import {StableSwapperBase} from "../../lib/StableSwapperBase.sol";

/**
 * @title UpdateFeeBasisPointsTest
 * @notice Tests for the StableSwapper updateFeeBasisPoints function
 */
contract UpdateFeeBasisPointsTest is StableSwapperBase {
    /*//////////////////////////////////////////////////////////////
                              REVERT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_updateFeeBasisPoints_reverts_whenUnauthorizedUser() public {
        address unauthorized = makeAddr("unauthorized");

        vm.prank(unauthorized);
        vm.expectRevert();
        swapper.updateFeeBasisPoints(50);
    }

    function testFuzz_updateFeeBasisPoints_reverts_whenFeeExceedsDenominator(uint256 FeeBasisPointsSeed) public {
        uint16 invalidFee = uint16(bound(FeeBasisPointsSeed, swapper.FEE_DENOMINATOR() + 1, type(uint16).max));

        vm.prank(configureAuthority);
        vm.expectRevert(abi.encodeWithSelector(StableSwapper.FeeExceedsDenominator.selector, invalidFee));
        swapper.updateFeeBasisPoints(invalidFee);
    }

    /*//////////////////////////////////////////////////////////////
                            SUCCESS TESTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Fuzz test: Any valid fee rate should be accepted
     * @dev Tests that fee rates can be set to any value up to and including FEE_DENOMINATOR
     */
    function testFuzz_updateFeeBasisPoints_acceptsValidFeeBasisPointss(uint256 FeeBasisPointsSeed) public {
        uint16 FeeBasisPoints = uint16(bound(FeeBasisPointsSeed, 0, swapper.FEE_DENOMINATOR()));

        vm.prank(configureAuthority);
        swapper.updateFeeBasisPoints(FeeBasisPoints);

        // Verify fee rate was set correctly
        assertEq(swapper.feeBasisPoints(), FeeBasisPoints, "Fee rate not set correctly");

        // Reset
        vm.prank(configureAuthority);
        swapper.updateFeeBasisPoints(0);
    }
}
