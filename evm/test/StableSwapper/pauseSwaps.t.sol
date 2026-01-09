// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {StableSwapperBase} from "./StableSwapperBase.sol";

/**
 * @title PauseSwapsTest
 * @notice Tests for the StableSwapper updateSwapStatus/updateLiquidityStatus functions
 */
contract PauseSwapsTest is StableSwapperBase {
    /*//////////////////////////////////////////////////////////////
                              REVERT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_updateSwapStatus_reverts_whenUnauthorizedUser() public {
        address unauthorized = makeAddr("unauthorized");

        vm.prank(unauthorized);
        vm.expectRevert();
        swapper.updateSwapStatus(false);
    }

    /*//////////////////////////////////////////////////////////////
                            SUCCESS TESTS
    //////////////////////////////////////////////////////////////*/

    function test_updateSwapStatus_pausesSwaps() public {
        vm.prank(pauseAuthority);
        swapper.updateSwapStatus(false);

        assertFalse(swapper.swapsEnabled());
        assertTrue(swapper.liquidityEnabled());
    }

    function test_updateSwapStatus_unpausesSwaps() public {
        vm.startPrank(pauseAuthority);
        swapper.updateSwapStatus(false);
        swapper.updateSwapStatus(true);
        vm.stopPrank();

        assertTrue(swapper.swapsEnabled());
    }
}
