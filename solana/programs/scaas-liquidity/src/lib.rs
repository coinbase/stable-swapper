use anchor_lang::prelude::*;
use anchor_spl::associated_token::AssociatedToken;
use anchor_spl::token::{self, Mint, Token, TokenAccount, Transfer};

mod constants;
mod errors;
mod state;
mod utils;

use constants::*;
use errors::*;
use state::*;
use utils::*;

declare_id!("9vDwZVJXw5nxymWmUcgmNpemDH5EBcJwLNhtsznrgJDH");

// NOTE: The previously deployed whitelist PDA (seeded b"address_whitelist") is orphaned
// on devnet/mainnet after whitelist removal. Its rent is intentionally forfeited; adding a
// close_whitelist instruction is not worth the complexity for the small amount involved.

#[program]
pub mod scaas_liquidity {
    use super::*;

    pub fn initialize(ctx: Context<Initialize>, fee_rate: u64) -> Result<()> {
        require!(fee_rate <= MAX_FEE_RATE, LiquidityError::InvalidFeeRate);
        // Refuse to stand up a pool whose withdraws would be unconditionally blocked by
        // `withdraw_liquidity`'s zero-key guard. Mirrors `update_withdraw_recipient`.
        require!(
            ctx.accounts.withdraw_recipient.key() != Pubkey::default(),
            LiquidityError::WithdrawRecipientNotSet
        );

        let pool = &mut ctx.accounts.pool;
        pool.pause_authority = ctx.accounts.pause_authority.key();
        pool.unpause_authority = ctx.accounts.unpause_authority.key();
        pool.treasury_authority = ctx.accounts.treasury_authority.key();
        pool.configure_authority = ctx.accounts.configure_authority.key();
        pool.fee_recipient = ctx.accounts.fee_recipient.key();
        pool.withdraw_recipient = ctx.accounts.withdraw_recipient.key();
        pool.supported_tokens = Vec::new();
        pool.fee_rate = fee_rate;
        pool.swaps_paused = false;
        pool.liquidity_paused = false;
        pool.bump = ctx.bumps.pool;

        msg!("Liquidity pool initialized with fee rate: {}", fee_rate);
        Ok(())
    }

    /// One-shot migration from the legacy `(operations_authority, pause_authority)` layout
    /// to the new role-based layout. Co-signed by both legacy authorities so neither key alone
    /// can unilaterally redistribute roles.
    ///
    /// The pool grows by 96 bytes (3 extra `Pubkey`s). The legacy account is opened as
    /// `UncheckedAccount` because the on-chain bytes don't deserialize into the new
    /// `LiquidityPool` struct; we parse the legacy fields manually, realloc, then serialize
    /// the new layout. Re-runs are rejected by checking the on-chain data length.
    pub fn migrate_authorities(
        ctx: Context<MigrateAuthorities>,
        new_pause_authority: Pubkey,
        new_unpause_authority: Pubkey,
        new_treasury_authority: Pubkey,
        new_configure_authority: Pubkey,
        new_withdraw_recipient: Pubkey,
    ) -> Result<()> {
        do_migrate_authorities(
            &ctx.accounts.pool.to_account_info(),
            &ctx.accounts.legacy_operations_authority.to_account_info(),
            &ctx.accounts.legacy_pause_authority.to_account_info(),
            &ctx.accounts.system_program.to_account_info(),
            new_pause_authority,
            new_unpause_authority,
            new_treasury_authority,
            new_configure_authority,
            new_withdraw_recipient,
        )
    }

    /// Test-only entrypoint: creates a synthetic legacy-shaped pool at a parametric PDA
    /// `[b"liquidity_pool_legacy_test", payer.key()]`, populates the legacy fields from the
    /// instruction args, and returns. Compiled only when the `test-helpers` feature is on
    /// so production builds never carry this surface.
    #[cfg(feature = "test-helpers")]
    pub fn init_legacy_for_test(
        ctx: Context<InitLegacyForTest>,
        legacy_ops: Pubkey,
        legacy_pause: Pubkey,
        legacy_fee_recipient: Pubkey,
        supported_tokens: Vec<Pubkey>,
        fee_rate: u64,
        swaps_paused: bool,
        liquidity_paused: bool,
    ) -> Result<()> {
        require!(
            supported_tokens.len() <= MAX_SUPPORTED_TOKENS,
            LiquidityError::LegacyVecLengthInvalid
        );

        let pool_ai = ctx.accounts.pool.to_account_info();
        let bump = ctx.bumps.pool;
        let mut data = pool_ai.try_borrow_mut_data()?;

        data[..8].copy_from_slice(LiquidityPool::DISCRIMINATOR);
        data[8..40].copy_from_slice(legacy_ops.as_ref());
        data[40..72].copy_from_slice(legacy_pause.as_ref());
        data[72..104].copy_from_slice(legacy_fee_recipient.as_ref());

        let len = supported_tokens.len() as u32;
        data[104..108].copy_from_slice(&len.to_le_bytes());
        for (i, mint) in supported_tokens.iter().enumerate() {
            let off = 108 + i * 32;
            data[off..off + 32].copy_from_slice(mint.as_ref());
        }

        let trailing = 108 + MAX_SUPPORTED_TOKENS * 32;
        data[trailing..trailing + 8].copy_from_slice(&fee_rate.to_le_bytes());
        data[trailing + 8] = swaps_paused as u8;
        data[trailing + 9] = liquidity_paused as u8;
        data[trailing + 10] = bump;

        Ok(())
    }

