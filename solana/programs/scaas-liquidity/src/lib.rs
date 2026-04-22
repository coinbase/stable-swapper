use anchor_lang::prelude::*;
use anchor_spl::token::{self, Token, TokenAccount, Mint, Transfer};
use anchor_spl::associated_token::AssociatedToken;

mod constants;
mod errors;
mod state;
mod utils;

use constants::*;
use errors::*;
use state::*;
use utils::*;

declare_id!("9vDwZVJXw5nxymWmUcgmNpemDH5EBcJwLNhtsznrgJDH");

#[program]
pub mod scaas_liquidity {
    use super::*;

    pub fn initialize(
        ctx: Context<Initialize>,
        fee_rate: u64,
    ) -> Result<()> {
        require!(fee_rate <= MAX_FEE_RATE, LiquidityError::InvalidFeeRate);

        let pool = &mut ctx.accounts.pool;
        pool.operations_authority = ctx.accounts.operations_authority.key();
        pool.pause_authority = ctx.accounts.pause_authority.key();
        pool.fee_recipient = ctx.accounts.fee_recipient.key();
        pool.supported_tokens = Vec::new();
        pool.fee_rate = fee_rate;
        pool.swaps_paused = false;
        pool.liquidity_paused = false;
        pool.bump = ctx.bumps.pool;

        // Initialize whitelist (disabled by default)
        // Note: Whitelist is controlled by pool.pause_authority (validated in ManageWhitelist context)
        let whitelist = &mut ctx.accounts.whitelist;
        whitelist.addresses = Vec::new();
        whitelist.enabled = false;
        whitelist.bump = ctx.bumps.whitelist;

        msg!("Liquidity pool and whitelist initialized with fee rate: {}", fee_rate);
        Ok(())
    }

