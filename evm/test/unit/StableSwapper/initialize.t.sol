// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {StableSwapper} from "../../../src/StableSwapper.sol";

import {StableSwapperBase} from "../../lib/StableSwapperBase.sol";

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
        swapper.initialize(defaultAdmin, withdrawalAuthority, configureAuthority, pauseAuthority, feeRecipient, 0, 0);
    }

    function test_initialize_reverts_whenDefaultAdminIsZeroAddress() public {
        // Deploy new implementation
        StableSwapper newImplementation = new StableSwapper();

        // OpenZeppelin's AccessControlDefaultAdminRules does not allow zero address for DEFAULT_ADMIN_ROLE
        bytes memory initData = abi.encodeWithSelector(
            StableSwapper.initialize.selector,
            address(0), // defaultAdmin - not allowed
            withdrawalAuthority,
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

    function testFuzz_initialize_reverts_whenFeeBasisPointsExceedsDenominator(uint16 invalidFee) public {
        // Bound the fee to be greater than FEE_DENOMINATOR (10000)
        vm.assume(invalidFee > swapper.FEE_DENOMINATOR());

        // Deploy new implementation
        StableSwapper newImplementation = new StableSwapper();

        bytes memory initData = abi.encodeWithSelector(
            StableSwapper.initialize.selector,
            defaultAdmin,
            withdrawalAuthority,
            configureAuthority,
            pauseAuthority,
            feeRecipient,
            invalidFee, // Fee exceeds 100%
            uint48(0)
        );

        // Should revert with FeeExceedsDenominator
        vm.expectRevert(abi.encodeWithSelector(StableSwapper.FeeExceedsDenominator.selector, invalidFee));
        new ERC1967Proxy(address(newImplementation), initData);
    }

    function test_initialize_reverts_whenFeeRecipientIsZeroAddress() public {
        // Deploy new implementation
        StableSwapper newImplementation = new StableSwapper();

        bytes memory initData = abi.encodeWithSelector(
            StableSwapper.initialize.selector,
            defaultAdmin,
            withdrawalAuthority,
            configureAuthority,
            pauseAuthority,
            address(0), // feeRecipient - not allowed
            uint16(0),
            uint48(0)
        );

        // Should revert with CannotBeZeroAddress
        vm.expectRevert(StableSwapper.CannotBeZeroAddress.selector);
        new ERC1967Proxy(address(newImplementation), initData);
    }

    /*//////////////////////////////////////////////////////////////
                            SUCCESS TESTS
    //////////////////////////////////////////////////////////////*/

    function test_initialize_setsAllInitialValues() public view {
        assertTrue(swapper.hasRole(swapper.DEFAULT_ADMIN_ROLE(), defaultAdmin));
        assertTrue(swapper.hasRole(swapper.TREASURY_ROLE(), withdrawalAuthority));
        assertTrue(swapper.hasRole(swapper.CONFIGURE_ROLE(), configureAuthority));
        assertTrue(swapper.hasRole(swapper.PAUSE_ROLE(), pauseAuthority));
        assertEq(swapper.feeRecipient(), feeRecipient);
        assertEq(swapper.feeBasisPoints(), 0);
        assertTrue(swapper.isFeatureEnabled(StableSwapper.FeatureFlag.SWAP));
        assertTrue(swapper.isFeatureEnabled(StableSwapper.FeatureFlag.WITHDRAW));
        assertEq(swapper.getListedTokensCount(), 0);
        assertFalse(swapper.isFeatureEnabled(StableSwapper.FeatureFlag.ALLOWLIST));
    }

    function test_initialize_allowsZeroAddressForOtherAuthorities() public {
        // Deploy new implementation
        StableSwapper newImplementation = new StableSwapper();

        // Zero addresses for non-admin authorities should be allowed (they just won't have permissions)
        // However, feeRecipient must be non-zero
        bytes memory initData = abi.encodeWithSelector(
            StableSwapper.initialize.selector,
            defaultAdmin,
            address(0), // withdrawalAuthority - allowed
            address(0), // configureAuthority - allowed
            address(0), // pauseAuthority - allowed
            feeRecipient, // feeRecipient - must be non-zero
            uint64(0),
            uint48(0)
        );

        // Should not revert
        ERC1967Proxy newProxy = new ERC1967Proxy(address(newImplementation), initData);
        StableSwapper newSwapper = StableSwapper(address(newProxy));

        assertEq(newSwapper.feeRecipient(), feeRecipient);
    }

    function testFuzz_initialize_allowsValidFeeBasisPoints(uint16 validFee) public {
        // Bound the fee to be less than or equal to FEE_DENOMINATOR (10000)
        vm.assume(validFee <= swapper.FEE_DENOMINATOR());

        // Deploy new implementation
        StableSwapper newImplementation = new StableSwapper();

        bytes memory initData = abi.encodeWithSelector(
            StableSwapper.initialize.selector,
            defaultAdmin,
            withdrawalAuthority,
            configureAuthority,
            pauseAuthority,
            feeRecipient,
            validFee, // Valid fee (0-100%)
            uint48(0)
        );

        // Should not revert with valid fee
        ERC1967Proxy newProxy = new ERC1967Proxy(address(newImplementation), initData);
        StableSwapper newSwapper = StableSwapper(address(newProxy));

        assertEq(newSwapper.feeBasisPoints(), validFee);
    }
}