    /// Test-only entrypoint: same migration logic as `migrate_authorities`, but operates on the
    /// parametric test pool at `[b"liquidity_pool_legacy_test", payer.key()]`. Compiled only
    /// when the `test-helpers` feature is on.
    #[cfg(feature = "test-helpers")]
    pub fn migrate_authorities_for_test(
        ctx: Context<MigrateAuthoritiesForTest>,
        new_pause_authority: Pubkey,
        new_unpause_authority: Pubkey,
        new_treasury_authority: Pubkey,
        new_configure_authority: Pubkey,
        new_withdraw_recipient: Pubkey,
    ) -> Result<()> {
        do_migrate_authorities(
            &ctx.accounts.pool.to_account_info(),
            &ctx.accounts.legacy_operations_authority.to_account_info(),
            &ctx.accounts.legacy_pause_authority.to_account_info(),
            &ctx.accounts.system_program.to_account_info(),
            new_pause_authority,
            new_unpause_authority,
            new_treasury_authority,
            new_configure_authority,
            new_withdraw_recipient,
        )
    }

    pub fn add_supported_token(ctx: Context<AddSupportedToken>) -> Result<()> {
        let pool = &mut ctx.accounts.pool;
        let mint = ctx.accounts.mint.key();
        let decimals = ctx.accounts.mint.decimals;

        // Validate decimal range (6-9 decimals only)
        require!(
            decimals >= MIN_TOKEN_DECIMALS && decimals <= MAX_TOKEN_DECIMALS,
            LiquidityError::InvalidTokenDecimals
        );

        require!(
            !pool.supported_tokens.contains(&mint),
            LiquidityError::TokenAlreadySupported
        );
        require!(
            pool.supported_tokens.len() < MAX_SUPPORTED_TOKENS,
            LiquidityError::MaxTokensReached
        );

        pool.supported_tokens.push(mint);

        let vault = &mut ctx.accounts.vault;
        vault.mint = mint;
        // reserved_amount is layout-only and stays zero because Anchor initializes account data with zeroes.
        vault.disabled = false;
        vault.bump = ctx.bumps.vault;

        msg!("Added supported token: {}", mint);
        Ok(())
    }

    /// Removes a token from the supported tokens list and closes associated accounts.
    /// Requirements:
    /// - Token must be disabled first (safety check)
    /// - Vault token account must have zero balance
    /// - Token must exist in supported_tokens list
    ///
    /// This instruction will:
    /// 1. Verify vault is empty
    /// 2. Close vault_token_account and reclaim rent to configure_authority
    /// 3. Close vault account and reclaim rent to configure_authority
    /// 4. Remove token from supported_tokens vector
    ///
    /// Note: Anyone can send tokens directly to vault_token_account via SPL transfers.
    /// To prevent griefing, treasury_authority can always withdraw() any balance first.
    pub fn remove_supported_token(ctx: Context<RemoveSupportedToken>) -> Result<()> {
        let pool = &mut ctx.accounts.pool;
        let vault = &ctx.accounts.vault;
        let mint = ctx.accounts.mint.key();

        // Safety check: token must be disabled first
        require!(vault.disabled, LiquidityError::TokenMustBeDisabled);

        // Safety check: vault must be empty
        require!(
            ctx.accounts.vault_token_account.amount == 0,
            LiquidityError::VaultNotEmpty
        );

        // Find and remove token from supported_tokens
        let position = pool
            .supported_tokens
            .iter()
            .position(|&token| token == mint)
            .ok_or(LiquidityError::TokenNotFound)?;

        // Close vault_token_account and reclaim rent
        anchor_spl::token::close_account(CpiContext::new_with_signer(
            ctx.accounts.token_program.to_account_info(),
            anchor_spl::token::CloseAccount {
                account: ctx.accounts.vault_token_account.to_account_info(),
                destination: ctx.accounts.configure_authority.to_account_info(),
                authority: pool.to_account_info(),
            },
            &[&[LIQUIDITY_POOL_SEED, &[pool.bump]]],
        ))?;

        pool.supported_tokens.swap_remove(position);

        msg!("Removed supported token: {} and reclaimed rent", mint);
        Ok(())
    }

