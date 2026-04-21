use anchor_lang::prelude::*;

#[error_code]
pub enum LiquidityError {
    #[msg("Swaps are paused")]
    SwapsPaused,
    #[msg("Liquidity management is paused")]
    LiquidityPaused,
    #[msg("Invalid amount")]
    InvalidAmount,
    #[msg("Token not supported")]
    TokenNotSupported,
    #[msg("Token already supported")]
    TokenAlreadySupported,
    #[msg("Cannot swap same token")]
    SameToken,
    #[msg("Insufficient liquidity")]
    InsufficientLiquidity,
    #[msg("Invalid fee rate")]
    InvalidFeeRate,
    #[msg("Invalid reserved amount")]
    InvalidReservedAmount,
    #[msg("Maximum number of supported tokens reached (50)")]
    MaxTokensReached,
    #[msg("Output amount below minimum acceptable (slippage exceeded)")]
    SlippageExceeded,
    #[msg("Invalid token decimals: must be between 6 and 9")]
    InvalidTokenDecimals,
    #[msg("Arithmetic overflow in fee calculation")]
    FeeCalculationOverflow,
    #[msg("Arithmetic overflow in decimal normalization")]
    DecimalNormalizationOverflow,
    #[msg("Token is disabled and cannot be used in swaps")]
    TokenDisabled,
    #[msg("User address is not whitelisted")]
    NotWhitelisted,
    #[msg("Maximum number of whitelisted addresses reached")]
    MaxWhitelistedAddressesReached,
    #[msg("Address is already whitelisted")]
    AddressAlreadyWhitelisted,
    #[msg("Address not found in whitelist")]
    AddressNotInWhitelist,
    #[msg("Invalid whitelist account provided")]
    InvalidWhitelistAccount,
    #[msg("Token not found in supported tokens list")]
    TokenNotFound,
    #[msg("Token must be disabled before removal")]
    TokenMustBeDisabled,
    #[msg("Vault must be empty before removing token")]
    VaultNotEmpty,
}
