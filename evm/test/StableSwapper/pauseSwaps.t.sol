// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {StableSwapperBase} from "./StableSwapperBase.sol";

/**
 * @title PauseSwapsTest
 * @notice Tests for the StableSwapper pauseSwaps/unpauseSwaps functions
 */
contract PauseSwapsTest is StableSwapperBase {
    /*//////////////////////////////////////////////////////////////
                              REVERT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_pauseSwaps_reverts_whenUnauthorizedUser() public {
        address unauthorized = makeAddr("unauthorized");

        vm.prank(unauthorized);
        vm.expectRevert();
        swapper.pauseSwaps();
    }

    function test_unpauseSwaps_reverts_whenUnauthorizedUser() public {
        // First pause swaps
        vm.prank(pauseAuthority);
        swapper.pauseSwaps();

        // Try to unpause with unauthorized user
        address unauthorized = makeAddr("unauthorized");
        vm.prank(unauthorized);
        vm.expectRevert();
        swapper.unpauseSwaps();
    }

    /*//////////////////////////////////////////////////////////////
                            SUCCESS TESTS
    //////////////////////////////////////////////////////////////*/

    function test_pauseSwaps_pausesSwaps() public {
        vm.prank(pauseAuthority);
        swapper.pauseSwaps();

        assertTrue(swapper.swapsPaused());
        assertFalse(swapper.liquidityPaused());
    }

    function test_unpauseSwaps_unpausesSwaps() public {
        vm.startPrank(pauseAuthority);
        swapper.pauseSwaps();
        swapper.unpauseSwaps();
        vm.stopPrank();

        assertFalse(swapper.swapsPaused());
    }
}
