/// Fee denominator for basis points calculation (100% = 10000 basis points)
pub const FEE_DENOMINATOR: u64 = 10000;

/// Maximum fee rate in basis points (10% = 1000 basis points)
pub const MAX_FEE_RATE: u64 = 1000;

/// Maximum number of supported tokens per pool
pub const MAX_SUPPORTED_TOKENS: usize = 50;

/// Maximum number of whitelisted addresses
pub const MAX_WHITELISTED_ADDRESSES: usize = 100;

/// Minimum allowed token decimals
pub const MIN_TOKEN_DECIMALS: u8 = 6;

/// Maximum allowed token decimals
pub const MAX_TOKEN_DECIMALS: u8 = 9;

// PDA Seeds
/// Seed for liquidity pool PDA
pub const LIQUIDITY_POOL_SEED: &[u8] = b"liquidity_pool";

/// Seed for token vault PDA
pub const TOKEN_VAULT_SEED: &[u8] = b"token_vault";

/// Seed for vault token account PDA
pub const VAULT_TOKEN_ACCOUNT_SEED: &[u8] = b"vault_token_account";

/// Seed for address whitelist PDA
pub const ADDRESS_WHITELIST_SEED: &[u8] = b"address_whitelist";
