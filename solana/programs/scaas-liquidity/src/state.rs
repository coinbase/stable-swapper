use crate::constants::MAX_SUPPORTED_TOKENS;
use anchor_lang::prelude::*;

#[account]
pub struct LiquidityPool {
    /// Hot key allowed to pause swaps, withdraws, and individual tokens.
    pub pause_authority: Pubkey,
    /// Cold key allowed to unpause swaps, withdraws, and individual tokens.
    pub unpause_authority: Pubkey,
    /// Hot key allowed to withdraw liquidity (only to `withdraw_recipient`).
    pub treasury_authority: Pubkey,
    /// Cold key allowed to list/unlist tokens, update fee config, and rotate the withdraw recipient.
    pub configure_authority: Pubkey,
    /// Recipient of swap fees (token transfers go to its ATA per mint).
    pub fee_recipient: Pubkey,
    /// Owner of the only token-account address allowed to receive `withdraw_liquidity` outputs.
    /// Set/rotated by `configure_authority`.
    pub withdraw_recipient: Pubkey,
    pub supported_tokens: Vec<Pubkey>,
    pub fee_rate: u64, // in basis points
    pub swaps_paused: bool,
    /// Controls the withdraw_liquidity instruction only.
    /// Note: Deposits go directly to vault_token_account via SPL Token transfers and are not gated.
    pub liquidity_paused: bool,
    pub bump: u8,
}

impl LiquidityPool {
    // 6 Pubkeys + supported_tokens vec header + cap + fee_rate + 2 bools + bump
    pub const INIT_SPACE: usize =
        32 * 6 + (4 + 32 * MAX_SUPPORTED_TOKENS) + 8 + 1 + 1 + 1;

    /// Pre-migration on-chain layout: ops + pause + fee_recipient + supported_tokens + fee_rate + 2 bools + bump.
    /// Used by `migrate_authorities` to size the pre-realloc account before expanding to `INIT_SPACE`.
    pub const LEGACY_INIT_SPACE: usize =
        32 * 3 + (4 + 32 * MAX_SUPPORTED_TOKENS) + 8 + 1 + 1 + 1;
}

#[account]
pub struct TokenVault {
    pub mint: Pubkey,
    /// Deprecated: liquidity reservation was removed in STBLE-2811.
    #[deprecated(
        note = "Liquidity reservation was removed in STBLE-2811; field retained for layout compatibility and is always zero on new vaults."
    )]
    pub reserved_amount: u64,
    pub disabled: bool, // If true, this token cannot be used in swaps
    pub bump: u8,
}

impl TokenVault {
    pub const INIT_SPACE: usize = 32 + 8 + 1 + 1; // mint + reserved_amount (layout-only) + disabled + bump
}
