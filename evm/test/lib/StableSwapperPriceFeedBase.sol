// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {StableSwapperPriceFeed} from "../../src/StableSwapperPriceFeed.sol";

import {StableSwapperBase} from "./StableSwapperBase.sol";

/**
 * @title StableSwapperPriceFeedBase
 * @notice Base contract for StableSwapperPriceFeed tests that deploys the feed against the base swapper proxy
 */
contract StableSwapperPriceFeedBase is StableSwapperBase {
    StableSwapperPriceFeed public priceFeed;

    function setUp() public virtual override {
        super.setUp();
        priceFeed = new StableSwapperPriceFeed(address(swapper));
    }

    function listToken(address token) internal {
        vm.prank(configureAuthority);
        swapper.updateTokenListing(token, true);
    }

    function unlistToken(address token) internal {
        vm.prank(configureAuthority);
        swapper.updateTokenListing(token, false);
    }

    function updateTokenStatus(address token, bool isSwappable) internal {
        vm.prank(pauseAuthority);
        swapper.updateTokenStatus(token, isSwappable);
    }

    function expectTokenNotListedRevert(address token) internal {
        vm.expectRevert(abi.encodeWithSelector(StableSwapperPriceFeed.TokenNotListed.selector, token));
    }
}