    pub fn add_supported_token(
        ctx: Context<AddSupportedToken>,
    ) -> Result<()> {
        let pool = &mut ctx.accounts.pool;
        let mint = ctx.accounts.mint.key();
        let decimals = ctx.accounts.mint.decimals;

        // Validate decimal range (6-9 decimals only)
        require!(
            decimals >= MIN_TOKEN_DECIMALS && decimals <= MAX_TOKEN_DECIMALS,
            LiquidityError::InvalidTokenDecimals
        );

        require!(!pool.supported_tokens.contains(&mint), LiquidityError::TokenAlreadySupported);
        require!(pool.supported_tokens.len() < MAX_SUPPORTED_TOKENS, LiquidityError::MaxTokensReached);

        pool.supported_tokens.push(mint);

        let vault = &mut ctx.accounts.vault;
        vault.mint = mint;
        vault.reserved_amount = 0;
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
    /// 2. Close vault_token_account and reclaim rent to operations_authority
    /// 3. Close vault account and reclaim rent to operations_authority
    /// 4. Remove token from supported_tokens vector
    ///
    /// Note: Anyone can send tokens directly to vault_token_account via SPL transfers.
    /// To prevent griefing, operations_authority can always withdraw() any balance first.
    pub fn remove_supported_token(
        ctx: Context<RemoveSupportedToken>,
    ) -> Result<()> {
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
        let position = pool.supported_tokens.iter().position(|&token| token == mint)
            .ok_or(LiquidityError::TokenNotFound)?;

        // Close vault_token_account and reclaim rent
        anchor_spl::token::close_account(
            CpiContext::new_with_signer(
                ctx.accounts.token_program.to_account_info(),
                anchor_spl::token::CloseAccount {
                    account: ctx.accounts.vault_token_account.to_account_info(),
                    destination: ctx.accounts.operations_authority.to_account_info(),
                    authority: pool.to_account_info(),
                },
                &[&[
                    LIQUIDITY_POOL_SEED,
                    &[pool.bump],
                ]],
            ),
        )?;

        pool.supported_tokens.swap_remove(position);

        msg!("Removed supported token: {} and reclaimed rent", mint);
        Ok(())
    }

    /// Deposits liquidity into a vault.
    ///
    /// Note: The liquidity_paused check only applies to deposit_liquidity and withdraw_liquidity instructions.
    /// Anyone can still transfer tokens directly to vault_token_account via SPL Token transfers,
    /// bypassing this check entirely. This is an inherent limitation of Solana's token program
    /// and cannot be prevented at the protocol level.
    pub fn deposit_liquidity(
        ctx: Context<DepositLiquidity>,
        amount: u64,
    ) -> Result<()> {
        let pool = &ctx.accounts.pool;
        require!(!pool.liquidity_paused, LiquidityError::LiquidityPaused);
        require!(amount > 0, LiquidityError::InvalidAmount);

        let transfer_ctx = CpiContext::new(
            ctx.accounts.token_program.to_account_info(),
            Transfer {
                from: ctx.accounts.operations_authority_token_account.to_account_info(),
                to: ctx.accounts.vault_token_account.to_account_info(),
                authority: ctx.accounts.operations_authority.to_account_info(),
            },
        );

        token::transfer(transfer_ctx, amount)?;

        msg!("Deposited {} tokens to vault", amount);
        Ok(())
    }

    pub fn swap(
        ctx: Context<Swap>,
        amount_in: u64,
        min_amount_out: u64,
    ) -> Result<()> {
        let pool = &ctx.accounts.pool;
        require!(!pool.swaps_paused, LiquidityError::SwapsPaused);
        require!(amount_in > 0, LiquidityError::InvalidAmount);

        // WHITELIST DESIGN: Signer-based, intentionally allows delegation/relaying
        //
        // The whitelist validates the TRANSACTION SIGNER (user), NOT token account ownership.
        // This intentionally permits Whitelisted users to act as delegates for non-whitelisted token accounts
        //
        // Example: If Alice is whitelisted and Bob delegates his tokens to Alice,
        // Alice can execute swaps using Bob's tokens. The output can go to any account.
        //
        // This design choice favors composability and legitimate delegation patterns over
        // strict ownership enforcement.
        if ctx.accounts.whitelist.enabled {
            require!(
                ctx.accounts.whitelist.is_whitelisted(&ctx.accounts.user.key()),
                LiquidityError::NotWhitelisted
            );
        }

        // Check that neither token is disabled
        require!(!ctx.accounts.in_vault.disabled, LiquidityError::TokenDisabled);
        require!(!ctx.accounts.out_vault.disabled, LiquidityError::TokenDisabled);

        let from_mint = ctx.accounts.from_mint.key();
        let to_mint = ctx.accounts.to_mint.key();

        require!(pool.supported_tokens.contains(&from_mint), LiquidityError::TokenNotSupported);
        require!(pool.supported_tokens.contains(&to_mint), LiquidityError::TokenNotSupported);
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

        // Check available liquidity (total - reserved) in destination token
        let out_vault = &ctx.accounts.out_vault;
        let available_liquidity = ctx.accounts.out_vault_token_account.amount
            .checked_sub(out_vault.reserved_amount)
            .ok_or(LiquidityError::InsufficientLiquidity)?;

        require!(
            available_liquidity >= amount_out,
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
        let pool_seeds = &[
            LIQUIDITY_POOL_SEED,
            &[pool.bump],
        ];
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

    pub fn withdraw_liquidity(
        ctx: Context<WithdrawLiquidity>,
        amount: u64,
    ) -> Result<()> {
        let pool = &ctx.accounts.pool;
        require!(!pool.liquidity_paused, LiquidityError::LiquidityPaused);
        require!(amount > 0, LiquidityError::InvalidAmount);

        // Operations authority can withdraw freely (reserved_amount only restricts user swaps)
        // Just ensure we don't overdraw the vault balance
        require!(
            amount <= ctx.accounts.vault_token_account.amount,
            LiquidityError::InsufficientLiquidity
        );

        let pool_seeds = &[
            LIQUIDITY_POOL_SEED,
            &[pool.bump],
        ];
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

    pub fn update_pause_config(
        ctx: Context<UpdatePauseConfig>,
        swaps_paused: Option<bool>,
        liquidity_paused: Option<bool>,
    ) -> Result<()> {
        let pool = &mut ctx.accounts.pool;

        if let Some(new_swaps_paused) = swaps_paused {
            pool.swaps_paused = new_swaps_paused;
            msg!("Updated swaps_paused to: {}", new_swaps_paused);
        }

        if let Some(new_liquidity_paused) = liquidity_paused {
            pool.liquidity_paused = new_liquidity_paused;
            msg!("Updated liquidity_paused to: {}", new_liquidity_paused);
        }

        Ok(())
    }

    pub fn update_operations_authority(
        ctx: Context<UpdateOperationsAuthority>,
        new_operations_authority: Pubkey,
    ) -> Result<()> {
        let pool = &mut ctx.accounts.pool;
        pool.operations_authority = new_operations_authority;
        msg!("Updated operations_authority to: {}", new_operations_authority);
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

    pub fn update_reserved_amount(
        ctx: Context<UpdateReservedAmount>,
        new_reserved_amount: u64,
    ) -> Result<()> {
        let vault = &mut ctx.accounts.vault;

        // Ensure reserved amount doesn't exceed actual balance
        require!(
            new_reserved_amount <= ctx.accounts.vault_token_account.amount,
            LiquidityError::InvalidReservedAmount
        );

        let old_reserved = vault.reserved_amount;
        vault.reserved_amount = new_reserved_amount;

        msg!(
            "Updated reserved amount from {} to {} for vault {}",
            old_reserved,
            new_reserved_amount,
            vault.mint
        );

        Ok(())
    }

    /// Disables or enables a token for swaps.
    /// Useful for emergency response or to deprecate tokens for operational reasons.
    pub fn update_token_status(
        ctx: Context<UpdateTokenStatus>,
        disabled: bool,
    ) -> Result<()> {
        let vault = &mut ctx.accounts.vault;
        vault.disabled = disabled;

        msg!("Updated token {} status to disabled: {}", ctx.accounts.mint.key(), disabled);
        Ok(())
    }

    /// Adds an address to the whitelist.
    pub fn add_to_whitelist(
        ctx: Context<ManageWhitelist>,
        address: Pubkey,
    ) -> Result<()> {
        let whitelist = &mut ctx.accounts.whitelist;

        require!(
            !whitelist.addresses.contains(&address),
            LiquidityError::AddressAlreadyWhitelisted
        );
        require!(
            whitelist.addresses.len() < MAX_WHITELISTED_ADDRESSES,
            LiquidityError::MaxWhitelistedAddressesReached
        );

        whitelist.addresses.push(address);

        msg!("Added address {} to whitelist", address);
        Ok(())
    }

    /// Removes an address from the whitelist.
    pub fn remove_from_whitelist(
        ctx: Context<ManageWhitelist>,
        address: Pubkey,
    ) -> Result<()> {
        let whitelist = &mut ctx.accounts.whitelist;

        let position = whitelist.addresses.iter().position(|&addr| addr == address)
            .ok_or(LiquidityError::AddressNotInWhitelist)?;

        whitelist.addresses.swap_remove(position);

        msg!("Removed address {} from whitelist", address);
        Ok(())
    }

    /// Enables or disables the whitelist.
    /// When disabled, all users can swap. When enabled, only whitelisted users can swap.
    pub fn toggle_whitelist(
        ctx: Context<ManageWhitelist>,
        enabled: bool,
    ) -> Result<()> {
        let whitelist = &mut ctx.accounts.whitelist;
        whitelist.enabled = enabled;

        msg!("Whitelist enabled status set to: {}", enabled);
        Ok(())
    }
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

    #[account(
        init,
        payer = payer,
        space = 8 + AddressWhitelist::INIT_SPACE,
        seeds = [ADDRESS_WHITELIST_SEED],
        bump
    )]
    pub whitelist: Account<'info, AddressWhitelist>,

    #[account(mut)]
    pub payer: Signer<'info>,

    /// CHECK: Operations authority can be any account
    pub operations_authority: UncheckedAccount<'info>,

    /// CHECK: Pause authority can be any account
    pub pause_authority: UncheckedAccount<'info>,

    /// CHECK: Fee recipient can be any account
    pub fee_recipient: UncheckedAccount<'info>,

    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct AddSupportedToken<'info> {
    #[account(
        mut,
        has_one = operations_authority,
        seeds = [LIQUIDITY_POOL_SEED],
        bump = pool.bump
    )]
    pub pool: Account<'info, LiquidityPool>,

    #[account(
        init,
        payer = operations_authority,
        space = 8 + TokenVault::INIT_SPACE,
        seeds = [TOKEN_VAULT_SEED, pool.key().as_ref(), mint.key().as_ref()],
        bump
    )]
    pub vault: Account<'info, TokenVault>,

    #[account(
        init,
        payer = operations_authority,
        token::mint = mint,
        token::authority = pool,
        seeds = [VAULT_TOKEN_ACCOUNT_SEED, vault.key().as_ref()],
        bump
    )]
    pub vault_token_account: Account<'info, TokenAccount>,

    #[account(
        init_if_needed,
        payer = operations_authority,
        associated_token::mint = mint,
        associated_token::authority = fee_recipient
    )]
    pub fee_recipient_token_account: Account<'info, TokenAccount>,

    /// CHECK: Fee recipient address, validated via pool.fee_recipient
    #[account(address = pool.fee_recipient)]
    pub fee_recipient: UncheckedAccount<'info>,

    pub mint: Account<'info, Mint>,

    #[account(mut)]
    pub operations_authority: Signer<'info>,

    pub token_program: Program<'info, Token>,
    pub associated_token_program: Program<'info, AssociatedToken>,
    pub system_program: Program<'info, System>,
    pub rent: Sysvar<'info, Rent>,
}

