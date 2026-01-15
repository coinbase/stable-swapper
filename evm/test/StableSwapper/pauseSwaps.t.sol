// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {StableSwapperBase} from "./StableSwapperBase.sol";
import {StableSwapper} from "../../src/StableSwapper.sol";

/**
 * @title PauseSwapsTest
 * @notice Tests for the StableSwapper setFeatureFlag function
 */
contract PauseSwapsTest is StableSwapperBase {
    /*//////////////////////////////////////////////////////////////
                              REVERT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_setFeatureFlag_reverts_whenUnauthorizedUser() public {
        address unauthorized = makeAddr("unauthorized");

        vm.prank(unauthorized);
        vm.expectRevert();
        swapper.setFeatureFlag(StableSwapper.FeatureFlag.SWAP, false);
    }

    /*//////////////////////////////////////////////////////////////
                            SUCCESS TESTS
    //////////////////////////////////////////////////////////////*/

    function test_setFeatureFlag_pausesSwaps() public {
        vm.prank(pauseAuthority);
        swapper.setFeatureFlag(StableSwapper.FeatureFlag.SWAP, false);

        assertFalse(swapper.isFeatureEnabled(StableSwapper.FeatureFlag.SWAP));
    }

    function test_setFeatureFlag_unpausesSwaps() public {
        vm.startPrank(pauseAuthority);
        swapper.setFeatureFlag(StableSwapper.FeatureFlag.SWAP, false);
        swapper.setFeatureFlag(StableSwapper.FeatureFlag.SWAP, true);
        vm.stopPrank();

        assertTrue(swapper.isFeatureEnabled(StableSwapper.FeatureFlag.SWAP));
    }
}