    pub fn swap(ctx: Context<Swap>, amount_in: u64, min_amount_out: u64) -> Result<()> {
        let pool = &ctx.accounts.pool;
        require!(!pool.swaps_paused, LiquidityError::SwapsPaused);
        require!(amount_in > 0, LiquidityError::InvalidAmount);

        // Check that neither token is disabled
        require!(
            !ctx.accounts.in_vault.disabled,
            LiquidityError::TokenDisabled
        );
        require!(
            !ctx.accounts.out_vault.disabled,
            LiquidityError::TokenDisabled
        );

        let from_mint = ctx.accounts.from_mint.key();
        let to_mint = ctx.accounts.to_mint.key();

        require!(
            pool.supported_tokens.contains(&from_mint),
            LiquidityError::TokenNotSupported
        );
        require!(
            pool.supported_tokens.contains(&to_mint),
            LiquidityError::TokenNotSupported
        );
        require!(from_mint != to_mint, LiquidityError::SameToken);

        // Read decimals from both mints
        let from_decimals = ctx.accounts.from_mint.decimals;
        let to_decimals = ctx.accounts.to_mint.decimals;

        // Fee Model: Fee is charged on INPUT token (from_mint)
        // Example: User swaps 100 USDC → SOL with 1% fee
        //   - User provides: 100 USDC total
        //   - from_vault receives: 99 USDC (liquidity)
        //   - fee_recipient receives: 1 USDC (protocol fee)
        //   - to_vault sends: 99 SOL to user (1:1 swap of net amount, normalized for decimals)

        // Calculate fee (in basis points, e.g., 100 = 1%)
        // Round up to ensure protocol always collects full fee amount
        let fee_amount = (amount_in as u128)
            .checked_mul(pool.fee_rate as u128)
            .ok_or(LiquidityError::FeeCalculationOverflow)?
            .checked_add(FEE_DENOMINATOR as u128 - 1)
            .ok_or(LiquidityError::FeeCalculationOverflow)?
            .checked_div(FEE_DENOMINATOR as u128)
            .ok_or(LiquidityError::FeeCalculationOverflow)? as u64;

        // Net amount after fee deduction (in from_token decimals)
        let amount_after_fee = amount_in
            .checked_sub(fee_amount)
            .ok_or(LiquidityError::FeeCalculationOverflow)?;

        // Normalize the amount to destination token decimals for output.
        //
        // IMPORTANT: When scaling down (e.g., 9 decimals → 6 decimals), integer division
        // rounds down, creating "dust" that cannot be represented in the lower-decimal token.
        // This dust is neither paid to the user nor to the fee recipient—it effectively
        // remains in the pool as a tiny implicit spread due to decimal precision mismatch.
        //
        // Example: Swapping 100.000000123 tokens (9 decimals) → 100.000000 tokens (6 decimals)
        // The remaining 0.000000123 precision is truncated (123 units in 9-decimal terms).
        // This is expected protocol-favorable rounding behavior.
        let amount_out = normalize_decimals(amount_after_fee, from_decimals, to_decimals)?;

        // Prevent zero-output swaps (e.g., when fees consume entire input amount)
        require!(amount_out > 0, LiquidityError::InvalidAmount);

        // Slippage protection: ensure normalized output meets user's minimum acceptable amount
        require!(
            amount_out >= min_amount_out,
            LiquidityError::SlippageExceeded
        );

        // Check available liquidity in the destination vault.
        require!(
            ctx.accounts.out_vault_token_account.amount >= amount_out,
            LiquidityError::InsufficientLiquidity
        );

        // Step 1: Transfer net amount (after fee) from user to source vault
        // This becomes the pool's liquidity for the input token
        let transfer_to_vault_ctx = CpiContext::new(
            ctx.accounts.token_program.to_account_info(),
            Transfer {
                from: ctx.accounts.user_from_token_account.to_account_info(),
                to: ctx.accounts.in_vault_token_account.to_account_info(),
                authority: ctx.accounts.user.to_account_info(),
            },
        );
        token::transfer(transfer_to_vault_ctx, amount_after_fee)?;

        // Step 2: Transfer fee portion (in input token) from user to fee recipient
        // Only execute if fee is non-zero to save gas
        if fee_amount > 0 {
            let transfer_fee_ctx = CpiContext::new(
                ctx.accounts.token_program.to_account_info(),
                Transfer {
                    from: ctx.accounts.user_from_token_account.to_account_info(),
                    to: ctx.accounts.fee_recipient_token_account.to_account_info(),
                    authority: ctx.accounts.user.to_account_info(),
                },
            );
            token::transfer(transfer_fee_ctx, fee_amount)?;
        }

        // Step 3: Transfer normalized amount from destination vault to user
        // amount_out is already normalized to destination token decimals
        let pool_seeds = &[LIQUIDITY_POOL_SEED, &[pool.bump]];
        let signer_seeds = &[&pool_seeds[..]];

        let transfer_out_ctx = CpiContext::new_with_signer(
            ctx.accounts.token_program.to_account_info(),
            Transfer {
                from: ctx.accounts.out_vault_token_account.to_account_info(),
                to: ctx.accounts.to_token_account.to_account_info(),
                authority: ctx.accounts.pool.to_account_info(),
            },
            signer_seeds,
        );
        token::transfer(transfer_out_ctx, amount_out)?;

        msg!(
            "Swapped {} tokens (from_decimals: {}, to_decimals: {}, amount_out: {}, fee: {})",
            amount_after_fee,
            from_decimals,
            to_decimals,
            amount_out,
            fee_amount
        );
        Ok(())
    }

