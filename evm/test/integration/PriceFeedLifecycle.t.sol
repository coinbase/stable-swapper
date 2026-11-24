// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";

import {StableSwapper} from "../../src/StableSwapper.sol";
import {MockERC20} from "../lib/StableSwapperBase.sol";
import {StableSwapperPriceFeedBase} from "../lib/StableSwapperPriceFeedBase.sol";

/// @title PriceFeedLifecycleTest
/// @notice Integration tests for the price feed across a token launch lifecycle and a swapper upgrade
/// @dev The feed is deployed once and never changed; every step only touches the swapper
contract PriceFeedLifecycleTest is StableSwapperPriceFeedBase {
    MockERC20 public newStable; // 18 decimals, launched after the feed is deployed

    function setUp() public override {
        super.setUp();
        setupBasicSwapEnvironment();
        newStable = new MockERC20("New Stable", "NSTBL", 18);
    }

    /// @dev Covers:
    /// 1. A new token has no price before listing
    /// 2. Listing it prices it with no feed change
    /// 3. Enabling swaps keeps the price
    /// 4. Pausing the token and global swaps keeps the price
    /// 5. Unlisting it removes the price
    function test_priceFeed_tokenLaunchLifecycle() public {
        address feedBefore = address(priceFeed);

        // PHASE 1: Not listed yet
        expectTokenNotListedRevert(address(newStable));
        priceFeed.getPrice(address(newStable));

        // PHASE 2: List the token
        listToken(address(newStable));
        assertEq(priceFeed.getPrice(address(newStable)), 1e6);

        // PHASE 3: Enable swaps
        updateTokenStatus(address(newStable), true);
        assertEq(priceFeed.getPrice(address(newStable)), 1e6);

        // PHASE 4: Pause the token and global swaps
        updateTokenStatus(address(newStable), false);
        vm.prank(pauseAuthority);
        swapper.setFeatureFlag(StableSwapper.FeatureFlag.SWAP, false);
        assertFalse(swapper.isFeatureEnabled(StableSwapper.FeatureFlag.SWAP));
        assertEq(priceFeed.getPrice(address(newStable)), 1e6);

        // PHASE 5: Unlist the token
        unlistToken(address(newStable));
        expectTokenNotListedRevert(address(newStable));
        priceFeed.getPrice(address(newStable));

        // Existing listings are unaffected and the feed itself never changed
        assertEq(priceFeed.getPrice(address(usdc)), 1e6);
        assertEq(priceFeed.getPrice(address(customStable)), 1e6);
        assertEq(address(priceFeed), feedBefore);
    }

    /// @dev The feed points at the proxy, so it keeps answering after the swapper is upgraded
    function test_priceFeed_survivesSwapperUpgrade() public {
        StableSwapper newImplementation = new StableSwapper();

        vm.prank(defaultAdmin);
        swapper.upgradeToAndCall(address(newImplementation), "");

        bytes32 implementationSlot = vm.load(address(swapper), ERC1967Utils.IMPLEMENTATION_SLOT);
        assertEq(address(uint160(uint256(implementationSlot))), address(newImplementation));
        assertEq(address(priceFeed.STABLE_SWAPPER()), address(swapper));
        assertEq(priceFeed.getPrice(address(usdc)), 1e6);
        assertEq(priceFeed.getPrice(address(customStable)), 1e6);

        // Listing changes after the upgrade still flow through
        listToken(address(newStable));
        assertEq(priceFeed.getPrice(address(newStable)), 1e6);

        updateTokenStatus(address(customStable), false);
        unlistToken(address(customStable));
        expectTokenNotListedRevert(address(customStable));
        priceFeed.getPrice(address(customStable));
    }
}
