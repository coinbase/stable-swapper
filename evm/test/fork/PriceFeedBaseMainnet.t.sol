// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {StableSwapperPriceFeed} from "../../src/StableSwapperPriceFeed.sol";

/// @title PriceFeedBaseMainnetTest
/// @notice Fork tests that deploy the price feed against the live Base mainnet StableSwapper proxy
/// @dev Runs only when BASE_RPC_URL is set, so CI without an RPC skips it
/// @dev Pinned to a block where the listings below were verified, since listings can change on-chain.
/// @dev Set BASE_FORK_BLOCK to check another block.
contract PriceFeedBaseMainnetTest is Test {
    uint256 internal constant FORK_BLOCK = 61_785_161;

    address internal constant STABLE_SWAPPER_PROXY = 0x57AB1E77a6E70074307f39173176B94043A8C33c;

    address internal constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address internal constant ONED = 0x10ED0050b7A5d5e1E9Cc164F77a71d0bF69f64BD;
    address internal constant USDSL = 0x362500574b36097c263e394D3CDEEFa321786Ed8;
    // Listed but not swappable
    address internal constant USDR = 0x7246004e0daBB5b24Ed0CB901A04bA273CB22480;
    // Not listed
    address internal constant RUSD = 0xB2000000000000000000014fCD75cd1000D011a5;

    StableSwapperPriceFeed public priceFeed;

    function setUp() public {
        string memory rpcUrl = vm.envOr("BASE_RPC_URL", string(""));
        if (bytes(rpcUrl).length == 0) {
            vm.skip(true);
            return;
        }

        vm.createSelectFork(rpcUrl, vm.envOr("BASE_FORK_BLOCK", FORK_BLOCK));
        priceFeed = new StableSwapperPriceFeed(STABLE_SWAPPER_PROXY);
    }

    function test_fork_getPrice_returnsOne_forListedTokens() public view {
        assertEq(priceFeed.getPrice(USDC), 1e6);
        assertEq(priceFeed.getPrice(ONED), 1e6);
        assertEq(priceFeed.getPrice(USDSL), 1e6);
        assertEq(priceFeed.getPrice(USDR), 1e6);
    }

    function test_fork_getPrice_reverts_forUnlistedToken() public {
        vm.expectRevert(abi.encodeWithSelector(StableSwapperPriceFeed.TokenNotListed.selector, RUSD));
        priceFeed.getPrice(RUSD);
    }
}