    pub fn withdraw_liquidity(ctx: Context<WithdrawLiquidity>, amount: u64) -> Result<()> {
        let pool = &ctx.accounts.pool;
        require!(!pool.liquidity_paused, LiquidityError::LiquidityPaused);
        require!(amount > 0, LiquidityError::InvalidAmount);

        // Defensive: refuse to release funds before configure_authority has set a recipient.
        require!(
            pool.withdraw_recipient != Pubkey::default(),
            LiquidityError::WithdrawRecipientNotSet
        );

        // Ensure the treasury authority does not overdraw the vault balance.
        require!(
            amount <= ctx.accounts.vault_token_account.amount,
            LiquidityError::InsufficientLiquidity
        );

        let pool_seeds = &[LIQUIDITY_POOL_SEED, &[pool.bump]];
        let signer_seeds = &[&pool_seeds[..]];

        let transfer_ctx = CpiContext::new_with_signer(
            ctx.accounts.token_program.to_account_info(),
            Transfer {
                from: ctx.accounts.vault_token_account.to_account_info(),
                to: ctx.accounts.recipient_token_account.to_account_info(),
                authority: ctx.accounts.pool.to_account_info(),
            },
            signer_seeds,
        );

        token::transfer(transfer_ctx, amount)?;

        msg!("Withdrew {} tokens from vault", amount);
        Ok(())
    }

    pub fn update_fee_config(
        ctx: Context<UpdateFeeConfig>,
        fee_rate: Option<u64>,
        fee_recipient: Option<Pubkey>,
    ) -> Result<()> {
        let pool = &mut ctx.accounts.pool;

        if let Some(new_fee_rate) = fee_rate {
            require!(new_fee_rate <= MAX_FEE_RATE, LiquidityError::InvalidFeeRate);
            pool.fee_rate = new_fee_rate;
            msg!("Updated fee rate to: {}", new_fee_rate);
        }

        if let Some(new_fee_recipient) = fee_recipient {
            // Note: Changing the fee recipient only affects future swaps.
            // Fees already collected in the old recipient's token accounts
            // remain owned by the previous recipient.
            pool.fee_recipient = new_fee_recipient;
            msg!("Updated fee recipient to: {}", new_fee_recipient);
        }

        Ok(())
    }

    pub fn update_withdraw_recipient(
        ctx: Context<UpdateWithdrawRecipient>,
        new_withdraw_recipient: Pubkey,
    ) -> Result<()> {
        require!(
            new_withdraw_recipient != Pubkey::default(),
            LiquidityError::WithdrawRecipientNotSet
        );
        let pool = &mut ctx.accounts.pool;
        pool.withdraw_recipient = new_withdraw_recipient;
        msg!("Updated withdraw recipient to: {}", new_withdraw_recipient);
        Ok(())
    }

    pub fn pause_swaps(ctx: Context<PauseAction>) -> Result<()> {
        ctx.accounts.pool.swaps_paused = true;
        msg!("Swaps paused");
        Ok(())
    }

    pub fn unpause_swaps(ctx: Context<UnpauseAction>) -> Result<()> {
        ctx.accounts.pool.swaps_paused = false;
        msg!("Swaps unpaused");
        Ok(())
    }

    pub fn pause_withdraws(ctx: Context<PauseAction>) -> Result<()> {
        ctx.accounts.pool.liquidity_paused = true;
        msg!("Withdraws paused");
        Ok(())
    }

    pub fn unpause_withdraws(ctx: Context<UnpauseAction>) -> Result<()> {
        ctx.accounts.pool.liquidity_paused = false;
        msg!("Withdraws unpaused");
        Ok(())
    }

    pub fn pause_token(ctx: Context<PauseToken>) -> Result<()> {
        ctx.accounts.vault.disabled = true;
        msg!("Token {} paused", ctx.accounts.mint.key());
        Ok(())
    }

    pub fn unpause_token(ctx: Context<UnpauseToken>) -> Result<()> {
        ctx.accounts.vault.disabled = false;
        msg!("Token {} unpaused", ctx.accounts.mint.key());
        Ok(())
    }

    pub fn update_pause_authority(
        ctx: Context<UpdatePauseAuthority>,
        new_pause_authority: Pubkey,
    ) -> Result<()> {
        let pool = &mut ctx.accounts.pool;
        pool.pause_authority = new_pause_authority;
        msg!("Updated pause_authority to: {}", new_pause_authority);
        Ok(())
    }

    pub fn update_unpause_authority(
        ctx: Context<UpdateUnpauseAuthority>,
        new_unpause_authority: Pubkey,
    ) -> Result<()> {
        let pool = &mut ctx.accounts.pool;
        pool.unpause_authority = new_unpause_authority;
        msg!("Updated unpause_authority to: {}", new_unpause_authority);
        Ok(())
    }

