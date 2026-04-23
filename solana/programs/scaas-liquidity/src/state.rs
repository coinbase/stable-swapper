use anchor_lang::prelude::*;
use crate::constants::{MAX_SUPPORTED_TOKENS, MAX_WHITELISTED_ADDRESSES};

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
#[allow(non_snake_case)]
pub struct TokenVault {
    pub mint: Pubkey,
    /// Deprecated: liquidity reservation was removed. This field is retained to
    /// preserve the on-chain account layout (Borsh is positional) for vaults
    /// created before removal. New vaults initialize it to 0. The swap path
    /// still subtracts it defensively so any legacy non-zero value on an
    /// already-deployed vault continues to behave as it did prior to removal.
    pub _DEPRECATED_reserved_amount: u64,
    pub disabled: bool, // If true, this token cannot be used in swaps
    pub bump: u8,
}

impl TokenVault {
    pub const INIT_SPACE: usize = 32 + 8 + 1 + 1; // mint + _DEPRECATED_reserved_amount (layout-only) + disabled + bump
}

/// Address whitelist for controlling swap access.
///
/// WHITELIST SEMANTICS: This whitelist validates TRANSACTION SIGNERS, not token ownership.
///
/// When enabled, only addresses in this list can sign swap transactions. However:
/// - Whitelisted signers can swap tokens they don't own (via delegation)
/// - Outputs can be routed to any address (not restricted to the signer)
///
/// Managed exclusively by pool.pause_authority via add_to_whitelist, remove_from_whitelist,
/// and toggle_whitelist instructions.
#[account]
pub struct AddressWhitelist {
    pub addresses: Vec<Pubkey>,
    pub enabled: bool,
    pub bump: u8,
}

impl AddressWhitelist {
    pub const INIT_SPACE: usize = (4 + 32 * MAX_WHITELISTED_ADDRESSES) + 1 + 1; // addresses + enabled + bump

    pub fn is_whitelisted(&self, address: &Pubkey) -> bool {
        self.addresses.contains(address)
    }
}
