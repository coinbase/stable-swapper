// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {StableSwapperBase} from "./StableSwapperBase.sol";

/**
 * @title InitializeTest
 * @notice Tests for the StableSwapper initialize function
 */
contract InitializeTest is StableSwapperBase {
    function test_setsAllInitialValues() public view {
        assertTrue(swapper.hasRole(swapper.UPGRADE_AUTHORITY(), upgradeAuthority));
        assertTrue(swapper.hasRole(swapper.OPERATIONS_AUTHORITY(), operationsAuthority));
        assertTrue(swapper.hasRole(swapper.PAUSE_AUTHORITY(), pauseAuthority));
        assertEq(swapper.feeRecipient(), feeRecipient);
        assertEq(swapper.feeRate(), 0);
        assertFalse(swapper.swapsPaused());
        assertFalse(swapper.liquidityPaused());
        assertEq(swapper.getSupportedTokensCount(), 0);
        assertFalse(swapper.whitelistEnabled());
    }
}