    pub fn update_treasury_authority(
        ctx: Context<UpdateTreasuryAuthority>,
        new_treasury_authority: Pubkey,
    ) -> Result<()> {
        let pool = &mut ctx.accounts.pool;
        pool.treasury_authority = new_treasury_authority;
        msg!("Updated treasury_authority to: {}", new_treasury_authority);
        Ok(())
    }

    pub fn update_configure_authority(
        ctx: Context<UpdateConfigureAuthority>,
        new_configure_authority: Pubkey,
    ) -> Result<()> {
        let pool = &mut ctx.accounts.pool;
        pool.configure_authority = new_configure_authority;
        msg!("Updated configure_authority to: {}", new_configure_authority);
        Ok(())
    }
}

/// Shared body for `migrate_authorities` and (when the `test-helpers` feature is on)
/// `migrate_authorities_for_test`. Performs the legacy parse, signer match, realloc, rent
/// top-up, and re-serialize. The Accounts struct on the calling instruction is responsible
/// for verifying the pool address (canonical PDA in production, parametric PDA in tests).
fn do_migrate_authorities<'info>(
    pool_ai: &AccountInfo<'info>,
    legacy_operations_authority_ai: &AccountInfo<'info>,
    legacy_pause_authority_ai: &AccountInfo<'info>,
    system_program_ai: &AccountInfo<'info>,
    new_pause_authority: Pubkey,
    new_unpause_authority: Pubkey,
    new_treasury_authority: Pubkey,
    new_configure_authority: Pubkey,
    new_withdraw_recipient: Pubkey,
) -> Result<()> {
    require!(
        new_withdraw_recipient != Pubkey::default(),
        LiquidityError::WithdrawRecipientNotSet
    );

    let legacy_total = 8 + LiquidityPool::LEGACY_INIT_SPACE;
    let new_total = 8 + LiquidityPool::INIT_SPACE;

    // Defense-in-depth: `UncheckedAccount` does not enforce ownership. Reject any account not
    // owned by this program before we start parsing its bytes.
    require_keys_eq!(
        *pool_ai.owner,
        crate::ID,
        LiquidityError::LegacyDiscriminatorMismatch
    );

    // Re-run guard: only legacy-sized accounts are migratable. After a successful migration
    // the account is `new_total` bytes, so a second invocation lands here.
    require!(
        pool_ai.data_len() == legacy_total,
        LiquidityError::AlreadyMigrated
    );

    // Snapshot legacy fields with a scoped borrow so we can drop it before realloc.
    let (
        legacy_ops,
        legacy_pause,
        legacy_fee_recipient,
        supported_tokens,
        fee_rate,
        swaps_paused,
        liquidity_paused,
        bump,
    ) = {
        let data = pool_ai.try_borrow_data()?;
        require!(
            &data[..8] == LiquidityPool::DISCRIMINATOR,
            LiquidityError::LegacyDiscriminatorMismatch
        );

        // `Pubkey::try_from` on a 32-byte slice is infallible; the slice length is fixed
        // here by construction, so unwrap is safe.
        let legacy_ops = Pubkey::try_from(&data[8..40]).unwrap();
        let legacy_pause = Pubkey::try_from(&data[40..72]).unwrap();
        let legacy_fee_recipient = Pubkey::try_from(&data[72..104]).unwrap();

        // supported_tokens vec: 4-byte length + 32-byte pubkeys, max-allocated to MAX_SUPPORTED_TOKENS
        let len = u32::from_le_bytes(data[104..108].try_into().unwrap()) as usize;
        require!(
            len <= MAX_SUPPORTED_TOKENS,
            LiquidityError::LegacyVecLengthInvalid
        );
        let mut tokens = Vec::with_capacity(len);
        for i in 0..len {
            let off = 108 + i * 32;
            tokens.push(Pubkey::try_from(&data[off..off + 32]).unwrap());
        }

        // Trailing fixed-size fields sit after the max-sized vec slot.
        let trailing = 108 + MAX_SUPPORTED_TOKENS * 32;
        let fee_rate = u64::from_le_bytes(data[trailing..trailing + 8].try_into().unwrap());
        let swaps_paused = data[trailing + 8] != 0;
        let liquidity_paused = data[trailing + 9] != 0;
        let bump = data[trailing + 10];

        (
            legacy_ops,
            legacy_pause,
            legacy_fee_recipient,
            tokens,
            fee_rate,
            swaps_paused,
            liquidity_paused,
            bump,
        )
    };

    // Verify both legacy signers match the on-chain values.
    require_keys_eq!(
        *legacy_operations_authority_ai.key,
        legacy_ops,
        LiquidityError::LegacyDiscriminatorMismatch
    );
    require_keys_eq!(
        *legacy_pause_authority_ai.key,
        legacy_pause,
        LiquidityError::LegacyDiscriminatorMismatch
    );

    // Top up rent for the additional 96 bytes, then grow the account.
    let rent = Rent::get()?;
    let new_min_balance = rent.minimum_balance(new_total);
    let lamports_diff = new_min_balance.saturating_sub(pool_ai.lamports());
    if lamports_diff > 0 {
        anchor_lang::system_program::transfer(
            CpiContext::new(
                system_program_ai.clone(),
                anchor_lang::system_program::Transfer {
                    from: legacy_operations_authority_ai.clone(),
                    to: pool_ai.clone(),
                },
            ),
            lamports_diff,
        )?;
    }
    pool_ai.resize(new_total)?;

    // Serialize the new layout over the entire account.
    let new_pool = LiquidityPool {
        pause_authority: new_pause_authority,
        unpause_authority: new_unpause_authority,
        treasury_authority: new_treasury_authority,
        configure_authority: new_configure_authority,
        fee_recipient: legacy_fee_recipient,
        withdraw_recipient: new_withdraw_recipient,
        supported_tokens,
        fee_rate,
        swaps_paused,
        liquidity_paused,
        bump,
    };

    {
        let mut data = pool_ai.try_borrow_mut_data()?;
        // Discriminator is the same before and after migration; rewrite it explicitly
        // and then borsh-serialize the struct body.
        data[..8].copy_from_slice(LiquidityPool::DISCRIMINATOR);
        let mut writer: &mut [u8] = &mut data[8..];
        new_pool
            .serialize(&mut writer)
            .map_err(|_| error!(LiquidityError::MigrationSerializeFailed))?;
    }

    msg!("Migrated pool authorities to role-based layout");
    Ok(())
}

