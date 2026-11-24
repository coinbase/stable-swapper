// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

/// @title IStableSwapperListing
/// @notice The subset of the StableSwapper interface that the price feed reads
interface IStableSwapperListing {
    /// @notice Returns whether a token is listed in the StableSwapper
    ///
    /// @param token Address of the token
    ///
    /// @return True if the token is listed, false otherwise
    function isTokenListed(address token) external view returns (bool);
}

/// @title StableSwapperPriceFeed
/// @notice A read-only price feed that quotes every token listed in the StableSwapper at 1 USDC
///
/// @dev The StableSwapper swaps listed stablecoins 1:1 (after decimal normalization) with USDC, so a
/// @dev listed token is always redeemable at par through the swapper. This feed exposes that par value
/// @dev for off-chain price consumers such as CoinGecko's Virtual Price, which `eth_call` `getPrice`.
///
/// @dev The price is pinned at 1 regardless of pool liquidity, fees, or whether swaps are paused. It
/// @dev reflects the swapper's listing, not a market price, and must not be used as an on-chain oracle.
/// @dev Listing a token in the StableSwapper is the only step needed for the feed to price it.
///
/// @dev The feed has no owner, no roles, no storage, and is not upgradeable. It points at the
/// @dev StableSwapper proxy, whose address stays the same across UUPS upgrades.
///
/// @author Coinbase
contract StableSwapperPriceFeed {
    /// @notice Number of decimals in the returned price, matching USDC
    uint8 public constant PRICE_DECIMALS = 6;

    /// @notice The price returned for every listed token (1.000000 USDC)
    uint256 public constant PRICE = 10 ** PRICE_DECIMALS;

    /// @notice The StableSwapper proxy whose listing decides which tokens are priced
    IStableSwapperListing public immutable STABLE_SWAPPER;

    /// @notice Thrown when the constructor receives the zero address
    error ZeroAddress();

    /// @notice Thrown when a price is requested for a token the StableSwapper does not list
    ///
    /// @param token Address of the unlisted token
    error TokenNotListed(address token);

    /// @notice Creates the price feed
    ///
    /// @param stableSwapper Address of the StableSwapper proxy (not the implementation)
    constructor(address stableSwapper) {
        require(stableSwapper != address(0), ZeroAddress());
        STABLE_SWAPPER = IStableSwapperListing(stableSwapper);
    }

    /// @notice Returns the price of `token` in USDC, with `PRICE_DECIMALS` decimals
    ///
    /// @dev Reverts for unlisted tokens so consumers never read a price for a token the swapper
    /// @dev does not back. Listed tokens that are paused (not swappable) are still priced, so a
    /// @dev temporary pause does not blank the price.
    ///
    /// @param token Address of the token to price
    ///
    /// @return The price of one whole `token` in USDC (always `PRICE`)
    function getPrice(address token) external view returns (uint256) {
        require(STABLE_SWAPPER.isTokenListed(token), TokenNotListed(token));
        return PRICE;
    }
}