#[derive(Accounts)]
pub struct RemoveSupportedToken<'info> {
    #[account(
        mut,
        has_one = operations_authority,
        seeds = [LIQUIDITY_POOL_SEED],
        bump = pool.bump
    )]
    pub pool: Account<'info, LiquidityPool>,

    #[account(
        mut,
        close = operations_authority,
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
    pub operations_authority: Signer<'info>,

    pub token_program: Program<'info, Token>,
}

#[derive(Accounts)]
pub struct DepositLiquidity<'info> {
    #[account(
        has_one = operations_authority,
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

    #[account(
        mut,
        token::mint = mint,
    )]
    pub operations_authority_token_account: Account<'info, TokenAccount>,

    pub mint: Account<'info, Mint>,

    pub operations_authority: Signer<'info>,

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
    /// This intentionally allows delegation patterns (see whitelist design docs above).
    #[account(
        mut,
        token::mint = from_mint,
    )]
    pub user_from_token_account: Account<'info, TokenAccount>,

    /// Output token account (where swap output is sent).
    ///
    /// IMPORTANT: This account is NOT constrained to be owned by `user`.
    /// Any valid token account for the output mint can be used, enabling
    /// whitelisted relayers to route swaps to any recipient address.
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

    #[account(
        seeds = [ADDRESS_WHITELIST_SEED],
        bump = whitelist.bump
    )]
    pub whitelist: Account<'info, AddressWhitelist>,

    pub token_program: Program<'info, Token>,
    pub associated_token_program: Program<'info, AssociatedToken>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct WithdrawLiquidity<'info> {
    #[account(
        has_one = operations_authority,
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

    #[account(
        mut,
        token::mint = mint,
    )]
    pub recipient_token_account: Account<'info, TokenAccount>,

    pub mint: Account<'info, Mint>,

    pub operations_authority: Signer<'info>,

    pub token_program: Program<'info, Token>,
}