// Instruction contexts
#[derive(Accounts)]
pub struct Initialize<'info> {
    #[account(
        init,
        payer = payer,
        space = 8 + LiquidityPool::INIT_SPACE,
        seeds = [LIQUIDITY_POOL_SEED],
        bump
    )]
    pub pool: Account<'info, LiquidityPool>,

    #[account(mut)]
    pub payer: Signer<'info>,

    /// CHECK: Pause authority can be any account
    pub pause_authority: UncheckedAccount<'info>,

    /// CHECK: Unpause authority can be any account
    pub unpause_authority: UncheckedAccount<'info>,

    /// CHECK: Treasury authority can be any account
    pub treasury_authority: UncheckedAccount<'info>,

    /// CHECK: Configure authority can be any account
    pub configure_authority: UncheckedAccount<'info>,

    /// CHECK: Fee recipient can be any account
    pub fee_recipient: UncheckedAccount<'info>,

    /// CHECK: Withdraw recipient can be any account; only its key matters and only `configure_authority`
    /// can change it after initialization.
    pub withdraw_recipient: UncheckedAccount<'info>,

    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct MigrateAuthorities<'info> {
    /// Pool is opened as `UncheckedAccount` because the on-chain legacy bytes don't fit the
    /// new `LiquidityPool` struct. The instruction body verifies the discriminator + PDA
    /// derivation, parses the legacy fields, reallocates, and rewrites the new layout.
    /// CHECK: PDA + discriminator + legacy size verified inside `migrate_authorities`.
    #[account(
        mut,
        seeds = [LIQUIDITY_POOL_SEED],
        bump,
    )]
    pub pool: UncheckedAccount<'info>,

    /// Legacy operations authority. Verified inside the instruction against the legacy on-chain
    /// bytes; pays the additional rent for the 96-byte realloc.
    #[account(mut)]
    pub legacy_operations_authority: Signer<'info>,

    /// Legacy pause authority. Verified inside the instruction against the legacy on-chain bytes.
    pub legacy_pause_authority: Signer<'info>,

    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct AddSupportedToken<'info> {
    #[account(
        mut,
        has_one = configure_authority,
        seeds = [LIQUIDITY_POOL_SEED],
        bump = pool.bump
    )]
    pub pool: Account<'info, LiquidityPool>,

    #[account(
        init,
        payer = configure_authority,
        space = 8 + TokenVault::INIT_SPACE,
        seeds = [TOKEN_VAULT_SEED, pool.key().as_ref(), mint.key().as_ref()],
        bump
    )]
    pub vault: Account<'info, TokenVault>,

    #[account(
        init,
        payer = configure_authority,
        token::mint = mint,
        token::authority = pool,
        seeds = [VAULT_TOKEN_ACCOUNT_SEED, vault.key().as_ref()],
        bump
    )]
    pub vault_token_account: Account<'info, TokenAccount>,

    #[account(
        init_if_needed,
        payer = configure_authority,
        associated_token::mint = mint,
        associated_token::authority = fee_recipient
    )]
    pub fee_recipient_token_account: Account<'info, TokenAccount>,

    /// CHECK: Fee recipient address, validated via pool.fee_recipient
    #[account(address = pool.fee_recipient)]
    pub fee_recipient: UncheckedAccount<'info>,

    pub mint: Account<'info, Mint>,

    #[account(mut)]
    pub configure_authority: Signer<'info>,

    pub token_program: Program<'info, Token>,
    pub associated_token_program: Program<'info, AssociatedToken>,
    pub system_program: Program<'info, System>,
    pub rent: Sysvar<'info, Rent>,
}

