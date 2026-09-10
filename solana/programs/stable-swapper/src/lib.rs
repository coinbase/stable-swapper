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

declare_id!("pqgqKahpG1y2wsgxFhzaAnkV1cL9vk8MSg9qm4q646F");

#[program]
pub mod stable_swapper {
    use super::*;

    pub fn initialize(ctx: Context<Initialize>, fee_rate: u64) -> Result<()> {
        require!(fee_rate <= MAX_FEE_RATE, LiquidityError::InvalidFeeRate);
        // Reject the default pubkey for every stored key so the pool starts fully usable; the
        // require_*_set helpers explain why a zero key is rejected.
        require_recipient_set("withdraw_recipient", &ctx.accounts.withdraw_recipient.key())?;
        require_recipient_set("fee_recipient", &ctx.accounts.fee_recipient.key())?;
        require_authority_set("pause_authority", &ctx.accounts.pause_authority.key())?;
        require_authority_set("unpause_authority", &ctx.accounts.unpause_authority.key())?;
        require_authority_set("treasury_authority", &ctx.accounts.treasury_authority.key())?;
        require_authority_set(
            "configure_authority",
            &ctx.accounts.configure_authority.key(),
        )?;

        let pool = &mut ctx.accounts.pool;
        pool.pause_authority = ctx.accounts.pause_authority.key();
        pool.unpause_authority = ctx.accounts.unpause_authority.key();
        pool.treasury_authority = ctx.accounts.treasury_authority.key();
        pool.configure_authority = ctx.accounts.configure_authority.key();
        pool.fee_recipient = ctx.accounts.fee_recipient.key();
        // Seed the allowlist with the initial recipient so withdraws are possible from day one.
        // Further recipients are managed by `configure_authority` via add/remove.
        pool.withdraw_recipients = vec![ctx.accounts.withdraw_recipient.key()];
        pool.supported_tokens = Vec::new();
        pool.fee_rate = fee_rate;
        pool.swaps_paused = false;
        pool.liquidity_paused = false;
        pool.bump = ctx.bumps.pool;

        msg!("Liquidity pool initialized with fee rate: {}", fee_rate);
        Ok(())
    }

    /// One-shot migration from the legacy `(operations_authority, pause_authority)` layout
    /// to the new role-based layout. Gated on the program upgrade authority.
    ///
    /// The pool grows from the legacy layout to `LiquidityPool::INIT_SPACE` (extra role keys
    /// plus the withdraw-recipient allowlist slot). The legacy account is opened as
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
            &ctx.accounts.payer.to_account_info(),
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
        vault.disabled = true;
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
        require!(min_amount_out > 0, LiquidityError::InvalidAmount);

        // Whitelist enforcement is permanently deprecated. `whitelist` stays in this
        // instruction's account list (see the field below) purely so already-encoded
        // callers/indexers built against the pre-deprecation `swap` signature keep working;
        // nothing reads or writes it anymore.

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
        require!(!pool.liquidity_paused, LiquidityError::WithdrawalPaused);
        require!(amount > 0, LiquidityError::InvalidAmount);

