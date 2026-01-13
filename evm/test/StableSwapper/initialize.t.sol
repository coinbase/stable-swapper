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
        swapper.initialize(defaultAdmin, treasuryAuthority, configureAuthority, pauseAuthority, feeRecipient, 0, 0);
    }

    function test_initialize_reverts_whenDefaultAdminIsZeroAddress() public {
        // Deploy new implementation
        StableSwapper newImplementation = new StableSwapper();

        // OpenZeppelin's AccessControlDefaultAdminRules does not allow zero address for DEFAULT_ADMIN_ROLE
        bytes memory initData = abi.encodeWithSelector(
            StableSwapper.initialize.selector,
            address(0), // defaultAdmin - not allowed
            treasuryAuthority,
            configureAuthority,
            pauseAuthority,
            feeRecipient,
            uint64(0),
            uint48(0)
        );

        // Should revert with AccessControlInvalidDefaultAdmin
        vm.expectRevert();
        new ERC1967Proxy(address(newImplementation), initData);
    }

    function test_initialize_reverts_whenFeeRateIsExactlyAboveMaximum() public {
        // Deploy new implementation
        StableSwapper newImplementation = new StableSwapper();

        uint64 maxFeeRate = swapper.MAX_FEE_RATE(); // 1000 basis points (10%)
        uint64 invalidFeeRate = maxFeeRate + 1;

        bytes memory initData = abi.encodeWithSelector(
            StableSwapper.initialize.selector,
            defaultAdmin,
            treasuryAuthority,
            configureAuthority,
            pauseAuthority,
            feeRecipient,
            invalidFeeRate,
            uint48(0)
        );

        vm.expectRevert(abi.encodeWithSelector(StableSwapper.FeeRateExceedsMaximum.selector, invalidFeeRate));
        new ERC1967Proxy(address(newImplementation), initData);
    }

    /*//////////////////////////////////////////////////////////////
                            SUCCESS TESTS
    //////////////////////////////////////////////////////////////*/

    function test_initialize_setsAllInitialValues() public view {
        assertTrue(swapper.hasRole(swapper.DEFAULT_ADMIN_ROLE(), defaultAdmin));
        assertTrue(swapper.hasRole(swapper.TREASURY_AUTHORITY(), treasuryAuthority));
        assertTrue(swapper.hasRole(swapper.CONFIGURE_AUTHORITY(), configureAuthority));
        assertTrue(swapper.hasRole(swapper.PAUSE_AUTHORITY(), pauseAuthority));
        assertEq(swapper.feeRecipient(), feeRecipient);
        assertEq(swapper.feeRate(), 0);
        assertTrue(swapper.swapsEnabled());
        assertTrue(swapper.liquidityEnabled());
        assertEq(swapper.getSupportedTokensCount(), 0);
        assertFalse(swapper.whitelistEnabled());
    }

    function test_initialize_allowsMaximumFeeRate() public {
        // Deploy new implementation
        StableSwapper newImplementation = new StableSwapper();

        uint64 maxFeeRate = swapper.MAX_FEE_RATE(); // 1000 basis points (10%)

        bytes memory initData = abi.encodeWithSelector(
            StableSwapper.initialize.selector,
            defaultAdmin,
            treasuryAuthority,
            configureAuthority,
            pauseAuthority,
            feeRecipient,
            maxFeeRate,
            uint48(0)
        );

        // Should not revert with maximum fee rate
        ERC1967Proxy newProxy = new ERC1967Proxy(address(newImplementation), initData);
        StableSwapper newSwapper = StableSwapper(address(newProxy));

        assertEq(newSwapper.feeRate(), maxFeeRate);
    }

    function test_initialize_allowsZeroAddressForOtherAuthorities() public {
        // Deploy new implementation
        StableSwapper newImplementation = new StableSwapper();

        // Zero addresses for non-admin authorities should be allowed (they just won't have permissions)
        bytes memory initData = abi.encodeWithSelector(
            StableSwapper.initialize.selector,
            defaultAdmin,
            address(0), // treasuryAuthority - allowed
            address(0), // configureAuthority - allowed
            address(0), // pauseAuthority - allowed
            address(0), // feeRecipient - allowed
            uint64(0),
            uint48(0)
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
