// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {StableSwapperPriceFeed} from "../../../src/StableSwapperPriceFeed.sol";

import {StableSwapperPriceFeedBase} from "../../lib/StableSwapperPriceFeedBase.sol";

/**
 * @title GetPriceTest
 * @notice Tests for the StableSwapperPriceFeed constructor, getters, and getPrice function
 */
contract GetPriceTest is StableSwapperPriceFeedBase {
    /*//////////////////////////////////////////////////////////////
                              REVERT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_constructor_reverts_whenStableSwapperIsZeroAddress() public {
        vm.expectRevert(StableSwapperPriceFeed.ZeroAddress.selector);
        new StableSwapperPriceFeed(address(0));
    }

    function test_getPrice_reverts_whenTokenNotListed() public {
        expectTokenNotListedRevert(address(customStable));
        priceFeed.getPrice(address(customStable));
    }

    function test_getPrice_reverts_whenTokenUnlisted() public {
        listToken(address(customStable));
        assertEq(priceFeed.getPrice(address(customStable)), 1e6);

        unlistToken(address(customStable));

        expectTokenNotListedRevert(address(customStable));
        priceFeed.getPrice(address(customStable));
    }

    function testFuzz_getPrice_reverts_whenTokenNotListed(address token) public {
        listToken(address(usdc));
        listToken(address(customStable));
        vm.assume(token != address(usdc) && token != address(customStable));

        expectTokenNotListedRevert(token);
        priceFeed.getPrice(token);
    }

    /*//////////////////////////////////////////////////////////////
                            SUCCESS TESTS
    //////////////////////////////////////////////////////////////*/

    function test_constructor_setsGetters() public view {
        assertEq(address(priceFeed.STABLE_SWAPPER()), address(swapper));
        assertEq(priceFeed.PRICE(), 1e6);
        assertEq(priceFeed.PRICE_DECIMALS(), 6);
    }

    function test_getPrice_returnsOne_whenCustomStableListed() public {
        listToken(address(customStable));

        assertEq(priceFeed.getPrice(address(customStable)), 1e6);
    }

    function test_getPrice_returnsOne_whenUsdcListed() public {
        listToken(address(usdc));

        assertEq(priceFeed.getPrice(address(usdc)), 1e6);
    }

    function test_getPrice_returnsOne_whenTokenListedButNotSwappable() public {
        listToken(address(customStable));
        updateTokenStatus(address(customStable), true);
        updateTokenStatus(address(customStable), false);

        assertFalse(swapper.isTokenSwappable(address(customStable)));
        assertEq(priceFeed.getPrice(address(customStable)), 1e6);
    }
}
