// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {StableSwapper} from "../../../src/StableSwapper.sol";

import {StableSwapperBase} from "../../lib/StableSwapperBase.sol";

/**
 * @title UpdateReservedAmountTest
 * @notice Tests for the StableSwapper updateReservedAmount function
 */
contract UpdateReservedAmountTest is StableSwapperBase {
    /*//////////////////////////////////////////////////////////////
                              REVERT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_updateReservedAmount_reverts_whenUnauthorizedUser() public {
        uint64 reservedAmount = 100 * 10 ** 6;
        vm.prank(configureAuthority);
        swapper.updateTokenListing(address(usdc), true);

        address unauthorized = makeAddr("unauthorized");

        vm.prank(unauthorized);
        vm.expectRevert();
        swapper.updateReservedAmount(address(usdc), reservedAmount);
    }

    function test_updateReservedAmount_reverts_whenTokenIsZeroAddress() public {
        uint64 reservedAmount = 100 * 10 ** 6;
        vm.prank(withdrawalAuthority);
        vm.expectRevert(StableSwapper.CannotBeZeroAddress.selector);
        swapper.updateReservedAmount(address(0), reservedAmount);
    }

    function test_updateReservedAmount_reverts_whenTokenNotListed() public {
        uint64 reservedAmount = 100 * 10 ** 6;
        vm.prank(withdrawalAuthority);
        vm.expectRevert(abi.encodeWithSelector(StableSwapper.TokenNotListed.selector, address(usdc)));
        swapper.updateReservedAmount(address(usdc), reservedAmount);
    }

    /**
     * @notice Fuzz test: Any reserved amount greater than liquidity amount should revert
     * @dev Tests that reserved amount cannot exceed liquidity amount
     */
    function testFuzz_updateReservedAmount_reverts_whenReservedAmountExceedsBalance(uint256 reservedAmountSeed) public {
        uint64 liquidityAmount = 100 * 10 ** 6;
        uint64 reservedAmount = uint64(bound(reservedAmountSeed, liquidityAmount + 1, type(uint64).max));

        vm.prank(configureAuthority);
        swapper.updateTokenListing(address(usdc), true);

        vm.prank(withdrawalAuthority);
        usdc.transfer(address(swapper), liquidityAmount);

        vm.prank(withdrawalAuthority);
        vm.expectRevert(
            abi.encodeWithSelector(
                StableSwapper.ReservedAmountExceedsBalance.selector, address(usdc), reservedAmount, liquidityAmount
            )
        );
        swapper.updateReservedAmount(address(usdc), reservedAmount);
    }

    /*//////////////////////////////////////////////////////////////
                            SUCCESS TESTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Fuzz test: Any valid reserved amount (0-liquidityAmount) should be accepted
     * @dev Tests that all reserved amounts within valid range can be set
     */
    function testFuzz_updateReservedAmount_updatesReservedAmount(uint256 reservedAmountSeed) public {
        uint64 liquidityAmount = 500 * 10 ** 6;
        uint64 reservedAmount = uint64(bound(reservedAmountSeed, 0, liquidityAmount));

        vm.prank(configureAuthority);
        swapper.updateTokenListing(address(usdc), true);

        vm.prank(withdrawalAuthority);
        usdc.transfer(address(swapper), liquidityAmount);

        vm.prank(withdrawalAuthority);
        swapper.updateReservedAmount(address(usdc), reservedAmount);

        assertEq(swapper.getReservedAmount(address(usdc)), reservedAmount);
    }
}
