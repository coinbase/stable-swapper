use crate::constants::MAX_SUPPORTED_TOKENS;
use anchor_lang::prelude::*;

#[account]
pub struct LiquidityPool {
    pub operations_authority: Pubkey,
    pub pause_authority: Pubkey,
    pub fee_recipient: Pubkey,
    pub supported_tokens: Vec<Pubkey>,
    pub fee_rate: u64, // in basis points
    pub swaps_paused: bool,
    /// Controls the withdraw_liquidity instruction only.
    /// Note: Deposits go directly to vault_token_account via SPL Token transfers and are not gated.
    pub liquidity_paused: bool,
    pub bump: u8,
}

impl LiquidityPool {
    pub const INIT_SPACE: usize = 32 + 32 + 32 + (4 + 32 * MAX_SUPPORTED_TOKENS) + 8 + 1 + 1 + 1; // operations_authority + pause_authority + fee_recipient + supported_tokens + fee_rate + swaps_paused + liquidity_paused + bump
}

#[account]
pub struct TokenVault {
    pub mint: Pubkey,
    /// Deprecated: liquidity reservation was removed.
    #[deprecated(
        note = "Liquidity reservation was removed; field retained for layout compatibility and is always zero on new vaults."
    )]
    pub reserved_amount: u64,
    pub disabled: bool, // If true, this token cannot be used in swaps
    pub bump: u8,
}

impl TokenVault {
    pub const INIT_SPACE: usize = 32 + 8 + 1 + 1; // mint + reserved_amount (layout-only) + disabled + bump
}