        // The treasury (hot) key selects a destination by passing its token account; the program
        // enforces that the account's owner is on the cold-key-managed allowlist. This prevents
        // the treasury key from redirecting funds to an address it controls on its own. An empty
        // allowlist therefore blocks all withdraws.
        require!(
            pool.withdraw_recipients
                .contains(&ctx.accounts.recipient_token_account.owner),
            LiquidityError::WithdrawRecipientNotAllowed
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

    pub fn update_fee_rate(ctx: Context<UpdateFeeConfig>, fee_rate: u64) -> Result<()> {
        require!(fee_rate <= MAX_FEE_RATE, LiquidityError::InvalidFeeRate);
        ctx.accounts.pool.fee_rate = fee_rate;
        msg!("Updated fee rate to: {}", fee_rate);
        Ok(())
    }

    /// Changing the fee recipient only affects future swaps. Fees already collected in the old
    /// recipient's token accounts remain owned by the previous recipient.
    pub fn update_fee_recipient(
        ctx: Context<UpdateFeeConfig>,
        fee_recipient: Pubkey,
    ) -> Result<()> {
        require_recipient_set("fee_recipient", &fee_recipient)?;
        ctx.accounts.pool.fee_recipient = fee_recipient;
        msg!("Updated fee recipient to: {}", fee_recipient);
        Ok(())
    }

    /// Adds an owner to the withdraw-recipient allowlist. Only `configure_authority` (cold key).
    pub fn add_withdraw_recipient(
        ctx: Context<ConfigureWithdrawRecipients>,
        recipient: Pubkey,
    ) -> Result<()> {
        require_recipient_set("withdraw_recipient", &recipient)?;
        let pool = &mut ctx.accounts.pool;
        require!(
            !pool.withdraw_recipients.contains(&recipient),
            LiquidityError::WithdrawRecipientAlreadyAllowed
        );
        require!(
            pool.withdraw_recipients.len() < MAX_WITHDRAW_RECIPIENTS,
            LiquidityError::MaxWithdrawRecipientsReached
        );
        pool.withdraw_recipients.push(recipient);
        msg!("Added withdraw recipient: {}", recipient);
        Ok(())
    }

    /// Removes an owner from the withdraw-recipient allowlist. Only `configure_authority` (cold key).
    pub fn remove_withdraw_recipient(
        ctx: Context<ConfigureWithdrawRecipients>,
        recipient: Pubkey,
    ) -> Result<()> {
        let pool = &mut ctx.accounts.pool;
        let position = pool
            .withdraw_recipients
            .iter()
            .position(|&r| r == recipient)
            .ok_or(LiquidityError::WithdrawRecipientNotAllowed)?;
        pool.withdraw_recipients.swap_remove(position);
        msg!("Removed withdraw recipient: {}", recipient);
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
        require_authority_set("pause_authority", &new_pause_authority)?;
        let pool = &mut ctx.accounts.pool;
        pool.pause_authority = new_pause_authority;
        msg!("Updated pause_authority to: {}", new_pause_authority);
        Ok(())
    }

    pub fn update_unpause_authority(
        ctx: Context<UpdateUnpauseAuthority>,
        new_unpause_authority: Pubkey,
    ) -> Result<()> {
        require_authority_set("unpause_authority", &new_unpause_authority)?;
        let pool = &mut ctx.accounts.pool;
        pool.unpause_authority = new_unpause_authority;
        msg!("Updated unpause_authority to: {}", new_unpause_authority);
        Ok(())
    }

    pub fn update_treasury_authority(
        ctx: Context<UpdateTreasuryAuthority>,
        new_treasury_authority: Pubkey,
    ) -> Result<()> {
        require_authority_set("treasury_authority", &new_treasury_authority)?;
        let pool = &mut ctx.accounts.pool;
        pool.treasury_authority = new_treasury_authority;
        msg!("Updated treasury_authority to: {}", new_treasury_authority);
        Ok(())
    }

    pub fn update_configure_authority(
        ctx: Context<UpdateConfigureAuthority>,
        new_configure_authority: Pubkey,
    ) -> Result<()> {
        require_authority_set("configure_authority", &new_configure_authority)?;
        let pool = &mut ctx.accounts.pool;
        pool.configure_authority = new_configure_authority;
        msg!(
            "Updated configure_authority to: {}",
            new_configure_authority
        );
        Ok(())
    }
}

/// Rejects the default pubkey for a key stored on the pool, failing with `error_code`. `field`
/// names the offending key, since a bare comparison logs the same zero key on both sides.
fn require_key_set(field: &str, key: &Pubkey, error_code: LiquidityError) -> Result<()> {
    if *key == Pubkey::default() {
        msg!("{} must not be set to the default pubkey", field);
        return Err(error_code.into());
    }
    Ok(())
}

/// Rejects the default pubkey for a signing role. Roles can only be rotated by their current
/// holder, so a zero-key role is a one-way door: no signature exists for it.
fn require_authority_set(field: &str, key: &Pubkey) -> Result<()> {
    require_key_set(field, key, LiquidityError::AuthorityNotSet)
}

/// Rejects the default pubkey for a payout destination (fee or withdraw recipient). Unlike a
/// role, a recipient never signs; a zero key just routes funds to a token account nobody can
/// sign for.
fn require_recipient_set(field: &str, key: &Pubkey) -> Result<()> {
    require_key_set(field, key, LiquidityError::RecipientNotSet)
}

/// Shared body for `migrate_authorities`: legacy parse, realloc, rent top-up, re-serialize.
/// The Accounts struct on the calling instruction is responsible for verifying the pool address
/// (the canonical PDA) and that the caller is the program upgrade authority.
///
/// Rent: the pool grows by the two extra role keys plus the withdraw-recipient allowlist,
/// and `payer_ai` pays the difference through a
/// `system_program::transfer` CPI. It must therefore be a system-owned account holding enough
/// lamports (~0.0027 SOL at the current rent rate). When the pool PDA already holds
/// `Rent::minimum_balance` for the new size the top-up is skipped entirely and no lamports are
/// needed, which is the way to migrate when the upgrade authority is a program-owned account
/// (a multisig PDA, say) that cannot be debited by the system program.
fn do_migrate_authorities<'info>(
    pool_ai: &AccountInfo<'info>,
    payer_ai: &AccountInfo<'info>,
    system_program_ai: &AccountInfo<'info>,
    new_pause_authority: Pubkey,
    new_unpause_authority: Pubkey,
    new_treasury_authority: Pubkey,
    new_configure_authority: Pubkey,
    new_withdraw_recipient: Pubkey,
) -> Result<()> {
    require_recipient_set("withdraw_recipient", &new_withdraw_recipient)?;
    require_authority_set("pause_authority", &new_pause_authority)?;
    require_authority_set("unpause_authority", &new_unpause_authority)?;
    require_authority_set("treasury_authority", &new_treasury_authority)?;
    require_authority_set("configure_authority", &new_configure_authority)?;

    let legacy_total = 8 + LiquidityPool::LEGACY_INIT_SPACE;
    let new_total = 8 + LiquidityPool::INIT_SPACE;

    // Defense-in-depth: `UncheckedAccount` does not enforce ownership. Reject any account not
    // owned by this program before we start parsing its bytes.
    require_keys_eq!(
        *pool_ai.owner,
        crate::ID,
        ErrorCode::AccountOwnedByWrongProgram
    );

    // Re-run guard: after a successful migration the account is `new_total` bytes, so a second
    // invocation is reported as already migrated. Any other unexpected size is a different
    // failure and gets its own error.
    require!(
        pool_ai.data_len() != new_total,
        LiquidityError::AlreadyMigrated
    );
    require!(
        pool_ai.data_len() == legacy_total,
        LiquidityError::LegacySizeMismatch
    );

    // Snapshot legacy fields with a scoped borrow so we can drop it before realloc.
    let (legacy_fee_recipient, supported_tokens, fee_rate, swaps_paused, liquidity_paused, bump) = {
        let data = pool_ai.try_borrow_data()?;
        require!(
            &data[..8] == LiquidityPool::DISCRIMINATOR,
            LiquidityError::LegacyDiscriminatorMismatch
        );

        // Bytes 8..72 hold the legacy operations and pause authorities. Both are superseded by
        // the role keys passed to this instruction, so they are skipped rather than read.
        // `Pubkey::try_from` on a 32-byte slice is infallible; the slice length is fixed
        // here by construction, so unwrap is safe.
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

        // Borsh serializes a `Vec` packed (4-byte len + len * element_size), NOT padded to its
        // allocated capacity. The trailing fixed-size fields therefore sit immediately after the
        // `len` actual token entries, not after the max-sized slot.
        let trailing = 108 + len * 32;
        let fee_rate = u64::from_le_bytes(data[trailing..trailing + 8].try_into().unwrap());
        let swaps_paused = data[trailing + 8] != 0;
        let liquidity_paused = data[trailing + 9] != 0;
        let bump = data[trailing + 10];

        (
            legacy_fee_recipient,
            tokens,
            fee_rate,
            swaps_paused,
            liquidity_paused,
            bump,
        )
    };

    require_recipient_set("fee_recipient", &legacy_fee_recipient)?;

    // Top up rent for the additional bytes, then grow the account. This is a no-op when the
    // pool already holds the new minimum balance.
    let rent = Rent::get()?;
    let new_min_balance = rent.minimum_balance(new_total);
    let lamports_diff = new_min_balance.saturating_sub(pool_ai.lamports());
    if lamports_diff > 0 {
        anchor_lang::system_program::transfer(
            CpiContext::new(
                system_program_ai.clone(),
                anchor_lang::system_program::Transfer {
                    from: payer_ai.clone(),
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
        withdraw_recipients: vec![new_withdraw_recipient],
        supported_tokens,
        fee_rate,
        swaps_paused,
        liquidity_paused,
        bump,
    };

    {
        let mut data = pool_ai.try_borrow_mut_data()?;
        data.fill(0);
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

    /// This program's `ProgramData` account, which carries the BPF loader's upgrade authority.
    ///
    /// The pool is a PDA of a fixed seed and no instruction can close it, so the first successful
    /// `initialize` claims the only pool this deployment will ever have. Left permissionless that
    /// is a griefing vector whose only remedy is redeploying at a new program ID, so pool creation
    /// is tied to the key that deploys the program. `Account<ProgramData>` enforces the BPF
    /// upgradeable loader as owner and rejects the other loader states; the address constraint
    /// pins it to this program's record.
    ///
    /// Note this makes `initialize` unavailable once the program is made immutable
    /// (`upgrade_authority_address == None`), which is intended: initialize and deploy belong to
    /// the same operation.
    #[account(
        constraint = program_data.key() == program_data_address()
            @ LiquidityError::InvalidProgramData,
        constraint = program_data.upgrade_authority_address == Some(payer.key())
            @ LiquidityError::NotUpgradeAuthority,
    )]
    pub program_data: Account<'info, ProgramData>,

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

    /// CHECK: Withdraw recipient can be any account; only its key matters. It seeds the withdraw
    /// allowlist, which `configure_authority` manages via add/remove after initialization.
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

    /// Must be the program upgrade authority, as enforced against `program_data` below. Also
    /// pays the additional rent for the realloc unless the pool is already funded to the new
    /// minimum balance. See `do_migrate_authorities` for the rent details.
    #[account(mut)]
    pub payer: Signer<'info>,

    /// This program's `ProgramData` account. Same gate as `initialize`, for the same reason the
    /// upgrade authority is the right key here: it can rewrite the pool wholesale by deploying
    /// new code, so a migration it authorizes grants it nothing it did not already have. The
    /// legacy authorities recorded in the pool are not consulted, which keeps hot keys out of
    /// the operation.
    #[account(
        constraint = program_data.key() == program_data_address()
            @ LiquidityError::InvalidProgramData,
        constraint = program_data.upgrade_authority_address == Some(payer.key())
            @ LiquidityError::NotUpgradeAuthority,
    )]
    pub program_data: Account<'info, ProgramData>,

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

    /// Deprecated whitelist PDA. Kept only so the account list matches the
    /// pre-deprecation `swap` signature that existing callers/indexers already encode;
    /// its data is never read. On mainnet this resolves to the orphaned whitelist account
    /// left behind by the original removal; on fresh deployments it need not exist at all.
    /// CHECK: seeds-verified PDA address only; deliberately not deserialized.
    #[account(
        seeds = [ADDRESS_WHITELIST_SEED],
        bump
    )]
    pub whitelist: UncheckedAccount<'info>,

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

    /// Destination token account. Its owner must be on `pool.withdraw_recipients` (enforced in
    /// the instruction body). This prevents the treasury (hot) key from redirecting funds to an
    /// attacker-controlled wallet on its own; only the cold configure authority manages the list.
    #[account(
        mut,
        token::mint = mint,
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
pub struct ConfigureWithdrawRecipients<'info> {
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