#[derive(Accounts)]
pub struct RemoveSupportedToken<'info> {
    #[account(
        mut,
        has_one = configure_authority,
        seeds = [LIQUIDITY_POOL_SEED],
        bump = pool.bump
    )]
    pub pool: Account<'info, LiquidityPool>,

    #[account(
        mut,
        close = configure_authority,
        seeds = [TOKEN_VAULT_SEED, pool.key().as_ref(), mint.key().as_ref()],
        bump = vault.bump
    )]
    pub vault: Account<'info, TokenVault>,

    #[account(
        mut,
        seeds = [VAULT_TOKEN_ACCOUNT_SEED, vault.key().as_ref()],
        bump
    )]
    pub vault_token_account: Account<'info, TokenAccount>,

    pub mint: Account<'info, Mint>,

    #[account(mut)]
    pub configure_authority: Signer<'info>,

    pub token_program: Program<'info, Token>,
}

#[derive(Accounts)]
pub struct Swap<'info> {
    #[account(
        seeds = [LIQUIDITY_POOL_SEED],
        bump = pool.bump
    )]
    pub pool: Account<'info, LiquidityPool>,

    #[account(
        seeds = [TOKEN_VAULT_SEED, pool.key().as_ref(), from_mint.key().as_ref()],
        bump = in_vault.bump
    )]
    pub in_vault: Account<'info, TokenVault>,

    #[account(
        seeds = [TOKEN_VAULT_SEED, pool.key().as_ref(), to_mint.key().as_ref()],
        bump = out_vault.bump
    )]
    pub out_vault: Account<'info, TokenVault>,

    #[account(
        mut,
        seeds = [VAULT_TOKEN_ACCOUNT_SEED, in_vault.key().as_ref()],
        bump
    )]
    pub in_vault_token_account: Account<'info, TokenAccount>,

    #[account(
        mut,
        seeds = [VAULT_TOKEN_ACCOUNT_SEED, out_vault.key().as_ref()],
        bump
    )]
    pub out_vault_token_account: Account<'info, TokenAccount>,

    /// User's input token account (where swap input comes from).
    ///
    /// IMPORTANT: This account is NOT constrained to be owned by `user`.
    /// The SPL Token transfer will succeed if either:
    /// - `user` owns this account, OR
    /// - `user` is a valid delegate with sufficient allowance
    ///
    /// This intentionally allows delegation patterns.
    #[account(
        mut,
        token::mint = from_mint,
    )]
    pub user_from_token_account: Account<'info, TokenAccount>,

    /// Output token account (where swap output is sent).
    ///
    /// IMPORTANT: This account is NOT constrained to be owned by `user`.
    /// Any valid token account for the output mint can receive swap output.
    ///
    /// Note: The recipient's token account must exist before the swap.
    /// Users can create it with: spl-token create-account <MINT>
    #[account(
        mut,
        token::mint = to_mint,
    )]
    pub to_token_account: Account<'info, TokenAccount>,

    #[account(
        init_if_needed,
        payer = user,
        associated_token::mint = from_mint,
        associated_token::authority = fee_recipient
    )]
    pub fee_recipient_token_account: Account<'info, TokenAccount>,

    /// CHECK: Fee recipient address, validated via pool.fee_recipient
    #[account(address = pool.fee_recipient)]
    pub fee_recipient: UncheckedAccount<'info>,

    pub from_mint: Account<'info, Mint>,
    pub to_mint: Account<'info, Mint>,

    #[account(mut)]
    pub user: Signer<'info>,

    pub token_program: Program<'info, Token>,
    pub associated_token_program: Program<'info, AssociatedToken>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct WithdrawLiquidity<'info> {
    #[account(
        has_one = treasury_authority,
        seeds = [LIQUIDITY_POOL_SEED],
        bump = pool.bump
    )]
    pub pool: Account<'info, LiquidityPool>,

    #[account(
        seeds = [TOKEN_VAULT_SEED, pool.key().as_ref(), mint.key().as_ref()],
        bump = vault.bump
    )]
    pub vault: Account<'info, TokenVault>,

    #[account(
        mut,
        seeds = [VAULT_TOKEN_ACCOUNT_SEED, vault.key().as_ref()],
        bump
    )]
    pub vault_token_account: Account<'info, TokenAccount>,

    /// Recipient token account is locked to the address whose owner equals
    /// `pool.withdraw_recipient`. This prevents the treasury (hot) key from
    /// redirecting funds to an attacker-controlled wallet on its own.
    #[account(
        mut,
        token::mint = mint,
        token::authority = pool.withdraw_recipient,
    )]
    pub recipient_token_account: Account<'info, TokenAccount>,

    pub mint: Account<'info, Mint>,

    pub treasury_authority: Signer<'info>,

    pub token_program: Program<'info, Token>,
}

#[derive(Accounts)]
pub struct UpdateFeeConfig<'info> {
    #[account(
        mut,
        has_one = configure_authority,
        seeds = [LIQUIDITY_POOL_SEED],
        bump = pool.bump
    )]
    pub pool: Account<'info, LiquidityPool>,

    pub configure_authority: Signer<'info>,
}

