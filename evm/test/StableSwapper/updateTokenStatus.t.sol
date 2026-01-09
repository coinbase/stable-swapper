// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {StableSwapper} from "../../src/StableSwapper.sol";
import {StableSwapperBase} from "./StableSwapperBase.sol";

/**
 * @title UpdateTokenStatusTest
 * @notice Tests for the StableSwapper updateTokenStatus function
 */
contract UpdateTokenStatusTest is StableSwapperBase {
    /*//////////////////////////////////////////////////////////////
                              REVERT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_updateTokenStatus_reverts_whenUnauthorizedUser() public {
        vm.prank(operationsAuthority);
        swapper.addToken(address(usdc));

        address unauthorized = makeAddr("unauthorized");

        vm.prank(unauthorized);
        vm.expectRevert();
        swapper.updateTokenStatus(address(usdc), false);
    }

    function test_updateTokenStatus_reverts_whenTokenIsZeroAddress() public {
        vm.prank(pauseAuthority);
        vm.expectRevert(abi.encodeWithSelector(StableSwapper.CannotBeZeroAddress.selector, address(0)));
        swapper.updateTokenStatus(address(0), false);
    }

    function test_updateTokenStatus_reverts_whenTokenNotSupported() public {
        vm.prank(pauseAuthority);
        vm.expectRevert(abi.encodeWithSelector(StableSwapper.TokenNotSupported.selector, address(usdc)));
        swapper.updateTokenStatus(address(usdc), false);
    }

    /*//////////////////////////////////////////////////////////////
                            SUCCESS TESTS
    //////////////////////////////////////////////////////////////*/

    function test_updateTokenStatus_disablesToken() public {
        setupBasicSwapEnvironment();

        bool disabledStatus = false;

        // Disable USDC
        vm.prank(pauseAuthority);
        swapper.updateTokenStatus(address(usdc), disabledStatus);

        StableSwapper.TokenVault memory vault = swapper.getVault(address(usdc));
        assertFalse(vault.isEnabled);
    }

    function test_updateTokenStatus_reEnablesToken() public {
        setupBasicSwapEnvironment();

        bool disabledStatus = false;
        bool enabledStatus = true;

        // Disable then re-enable USDC
        vm.startPrank(pauseAuthority);
        swapper.updateTokenStatus(address(usdc), disabledStatus);
        swapper.updateTokenStatus(address(usdc), enabledStatus);
        vm.stopPrank();

        StableSwapper.TokenVault memory vault = swapper.getVault(address(usdc));
        assertTrue(vault.isEnabled);

        // Swap should succeed
        uint64 swapAmount = 10 * 10 ** 6;
        uint64 minAmountOut = 10 * 10 ** 6;

        vm.startPrank(wallet0);
        usdc.approve(address(swapper), swapAmount);
        swapper.swap(address(usdc), address(appStable), swapAmount, minAmountOut, wallet0);
        vm.stopPrank();
    }
}