#[derive(Accounts)]
pub struct UpdateFeeConfig<'info> {
    #[account(
        mut,
        has_one = operations_authority,
        seeds = [LIQUIDITY_POOL_SEED],
        bump = pool.bump
    )]
    pub pool: Account<'info, LiquidityPool>,

    pub operations_authority: Signer<'info>,
}

#[derive(Accounts)]
pub struct UpdatePauseConfig<'info> {
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
pub struct UpdateOperationsAuthority<'info> {
    #[account(
        mut,
        has_one = operations_authority,
        seeds = [LIQUIDITY_POOL_SEED],
        bump = pool.bump
    )]
    pub pool: Account<'info, LiquidityPool>,

    pub operations_authority: Signer<'info>,
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
pub struct UpdateReservedAmount<'info> {
    #[account(
        has_one = operations_authority,
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

    #[account(
        seeds = [VAULT_TOKEN_ACCOUNT_SEED, vault.key().as_ref()],
        bump
    )]
    pub vault_token_account: Account<'info, TokenAccount>,

    pub mint: Account<'info, Mint>,

    pub operations_authority: Signer<'info>,
}

#[derive(Accounts)]
pub struct UpdateTokenStatus<'info> {
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
pub struct ManageWhitelist<'info> {
    #[account(
        has_one = pause_authority,
        seeds = [LIQUIDITY_POOL_SEED],
        bump = pool.bump
    )]
    pub pool: Account<'info, LiquidityPool>,

    #[account(
        mut,
        seeds = [ADDRESS_WHITELIST_SEED],
        bump = whitelist.bump
    )]
    pub whitelist: Account<'info, AddressWhitelist>,

    pub pause_authority: Signer<'info>,
}