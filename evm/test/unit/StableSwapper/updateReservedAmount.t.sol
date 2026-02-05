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

    function test_updateReservedAmount_reverts_whenTokenNotListed() public {
        uint64 reservedAmount = 100 * 10 ** 6;
        vm.prank(treasuryAuthority);
        vm.expectRevert(abi.encodeWithSelector(StableSwapper.TokenNotListed.selector, address(usdc)));
        swapper.updateReservedAmount(address(usdc), reservedAmount);
    }

    /*//////////////////////////////////////////////////////////////
                            SUCCESS TESTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Fuzz test: Any reserved amount can be set regardless of current balance
     * @dev Tests that reserved amounts can be set flexibly
     */
    function testFuzz_updateReservedAmount_updatesReservedAmount(uint256 reservedAmountSeed) public {
        uint64 liquidityAmount = 500 * 10 ** 6;
        uint64 reservedAmount = uint64(bound(reservedAmountSeed, 0, type(uint256).max));

        vm.prank(configureAuthority);
        swapper.updateTokenListing(address(usdc), true);

        vm.prank(treasuryAuthority);
        usdc.transfer(address(swapper), liquidityAmount);

        vm.prank(treasuryAuthority);
        swapper.updateReservedAmount(address(usdc), reservedAmount);

        assertEq(swapper.getReservedAmount(address(usdc)), reservedAmount);
    }
}
