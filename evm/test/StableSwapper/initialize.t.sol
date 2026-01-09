// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {StableSwapper} from "../../src/StableSwapper.sol";
import {StableSwapperBase} from "./StableSwapperBase.sol";

/**
 * @title InitializeTest
 * @notice Tests for the StableSwapper initialize function
 */
contract InitializeTest is StableSwapperBase {
    /*//////////////////////////////////////////////////////////////
                              REVERT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_initialize_reverts_whenCalledTwice() public {
        // Try to initialize again on already initialized contract
        vm.expectRevert();
        swapper.initialize(upgradeAuthority, operationsAuthority, pauseAuthority, feeRecipient, 0);
    }

    function test_initialize_reverts_whenFeeRateIsExactlyAboveMaximum() public {
        // Deploy new implementation
        StableSwapper newImplementation = new StableSwapper();

        uint64 maxFeeRate = swapper.MAX_FEE_RATE(); // 1000 basis points (10%)
        uint64 invalidFeeRate = maxFeeRate + 1;

        bytes memory initData = abi.encodeWithSelector(
            StableSwapper.initialize.selector,
            upgradeAuthority,
            operationsAuthority,
            pauseAuthority,
            feeRecipient,
            invalidFeeRate
        );

        vm.expectRevert(abi.encodeWithSelector(StableSwapper.FeeRateExceedsMaximum.selector, invalidFeeRate));
        new ERC1967Proxy(address(newImplementation), initData);
    }

    /*//////////////////////////////////////////////////////////////
                            SUCCESS TESTS
    //////////////////////////////////////////////////////////////*/

    function test_initialize_setsAllInitialValues() public view {
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

    function test_initialize_allowsMaximumFeeRate() public {
        // Deploy new implementation
        StableSwapper newImplementation = new StableSwapper();

        uint64 maxFeeRate = swapper.MAX_FEE_RATE(); // 1000 basis points (10%)

        bytes memory initData = abi.encodeWithSelector(
            StableSwapper.initialize.selector,
            upgradeAuthority,
            operationsAuthority,
            pauseAuthority,
            feeRecipient,
            maxFeeRate
        );

        // Should not revert with maximum fee rate
        ERC1967Proxy newProxy = new ERC1967Proxy(address(newImplementation), initData);
        StableSwapper newSwapper = StableSwapper(address(newProxy));

        assertEq(newSwapper.feeRate(), maxFeeRate);
    }

    function test_initialize_allowsZeroAddressForAuthorities() public {
        // Deploy new implementation
        StableSwapper newImplementation = new StableSwapper();

        // Zero addresses for authorities should be allowed (they just won't have permissions)
        bytes memory initData = abi.encodeWithSelector(
            StableSwapper.initialize.selector,
            address(0), // upgradeAuthority
            address(0), // operationsAuthority
            address(0), // pauseAuthority
            address(0), // feeRecipient
            uint64(0)
        );

        // Should not revert
        ERC1967Proxy newProxy = new ERC1967Proxy(address(newImplementation), initData);
        StableSwapper newSwapper = StableSwapper(address(newProxy));

        assertEq(newSwapper.feeRecipient(), address(0));
    }

    function test_initialize_setsContractVersion() public view {
        assertEq(swapper.contractVersion(), 1);
    }
}