#[derive(Accounts)]
pub struct UpdateWithdrawRecipient<'info> {
    #[account(
        mut,
        has_one = configure_authority,
        seeds = [LIQUIDITY_POOL_SEED],
        bump = pool.bump
    )]
    pub pool: Account<'info, LiquidityPool>,

    pub configure_authority: Signer<'info>,
}

#[derive(Accounts)]
pub struct PauseAction<'info> {
    #[account(
        mut,
        has_one = pause_authority,
        seeds = [LIQUIDITY_POOL_SEED],
        bump = pool.bump
    )]
    pub pool: Account<'info, LiquidityPool>,

    pub pause_authority: Signer<'info>,
}

#[derive(Accounts)]
pub struct UnpauseAction<'info> {
    #[account(
        mut,
        has_one = unpause_authority,
        seeds = [LIQUIDITY_POOL_SEED],
        bump = pool.bump
    )]
    pub pool: Account<'info, LiquidityPool>,

    pub unpause_authority: Signer<'info>,
}

#[derive(Accounts)]
pub struct PauseToken<'info> {
    #[account(
        has_one = pause_authority,
        seeds = [LIQUIDITY_POOL_SEED],
        bump = pool.bump
    )]
    pub pool: Account<'info, LiquidityPool>,

    #[account(
        mut,
        seeds = [TOKEN_VAULT_SEED, pool.key().as_ref(), mint.key().as_ref()],
        bump = vault.bump
    )]
    pub vault: Account<'info, TokenVault>,

    pub mint: Account<'info, Mint>,

    pub pause_authority: Signer<'info>,
}

#[derive(Accounts)]
pub struct UnpauseToken<'info> {
    #[account(
        has_one = unpause_authority,
        seeds = [LIQUIDITY_POOL_SEED],
        bump = pool.bump
    )]
    pub pool: Account<'info, LiquidityPool>,

    #[account(
        mut,
        seeds = [TOKEN_VAULT_SEED, pool.key().as_ref(), mint.key().as_ref()],
        bump = vault.bump
    )]
    pub vault: Account<'info, TokenVault>,

    pub mint: Account<'info, Mint>,

    pub unpause_authority: Signer<'info>,
}

#[derive(Accounts)]
pub struct UpdatePauseAuthority<'info> {
    #[account(
        mut,
        has_one = pause_authority,
        seeds = [LIQUIDITY_POOL_SEED],
        bump = pool.bump
    )]
    pub pool: Account<'info, LiquidityPool>,

    pub pause_authority: Signer<'info>,
}

#[derive(Accounts)]
pub struct UpdateUnpauseAuthority<'info> {
    #[account(
        mut,
        has_one = unpause_authority,
        seeds = [LIQUIDITY_POOL_SEED],
        bump = pool.bump
    )]
    pub pool: Account<'info, LiquidityPool>,

    pub unpause_authority: Signer<'info>,
}

#[derive(Accounts)]
pub struct UpdateTreasuryAuthority<'info> {
    #[account(
        mut,
        has_one = treasury_authority,
        seeds = [LIQUIDITY_POOL_SEED],
        bump = pool.bump
    )]
    pub pool: Account<'info, LiquidityPool>,

    pub treasury_authority: Signer<'info>,
}

#[derive(Accounts)]
pub struct UpdateConfigureAuthority<'info> {
    #[account(
        mut,
        has_one = configure_authority,
        seeds = [LIQUIDITY_POOL_SEED],
        bump = pool.bump
    )]
    pub pool: Account<'info, LiquidityPool>,

    pub configure_authority: Signer<'info>,
}

/// Test-only accounts: creates a synthetic legacy pool at a parametric PDA so test fixtures
/// don't collide with the canonical pool used by the rest of the suite. Compiled only when
/// the `test-helpers` feature is on.
#[cfg(feature = "test-helpers")]
#[derive(Accounts)]
pub struct InitLegacyForTest<'info> {
    #[account(
        init,
        payer = payer,
        space = 8 + LiquidityPool::LEGACY_INIT_SPACE,
        seeds = [b"liquidity_pool_legacy_test", payer.key().as_ref()],
        bump
    )]
    /// CHECK: opened as raw bytes; we manually write the legacy layout in the body.
    pub pool: UncheckedAccount<'info>,

    #[account(mut)]
    pub payer: Signer<'info>,

    pub system_program: Program<'info, System>,
}

/// Test-only accounts mirror of `MigrateAuthorities` but rooted at the parametric test PDA.
/// Compiled only when the `test-helpers` feature is on.
#[cfg(feature = "test-helpers")]
#[derive(Accounts)]
pub struct MigrateAuthoritiesForTest<'info> {
    /// CHECK: PDA + discriminator + legacy size + co-signers verified inside the shared
    /// `do_migrate_authorities` helper.
    #[account(
        mut,
        seeds = [b"liquidity_pool_legacy_test", legacy_operations_authority.key().as_ref()],
        bump,
    )]
    pub pool: UncheckedAccount<'info>,

    #[account(mut)]
    pub legacy_operations_authority: Signer<'info>,

    pub legacy_pause_authority: Signer<'info>,

    pub system_program: Program<'info, System>,
}
