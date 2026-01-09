// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {StableSwapperBase} from "./StableSwapperBase.sol";

/**
 * @title PauseSwapsTest
 * @notice Tests for the StableSwapper pauseSwaps/unpauseSwaps functions
 */
contract PauseSwapsTest is StableSwapperBase {
    function test_pausesSwaps() public {
        vm.prank(pauseAuthority);
        swapper.pauseSwaps();
        
        assertTrue(swapper.swapsPaused());
        assertFalse(swapper.liquidityPaused());
    }
    
    function test_unpausesSwaps() public {
        vm.startPrank(pauseAuthority);
        swapper.pauseSwaps();
        swapper.unpauseSwaps();
        vm.stopPrank();
        
        assertFalse(swapper.swapsPaused());
    }
}

