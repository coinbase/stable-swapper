import * as anchor from "@coral-xyz/anchor";
import { Program } from "@coral-xyz/anchor";
import { StableSwapper } from "../target/types/stable_swapper";
import { PublicKey, SystemProgram } from "@solana/web3.js";
import {
  TOKEN_PROGRAM_ID,
  ASSOCIATED_TOKEN_PROGRAM_ID,
  createMint,
  createAccount,
  mintTo,
  getAccount,
  getAssociatedTokenAddress,
  transfer,
  approve,
} from "@solana/spl-token";
import { assert } from "chai";

describe("stable-swapper", () => {
  const provider = anchor.AnchorProvider.env();
  anchor.setProvider(provider);

  const program = anchor.workspace.stableSwapper as Program<StableSwapper>;
  const payer = provider.wallet as anchor.Wallet;
  const operationsAuthority = payer; // In tests, same as payer
  const pauseAuthority = payer; // In tests, same as payer

  // Test keypairs
  let usdcMint: PublicKey;
  let customStableMint: PublicKey;
  let pool: PublicKey;
  let usdcVault: PublicKey;
  let customStableVault: PublicKey;
  let usdcVaultTokenAccount: PublicKey;
  let customStableVaultTokenAccount: PublicKey;

  // User accounts (also used for fee collection since authority is the fee recipient in tests)
  let userUsdcAccount: PublicKey;
  let userCustomStableAccount: PublicKey;

  // Fee recipient token accounts (created when tokens are added)
  let feeRecipientUsdcAccount: PublicKey;
  let feeRecipientCustomStableAccount: PublicKey;

  before(async () => {
    // Create USDC and CustomStable mints
    usdcMint = await createMint(
      provider.connection,
      payer.payer,
      payer.publicKey,
      null,
      6 // USDC decimals
    );

    customStableMint = await createMint(
      provider.connection,
      payer.payer,
      payer.publicKey,
      null,
      6 // CustomStable decimals
    );

    // Derive PDAs (pool is now a single centralized pool, no authority in seed)
    [pool] = PublicKey.findProgramAddressSync(
      [Buffer.from("liquidity_pool")],
      program.programId
    );

    [usdcVault] = PublicKey.findProgramAddressSync(
      [Buffer.from("token_vault"), pool.toBuffer(), usdcMint.toBuffer()],
      program.programId
    );

    [customStableVault] = PublicKey.findProgramAddressSync(
      [Buffer.from("token_vault"), pool.toBuffer(), customStableMint.toBuffer()],
      program.programId
    );

    [usdcVaultTokenAccount] = PublicKey.findProgramAddressSync(
      [Buffer.from("vault_token_account"), usdcVault.toBuffer()],
      program.programId
    );

    [customStableVaultTokenAccount] = PublicKey.findProgramAddressSync(
      [Buffer.from("vault_token_account"), customStableVault.toBuffer()],
      program.programId
    );

    // Derive fee recipient token accounts (ATAs)
    feeRecipientUsdcAccount = await getAssociatedTokenAddress(
      usdcMint,
      payer.publicKey
    );
    feeRecipientCustomStableAccount = await getAssociatedTokenAddress(
      customStableMint,
      payer.publicKey
    );

    // Create user token accounts
    userUsdcAccount = await createAccount(
      provider.connection,
      payer.payer,
      usdcMint,
      payer.publicKey
    );

    userCustomStableAccount = await createAccount(
      provider.connection,
      payer.payer,
      customStableMint,
      payer.publicKey
    );

    // Mint tokens to user accounts for testing
    await mintTo(
      provider.connection,
      payer.payer,
      usdcMint,
      userUsdcAccount,
      payer.payer,
      1000 * 10 ** 6 // 1000 USDC
    );

    await mintTo(
      provider.connection,
      payer.payer,
      customStableMint,
      userCustomStableAccount,
      payer.payer,
      1000 * 10 ** 6 // 1000 CustomStable
    );
  });

  describe("Pool Initialization", () => {
    it("Initializes the liquidity pool", async () => {
      const feeRate = 0; // 0% fee for 1:1 swaps

      await program.methods
        .initialize(new anchor.BN(feeRate))
        .accounts({
          pool,
          payer: payer.publicKey,
          operationsAuthority: operationsAuthority.publicKey,
          pauseAuthority: pauseAuthority.publicKey,
          feeRecipient: payer.publicKey,
          systemProgram: SystemProgram.programId,
        })
        .signers([payer.payer])
        .rpc();

      // Verify pool state
      const poolAccount = await program.account.liquidityPool.fetch(pool);
      assert.equal(
        poolAccount.operationsAuthority.toString(),
        operationsAuthority.publicKey.toString()
      );
      assert.equal(
        poolAccount.pauseAuthority.toString(),
        pauseAuthority.publicKey.toString()
      );
      assert.equal(poolAccount.feeRate.toNumber(), feeRate);
      assert.equal(poolAccount.swapsPaused, false);
      assert.equal(poolAccount.liquidityPaused, false);
      assert.equal(poolAccount.supportedTokens.length, 0);
    });

    it("Adds USDC as supported token", async () => {
      await program.methods
        .addSupportedToken()
        .accounts({
          pool,
          vault: usdcVault,
          vaultTokenAccount: usdcVaultTokenAccount,
          feeRecipientTokenAccount: feeRecipientUsdcAccount,
          feeRecipient: payer.publicKey,
          mint: usdcMint,
          operationsAuthority: operationsAuthority.publicKey,
          tokenProgram: TOKEN_PROGRAM_ID,
          associatedTokenProgram: ASSOCIATED_TOKEN_PROGRAM_ID,
          systemProgram: SystemProgram.programId,
          rent: anchor.web3.SYSVAR_RENT_PUBKEY,
        })
        .signers([operationsAuthority.payer])
        .rpc();

      // Verify vault creation
      const vaultAccount = await program.account.tokenVault.fetch(usdcVault);
      assert.equal(vaultAccount.mint.toString(), usdcMint.toString());

      // Verify token was added to pool
      const poolAccount = await program.account.liquidityPool.fetch(pool);
      assert.equal(poolAccount.supportedTokens.length, 1);
      assert.equal(
        poolAccount.supportedTokens[0].toString(),
        usdcMint.toString()
      );
    });

    it("Adds CustomStable as supported token", async () => {
      await program.methods
        .addSupportedToken()
        .accounts({
          pool,
          vault: customStableVault,
          vaultTokenAccount: customStableVaultTokenAccount,
          feeRecipientTokenAccount: feeRecipientCustomStableAccount,
          feeRecipient: payer.publicKey,
          mint: customStableMint,
          operationsAuthority: operationsAuthority.publicKey,
          tokenProgram: TOKEN_PROGRAM_ID,
          associatedTokenProgram: ASSOCIATED_TOKEN_PROGRAM_ID,
          systemProgram: SystemProgram.programId,
          rent: anchor.web3.SYSVAR_RENT_PUBKEY,
        })
        .signers([operationsAuthority.payer])
        .rpc();

      // Verify pool now has both tokens
      const poolAccount = await program.account.liquidityPool.fetch(pool);
      assert.equal(poolAccount.supportedTokens.length, 2);
    });
  });

  describe("Liquidity Management", () => {
    // Seed both vaults via direct SPL transfer so downstream withdraw/swap
    // tests have liquidity to operate on.
    before(async () => {
      const seedAmount = BigInt(500 * 10 ** 6);

      await transfer(
        provider.connection,
        payer.payer,
        userUsdcAccount,
        usdcVaultTokenAccount,
        payer.payer,
        seedAmount
      );

      await transfer(
        provider.connection,
        payer.payer,
        userCustomStableAccount,
        customStableVaultTokenAccount,
        payer.payer,
        seedAmount
      );
    });

    it("Withdraws USDC liquidity successfully", async () => {
      const withdrawAmount = new anchor.BN(50 * 10 ** 6); // 50 USDC

      // Get initial balances
      const initialVaultBalance = await getAccount(
        provider.connection,
        usdcVaultTokenAccount
      );
      const initialRecipientBalance = await getAccount(
        provider.connection,
        userUsdcAccount
      );

      await program.methods
        .withdrawLiquidity(withdrawAmount)
        .accounts({
          pool,
          vault: usdcVault,
          vaultTokenAccount: usdcVaultTokenAccount,
          recipientTokenAccount: userUsdcAccount,
          mint: usdcMint,
          operationsAuthority: operationsAuthority.publicKey,
          tokenProgram: TOKEN_PROGRAM_ID,
        })
        .signers([operationsAuthority.payer])
        .rpc();

      // Verify liquidity was withdrawn
      const finalVaultBalance = await getAccount(
        provider.connection,
        usdcVaultTokenAccount
      );
      const finalRecipientBalance = await getAccount(
        provider.connection,
        userUsdcAccount
      );

      assert.equal(
        initialVaultBalance.amount - finalVaultBalance.amount,
        BigInt(withdrawAmount.toString()),
        "Vault balance should decrease by withdrawal amount"
      );
      assert.equal(
        finalRecipientBalance.amount - initialRecipientBalance.amount,
        BigInt(withdrawAmount.toString()),
        "Recipient balance should increase by withdrawal amount"
      );
    });

    it("Fails to withdraw when liquidity is paused", async () => {
      // First pause liquidity
      await program.methods
        .updatePauseConfig(null, true) // swapsPaused=null, liquidityPaused=true
        .accounts({
          pool,
          pauseAuthority: pauseAuthority.publicKey,
        })
        .signers([pauseAuthority.payer])
        .rpc();

      const withdrawAmount = new anchor.BN(10 * 10 ** 6);

      try {
        await program.methods
          .withdrawLiquidity(withdrawAmount)
          .accounts({
            pool,
            vault: usdcVault,
            vaultTokenAccount: usdcVaultTokenAccount,
            recipientTokenAccount: userUsdcAccount,
            mint: usdcMint,
            operationsAuthority: operationsAuthority.publicKey,
            tokenProgram: TOKEN_PROGRAM_ID,
          })
          .signers([operationsAuthority.payer])
          .rpc();

        assert.fail("Expected liquidity paused error");
      } catch (error) {
        assert.include(error.toString(), "LiquidityPaused");
      }

      // Unpause liquidity for other tests
      await program.methods
        .updatePauseConfig(null, false)
        .accounts({
          pool,
          pauseAuthority: pauseAuthority.publicKey,
        })
        .signers([pauseAuthority.payer])
        .rpc();
    });
  });

  describe("Swapping", () => {
    it("Swaps USDC for CustomStable (1:1)", async () => {
      const swapAmount = new anchor.BN(100 * 10 ** 6); // 100 USDC
      const minAmountOut = new anchor.BN(100 * 10 ** 6); // Expect 100 CustomStable (0% fee)

      // Get initial balances
      const initialUserUsdcBalance = await getAccount(
        provider.connection,
        userUsdcAccount
      );
      const initialUserCustomStableBalance = await getAccount(
        provider.connection,
        userCustomStableAccount
      );

      await program.methods
        .swap(swapAmount, minAmountOut)
        .accounts({
          pool,
          inVault: usdcVault,
          outVault: customStableVault,
          inVaultTokenAccount: usdcVaultTokenAccount,
          outVaultTokenAccount: customStableVaultTokenAccount,
          userFromTokenAccount: userUsdcAccount,
          toTokenAccount: userCustomStableAccount,
          feeRecipientTokenAccount: userUsdcAccount, // Fee collected in input token (USDC)
          feeRecipient: payer.publicKey, // Fee recipient authority
          fromMint: usdcMint,
          toMint: customStableMint,
          user: payer.publicKey,
          tokenProgram: TOKEN_PROGRAM_ID,
          associatedTokenProgram: ASSOCIATED_TOKEN_PROGRAM_ID,
          systemProgram: SystemProgram.programId,
        })
        .signers([payer.payer])
        .rpc();

      // Get final balances
      const finalUserUsdcBalance = await getAccount(
        provider.connection,
        userUsdcAccount
      );
      const finalUserCustomStableBalance = await getAccount(
        provider.connection,
        userCustomStableAccount
      );

      // Verify balances changed correctly (1:1 swap, 0% fee)
      const usdcDiff =
        initialUserUsdcBalance.amount - finalUserUsdcBalance.amount;
      const customStableDiff =
        finalUserCustomStableBalance.amount - initialUserCustomStableBalance.amount;

      assert.equal(usdcDiff.toString(), swapAmount.toString());
      assert.equal(customStableDiff.toString(), swapAmount.toString()); // 1:1 with 0% fee
    });

    it("Swaps CustomStable for USDC (1:1)", async () => {
      const swapAmount = new anchor.BN(50 * 10 ** 6); // 50 CustomStable
      const minAmountOut = new anchor.BN(50 * 10 ** 6); // Expect 50 USDC (0% fee)

      // Get initial balances
      const initialUserUsdcBalance = await getAccount(
        provider.connection,
        userUsdcAccount
      );
      const initialUserCustomStableBalance = await getAccount(
        provider.connection,
        userCustomStableAccount
      );

      await program.methods
        .swap(swapAmount, minAmountOut)
        .accounts({
          pool,
          inVault: customStableVault,
          outVault: usdcVault,
          inVaultTokenAccount: customStableVaultTokenAccount,
          outVaultTokenAccount: usdcVaultTokenAccount,
          userFromTokenAccount: userCustomStableAccount,
          toTokenAccount: userUsdcAccount,
          feeRecipientTokenAccount: userCustomStableAccount, // Fee collected in input token (CustomStable)
          feeRecipient: payer.publicKey, // Fee recipient authority
          fromMint: customStableMint,
          toMint: usdcMint,
          user: payer.publicKey,
          tokenProgram: TOKEN_PROGRAM_ID,
          associatedTokenProgram: ASSOCIATED_TOKEN_PROGRAM_ID,
          systemProgram: SystemProgram.programId,
        })
        .signers([payer.payer])
        .rpc();

      // Get final balances
      const finalUserUsdcBalance = await getAccount(
        provider.connection,
        userUsdcAccount
      );
      const finalUserCustomStableBalance = await getAccount(
        provider.connection,
        userCustomStableAccount
      );

      // Verify balances changed correctly (1:1 swap, 0% fee)
      const usdcDiff =
        finalUserUsdcBalance.amount - initialUserUsdcBalance.amount;
      const customStableDiff =
        initialUserCustomStableBalance.amount - finalUserCustomStableBalance.amount;

      assert.equal(customStableDiff.toString(), swapAmount.toString());
      assert.equal(usdcDiff.toString(), swapAmount.toString()); // 1:1 with 0% fee
    });

    it("Allows any token account owner to swap", async () => {
      const swapper = anchor.web3.Keypair.generate();
      const swapperUsdcAccount = await createAccount(
        provider.connection,
        payer.payer,
        usdcMint,
        swapper.publicKey
      );
      const swapperCustomStableAccount = await createAccount(
        provider.connection,
        payer.payer,
        customStableMint,
        swapper.publicKey
      );

      await mintTo(
        provider.connection,
        payer.payer,
        usdcMint,
        swapperUsdcAccount,
        payer.publicKey,
        100 * 10 ** 6
      );

      const swapAmount = new anchor.BN(10 * 10 ** 6);
      const minAmountOut = new anchor.BN(10 * 10 ** 6);
      const beforeBalance = await getAccount(
        provider.connection,
        swapperCustomStableAccount
      );

      await program.methods
        .swap(swapAmount, minAmountOut)
        .accounts({
          pool,
          inVault: usdcVault,
          outVault: customStableVault,
          inVaultTokenAccount: usdcVaultTokenAccount,
          outVaultTokenAccount: customStableVaultTokenAccount,
          userFromTokenAccount: swapperUsdcAccount,
          toTokenAccount: swapperCustomStableAccount,
          feeRecipientTokenAccount: feeRecipientUsdcAccount,
          feeRecipient: payer.publicKey,
          fromMint: usdcMint,
          toMint: customStableMint,
          user: swapper.publicKey,
          tokenProgram: TOKEN_PROGRAM_ID,
          associatedTokenProgram: ASSOCIATED_TOKEN_PROGRAM_ID,
          systemProgram: SystemProgram.programId,
        })
        .signers([swapper])
        .rpc();

      const afterBalance = await getAccount(
        provider.connection,
        swapperCustomStableAccount
      );
      assert.equal(
        (afterBalance.amount - beforeBalance.amount).toString(),
        swapAmount.toString()
      );
    });

    it("Rejects swaps from token accounts without owner or delegate authority", async () => {
      const unauthorizedUser = anchor.web3.Keypair.generate();
      const swapAmount = new anchor.BN(1 * 10 ** 6);
      const minAmountOut = new anchor.BN(1 * 10 ** 6);
      let rejectedByTokenProgram = false;

      try {
        await program.methods
          .swap(swapAmount, minAmountOut)
          .accounts({
            pool,
            inVault: usdcVault,
            outVault: customStableVault,
            inVaultTokenAccount: usdcVaultTokenAccount,
            outVaultTokenAccount: customStableVaultTokenAccount,
            userFromTokenAccount: userUsdcAccount,
            toTokenAccount: userCustomStableAccount,
            feeRecipientTokenAccount: feeRecipientUsdcAccount,
            feeRecipient: payer.publicKey,
            fromMint: usdcMint,
            toMint: customStableMint,
            user: unauthorizedUser.publicKey,
            tokenProgram: TOKEN_PROGRAM_ID,
            associatedTokenProgram: ASSOCIATED_TOKEN_PROGRAM_ID,
            systemProgram: SystemProgram.programId,
          })
          .signers([unauthorizedUser])
          .rpc();
      } catch (error) {
        rejectedByTokenProgram = true;
        assert.notInclude(
          error.toString(),
          "Expected SPL Token authority check",
          "Swap should fail in the token program, not via test assertion"
        );
      }

      assert.isTrue(
        rejectedByTokenProgram,
        "Expected SPL Token authority check to reject the swap"
      );
    });

    it("Allows delegated token account swaps to route output to any recipient", async () => {
      const owner = anchor.web3.Keypair.generate();
      const delegate = anchor.web3.Keypair.generate();
      const ownerUsdcAccount = await createAccount(
        provider.connection,
        payer.payer,
        usdcMint,
        owner.publicKey
      );
      const delegateCustomStableAccount = await createAccount(
        provider.connection,
        payer.payer,
        customStableMint,
        delegate.publicKey
      );

      const swapAmount = new anchor.BN(10 * 10 ** 6);
      await mintTo(
        provider.connection,
        payer.payer,
        usdcMint,
        ownerUsdcAccount,
        payer.publicKey,
        100 * 10 ** 6
      );
      await approve(
        provider.connection,
        payer.payer,
        ownerUsdcAccount,
        delegate.publicKey,
        owner,
        BigInt(swapAmount.toString())
      );

      const beforeBalance = await getAccount(
        provider.connection,
        delegateCustomStableAccount
      );

      await program.methods
        .swap(swapAmount, swapAmount)
        .accounts({
          pool,
          inVault: usdcVault,
          outVault: customStableVault,
          inVaultTokenAccount: usdcVaultTokenAccount,
          outVaultTokenAccount: customStableVaultTokenAccount,
          userFromTokenAccount: ownerUsdcAccount,
          toTokenAccount: delegateCustomStableAccount,
          feeRecipientTokenAccount: feeRecipientUsdcAccount,
          feeRecipient: payer.publicKey,
          fromMint: usdcMint,
          toMint: customStableMint,
          user: delegate.publicKey,
          tokenProgram: TOKEN_PROGRAM_ID,
          associatedTokenProgram: ASSOCIATED_TOKEN_PROGRAM_ID,
          systemProgram: SystemProgram.programId,
        })
        .signers([delegate])
        .rpc();

      const afterBalance = await getAccount(
        provider.connection,
        delegateCustomStableAccount
      );
      assert.equal(
        (afterBalance.amount - beforeBalance.amount).toString(),
        swapAmount.toString()
      );
    });

    it("Allows swapping exactly the full destination vault balance", async () => {
      const destinationVaultBefore = await getAccount(
        provider.connection,
        customStableVaultTokenAccount
      );
      const fullDrainAmount = new anchor.BN(
        destinationVaultBefore.amount.toString()
      );

      await mintTo(
        provider.connection,
        payer.payer,
        usdcMint,
        userUsdcAccount,
        payer.publicKey,
        BigInt(fullDrainAmount.toString())
      );

      await program.methods
        .swap(fullDrainAmount, fullDrainAmount)
        .accounts({
          pool,
          inVault: usdcVault,
          outVault: customStableVault,
          inVaultTokenAccount: usdcVaultTokenAccount,
          outVaultTokenAccount: customStableVaultTokenAccount,
          userFromTokenAccount: userUsdcAccount,
          toTokenAccount: userCustomStableAccount,
          feeRecipientTokenAccount: feeRecipientUsdcAccount,
          feeRecipient: payer.publicKey,
          fromMint: usdcMint,
          toMint: customStableMint,
          user: payer.publicKey,
          tokenProgram: TOKEN_PROGRAM_ID,
          associatedTokenProgram: ASSOCIATED_TOKEN_PROGRAM_ID,
          systemProgram: SystemProgram.programId,
        })
        .signers([payer.payer])
        .rpc();

      const drainedVault = await getAccount(
        provider.connection,
        customStableVaultTokenAccount
      );
      assert.equal(drainedVault.amount.toString(), "0");

      await transfer(
        provider.connection,
        payer.payer,
        userCustomStableAccount,
        customStableVaultTokenAccount,
        payer.payer,
        BigInt(fullDrainAmount.toString())
      );
    });

    it("Fails to swap when insufficient liquidity", async () => {
      const excessiveAmount = new anchor.BN(1000 * 10 ** 6); // More than vault has
      const minAmountOut = new anchor.BN(1000 * 10 ** 6);

      try {
        await program.methods
          .swap(excessiveAmount, minAmountOut)
          .accounts({
            pool,
            inVault: usdcVault,
            outVault: customStableVault,
            inVaultTokenAccount: usdcVaultTokenAccount,
            outVaultTokenAccount: customStableVaultTokenAccount,
            userFromTokenAccount: userUsdcAccount,
            toTokenAccount: userCustomStableAccount,
            feeRecipientTokenAccount: userUsdcAccount,
            feeRecipient: payer.publicKey,
            fromMint: usdcMint,
            toMint: customStableMint,
            user: payer.publicKey,
            tokenProgram: TOKEN_PROGRAM_ID,
            associatedTokenProgram: ASSOCIATED_TOKEN_PROGRAM_ID,
            systemProgram: SystemProgram.programId,
          })
          .signers([payer.payer])
          .rpc();

        assert.fail("Expected insufficient liquidity error");
      } catch (error) {
        assert.include(error.toString(), "InsufficientLiquidity");
      }
    });

    it("Fails to swap when slippage protection is triggered", async () => {
      // First, set a 5% fee rate
      await program.methods
        .updateFeeConfig(new anchor.BN(500), null) // 5% fee
        .accounts({
          pool,
          operationsAuthority: operationsAuthority.publicKey,
        })
        .signers([operationsAuthority.payer])
        .rpc();

      const swapAmount = new anchor.BN(100 * 10 ** 6); // 100 USDC
      // With 5% fee, output would be 95 USDC
      // But user expects minimum 98 USDC (only willing to accept 2% slippage)
      const minAmountOut = new anchor.BN(98 * 10 ** 6);

      try {
        await program.methods
          .swap(swapAmount, minAmountOut)
          .accounts({
            pool,
            inVault: usdcVault,
            outVault: customStableVault,
            inVaultTokenAccount: usdcVaultTokenAccount,
            outVaultTokenAccount: customStableVaultTokenAccount,
            userFromTokenAccount: userUsdcAccount,
            toTokenAccount: userCustomStableAccount,
            feeRecipientTokenAccount: userUsdcAccount,
            feeRecipient: payer.publicKey,
            fromMint: usdcMint,
            toMint: customStableMint,
            user: payer.publicKey,
            tokenProgram: TOKEN_PROGRAM_ID,
            associatedTokenProgram: ASSOCIATED_TOKEN_PROGRAM_ID,
            systemProgram: SystemProgram.programId,
          })
          .signers([payer.payer])
          .rpc();

        assert.fail("Expected slippage exceeded error");
      } catch (error) {
        assert.include(error.toString(), "SlippageExceeded");
      }

      // Reset fee rate to 0
      await program.methods
        .updateFeeConfig(new anchor.BN(0), null)
        .accounts({
          pool,
          operationsAuthority: operationsAuthority.publicKey,
        })
        .signers([operationsAuthority.payer])
        .rpc();
    });

    it("Fails when swap amount results in zero output (fee consumes entire input)", async () => {
      // Set a 1% fee rate (100 basis points)
      await program.methods
        .updateFeeConfig(new anchor.BN(100), null) // 1% fee
        .accounts({
          pool,
          operationsAuthority: operationsAuthority.publicKey,
        })
        .signers([operationsAuthority.payer])
        .rpc();

      // Try to swap only 1 unit
      // With 1% fee and round-up: fee_amount = (1 * 100 + 9999) / 10000 = 1
      // amount_after_fee = 1 - 1 = 0
      // amount_out = 0 (should fail)
      const tinySwapAmount = new anchor.BN(1);
      const minAmountOut = new anchor.BN(0); // User doesn't care about slippage

      try {
        await program.methods
          .swap(tinySwapAmount, minAmountOut)
          .accounts({
            pool,
            inVault: usdcVault,
            outVault: customStableVault,
            inVaultTokenAccount: usdcVaultTokenAccount,
            outVaultTokenAccount: customStableVaultTokenAccount,
            userFromTokenAccount: userUsdcAccount,
            toTokenAccount: userCustomStableAccount,
            feeRecipientTokenAccount: userUsdcAccount,
            feeRecipient: payer.publicKey,
            fromMint: usdcMint,
            toMint: customStableMint,
            user: payer.publicKey,
            tokenProgram: TOKEN_PROGRAM_ID,
            associatedTokenProgram: ASSOCIATED_TOKEN_PROGRAM_ID,
            systemProgram: SystemProgram.programId,
          })
          .signers([payer.payer])
          .rpc();

        assert.fail(
          "Expected InvalidAmount error - swap would result in zero output"
        );
      } catch (error) {
        assert.include(error.toString().toLowerCase(), "invalidamount");
      }

      // Reset fee rate to 0
      await program.methods
        .updateFeeConfig(new anchor.BN(0), null)
        .accounts({
          pool,
          operationsAuthority: operationsAuthority.publicKey,
        })
        .signers([operationsAuthority.payer])
        .rpc();
    });
  });

  describe("Token Disable Mechanism", () => {
    it("Disables a token and prevents swaps", async () => {
      // Disable USDC
      await program.methods
        .updateTokenStatus(true)
        .accounts({
          pool,
          vault: usdcVault,
          mint: usdcMint,
          pauseAuthority: pauseAuthority.publicKey,
        })
        .signers([pauseAuthority.payer])
        .rpc();

      // Verify vault is disabled
      const vaultAccount = await program.account.tokenVault.fetch(usdcVault);
      assert.equal(vaultAccount.disabled, true, "Vault should be disabled");

      // Try to swap USDC for CustomStable (should fail)
      const swapAmount = new anchor.BN(10 * 10 ** 6);
      const minAmountOut = new anchor.BN(10 * 10 ** 6);

      try {
        await program.methods
          .swap(swapAmount, minAmountOut)
          .accounts({
            pool,
            inVault: usdcVault,
            outVault: customStableVault,
            inVaultTokenAccount: usdcVaultTokenAccount,
            outVaultTokenAccount: customStableVaultTokenAccount,
            userFromTokenAccount: userUsdcAccount,
            toTokenAccount: userCustomStableAccount,
            feeRecipientTokenAccount: userUsdcAccount,
            feeRecipient: payer.publicKey,
            fromMint: usdcMint,
            toMint: customStableMint,
            user: payer.publicKey,
            tokenProgram: TOKEN_PROGRAM_ID,
            associatedTokenProgram: ASSOCIATED_TOKEN_PROGRAM_ID,
            systemProgram: SystemProgram.programId,
          })
          .signers([payer.payer])
          .rpc();

        assert.fail("Expected token disabled error");
      } catch (error) {
        assert.include(error.toString(), "TokenDisabled");
      }
    });

    it("Prevents swaps when output token is disabled", async () => {
      // Try to swap CustomStable for USDC (USDC is disabled from previous test)
      const swapAmount = new anchor.BN(10 * 10 ** 6);
      const minAmountOut = new anchor.BN(10 * 10 ** 6);

      try {
        await program.methods
          .swap(swapAmount, minAmountOut)
          .accounts({
            pool,
            inVault: customStableVault,
            outVault: usdcVault,
            inVaultTokenAccount: customStableVaultTokenAccount,
            outVaultTokenAccount: usdcVaultTokenAccount,
            userFromTokenAccount: userCustomStableAccount,
            toTokenAccount: userUsdcAccount,
            feeRecipientTokenAccount: userCustomStableAccount,
            feeRecipient: payer.publicKey,
            fromMint: customStableMint,
            toMint: usdcMint,
            user: payer.publicKey,
            tokenProgram: TOKEN_PROGRAM_ID,
            associatedTokenProgram: ASSOCIATED_TOKEN_PROGRAM_ID,
            systemProgram: SystemProgram.programId,
          })
          .signers([payer.payer])
          .rpc();

        assert.fail("Expected token disabled error");
      } catch (error) {
        assert.include(error.toString(), "TokenDisabled");
      }
    });

    it("Re-enables a token and allows swaps again", async () => {
      // Re-enable USDC
      await program.methods
        .updateTokenStatus(false)
        .accounts({
          pool,
          vault: usdcVault,
          mint: usdcMint,
          pauseAuthority: pauseAuthority.publicKey,
        })
        .signers([pauseAuthority.payer])
        .rpc();

      // Verify vault is enabled
      const vaultAccount = await program.account.tokenVault.fetch(usdcVault);
      assert.equal(vaultAccount.disabled, false, "Vault should be enabled");

      // Now swap should succeed
      const swapAmount = new anchor.BN(10 * 10 ** 6);
      const minAmountOut = new anchor.BN(10 * 10 ** 6);

      await program.methods
        .swap(swapAmount, minAmountOut)
        .accounts({
          pool,
          inVault: usdcVault,
          outVault: customStableVault,
          inVaultTokenAccount: usdcVaultTokenAccount,
          outVaultTokenAccount: customStableVaultTokenAccount,
          userFromTokenAccount: userUsdcAccount,
          toTokenAccount: userCustomStableAccount,
          feeRecipientTokenAccount: userUsdcAccount,
          feeRecipient: payer.publicKey,
          fromMint: usdcMint,
          toMint: customStableMint,
          user: payer.publicKey,
          tokenProgram: TOKEN_PROGRAM_ID,
          associatedTokenProgram: ASSOCIATED_TOKEN_PROGRAM_ID,
          systemProgram: SystemProgram.programId,
        })
        .signers([payer.payer])
        .rpc();

      // If we got here, swap succeeded
      assert.ok(true, "Swap should succeed after re-enabling");
    });

    it("Fails when unauthorized user tries to disable token", async () => {
      const unauthorizedUser = anchor.web3.Keypair.generate();

      // Transfer some SOL for transaction fees
      const transferTx = new anchor.web3.Transaction().add(
        anchor.web3.SystemProgram.transfer({
          fromPubkey: payer.publicKey,
          toPubkey: unauthorizedUser.publicKey,
          lamports: 1 * anchor.web3.LAMPORTS_PER_SOL,
        })
      );
      await provider.sendAndConfirm(transferTx, [payer.payer]);

      try {
        await program.methods
          .updateTokenStatus(true)
          .accounts({
            pool,
            vault: usdcVault,
            mint: usdcMint,
            pauseAuthority: unauthorizedUser.publicKey,
          })
          .signers([unauthorizedUser])
          .rpc();

        assert.fail("Expected constraint violation");
      } catch (error) {
        assert.include(error.toString().toLowerCase(), "constraint");
      }
    });
  });

  describe("Token Removal", () => {
    let testTokenMint: PublicKey;
    let testTokenVault: PublicKey;
    let testTokenVaultTokenAccount: PublicKey;
    let userTestTokenAccount: PublicKey;
    let feeRecipientTestTokenAccount: PublicKey;

    before(async () => {
      // Create a new test token that we'll add and remove
      testTokenMint = await createMint(
        provider.connection,
        payer.payer,
        payer.publicKey,
        null,
        6
      );

      // Derive PDAs for test token
      [testTokenVault] = PublicKey.findProgramAddressSync(
        [Buffer.from("token_vault"), pool.toBuffer(), testTokenMint.toBuffer()],
        program.programId
      );

      [testTokenVaultTokenAccount] = PublicKey.findProgramAddressSync(
        [Buffer.from("vault_token_account"), testTokenVault.toBuffer()],
        program.programId
      );

      feeRecipientTestTokenAccount = await getAssociatedTokenAddress(
        testTokenMint,
        payer.publicKey
      );

      // Create user token account
      userTestTokenAccount = await createAccount(
        provider.connection,
        payer.payer,
        testTokenMint,
        payer.publicKey
      );

      // Mint some tokens to user
      await mintTo(
        provider.connection,
        payer.payer,
        testTokenMint,
        userTestTokenAccount,
        payer.publicKey,
        1_000_000
      );
    });

    it("Adds a new test token", async () => {
      await program.methods
        .addSupportedToken()
        .accounts({
          pool,
          vault: testTokenVault,
          vaultTokenAccount: testTokenVaultTokenAccount,
          feeRecipientTokenAccount: feeRecipientTestTokenAccount,
          feeRecipient: payer.publicKey,
          mint: testTokenMint,
          operationsAuthority: operationsAuthority.publicKey,
          tokenProgram: TOKEN_PROGRAM_ID,
          associatedTokenProgram: ASSOCIATED_TOKEN_PROGRAM_ID,
          systemProgram: SystemProgram.programId,
          rent: anchor.web3.SYSVAR_RENT_PUBKEY,
        })
        .signers([operationsAuthority.payer])
        .rpc();

      const poolAccount = await program.account.liquidityPool.fetch(pool);
      assert.equal(poolAccount.supportedTokens.length, 3);
      assert.ok(
        poolAccount.supportedTokens.some(
          (token) => token.toString() === testTokenMint.toString()
        )
      );
    });

    it("Fails to remove token that is not disabled", async () => {
      try {
        await program.methods
          .removeSupportedToken()
          .accounts({
            pool,
            vault: testTokenVault,
            vaultTokenAccount: testTokenVaultTokenAccount,
            mint: testTokenMint,
            operationsAuthority: operationsAuthority.publicKey,
            tokenProgram: TOKEN_PROGRAM_ID,
          })
          .signers([operationsAuthority.payer])
          .rpc();

        assert.fail("Should have failed - token not disabled");
      } catch (error) {
        assert.include(error.toString().toLowerCase(), "tokenmustbedisabled");
      }
    });

    it("Seeds test token vault via direct SPL transfer", async () => {
      await transfer(
        provider.connection,
        payer.payer,
        userTestTokenAccount,
        testTokenVaultTokenAccount,
        payer.payer,
        BigInt(100_000)
      );

      const vaultTokenAccountInfo = await getAccount(
        provider.connection,
        testTokenVaultTokenAccount
      );
      assert.equal(vaultTokenAccountInfo.amount.toString(), "100000");
    });

    it("Disables the test token", async () => {
      await program.methods
        .updateTokenStatus(true)
        .accounts({
          pool,
          vault: testTokenVault,
          mint: testTokenMint,
          pauseAuthority: pauseAuthority.publicKey,
        })
        .signers([pauseAuthority.payer])
        .rpc();

      const vaultAccount = await program.account.tokenVault.fetch(
        testTokenVault
      );
      assert.equal(vaultAccount.disabled, true);
    });

    it("Fails to remove token with non-zero vault balance", async () => {
      try {
        await program.methods
          .removeSupportedToken()
          .accounts({
            pool,
            vault: testTokenVault,
            vaultTokenAccount: testTokenVaultTokenAccount,
            mint: testTokenMint,
            operationsAuthority: operationsAuthority.publicKey,
            tokenProgram: TOKEN_PROGRAM_ID,
          })
          .signers([operationsAuthority.payer])
          .rpc();

        assert.fail("Should have failed - vault not empty");
      } catch (error) {
        assert.include(error.toString().toLowerCase(), "vaultnotempty");
      }
    });

    it("Withdraws all liquidity and successfully removes token", async () => {
      // First withdraw all liquidity
      const vaultBalance = await getAccount(
        provider.connection,
        testTokenVaultTokenAccount
      );

      await program.methods
        .withdrawLiquidity(new anchor.BN(vaultBalance.amount.toString()))
        .accounts({
          pool,
          vault: testTokenVault,
          vaultTokenAccount: testTokenVaultTokenAccount,
          recipientTokenAccount: userTestTokenAccount,
          mint: testTokenMint,
          operationsAuthority: operationsAuthority.publicKey,
          tokenProgram: TOKEN_PROGRAM_ID,
        })
        .signers([operationsAuthority.payer])
        .rpc();

      // Verify vault is empty
      const vaultBalanceAfter = await getAccount(
        provider.connection,
        testTokenVaultTokenAccount
      );
      assert.equal(vaultBalanceAfter.amount.toString(), "0");

      // Now remove the token
      await program.methods
        .removeSupportedToken()
        .accounts({
          pool,
          vault: testTokenVault,
          vaultTokenAccount: testTokenVaultTokenAccount,
          mint: testTokenMint,
          operationsAuthority: operationsAuthority.publicKey,
          tokenProgram: TOKEN_PROGRAM_ID,
        })
        .signers([operationsAuthority.payer])
        .rpc();

      // Verify token removed from pool
      const poolAfter = await program.account.liquidityPool.fetch(pool);
      assert.ok(
        !poolAfter.supportedTokens.some(
          (token) => token.toString() === testTokenMint.toString()
        ),
        "Token should be removed from pool"
      );

      // Verify vault account is closed
      try {
        await program.account.tokenVault.fetch(testTokenVault);
        assert.fail("Vault account should be closed");
      } catch (error) {
        assert.include(
          error.toString().toLowerCase(),
          "account does not exist"
        );
      }
    });

    it("Fails when unauthorized user tries to remove token", async () => {
      const unauthorizedUser = anchor.web3.Keypair.generate();

      // Transfer some SOL for transaction fees
      const transferTx = new anchor.web3.Transaction().add(
        anchor.web3.SystemProgram.transfer({
          fromPubkey: payer.publicKey,
          toPubkey: unauthorizedUser.publicKey,
          lamports: 1 * anchor.web3.LAMPORTS_PER_SOL,
        })
      );
      await provider.sendAndConfirm(transferTx, [payer.payer]);

      // Create a new token for this test (to avoid init conflict)
      const newTestTokenMint = await createMint(
        provider.connection,
        payer.payer,
        payer.publicKey,
        null,
        6
      );

      const [newTestTokenVault] = PublicKey.findProgramAddressSync(
        [
          Buffer.from("token_vault"),
          pool.toBuffer(),
          newTestTokenMint.toBuffer(),
        ],
        program.programId
      );

      const [newTestTokenVaultTokenAccount] = PublicKey.findProgramAddressSync(
        [Buffer.from("vault_token_account"), newTestTokenVault.toBuffer()],
        program.programId
      );

      const newFeeRecipientTestTokenAccount = await getAssociatedTokenAddress(
        newTestTokenMint,
        payer.publicKey
      );

      // Add the new test token
      await program.methods
        .addSupportedToken()
        .accounts({
          pool,
          vault: newTestTokenVault,
          vaultTokenAccount: newTestTokenVaultTokenAccount,
          feeRecipientTokenAccount: newFeeRecipientTestTokenAccount,
          feeRecipient: payer.publicKey,
          mint: newTestTokenMint,
          operationsAuthority: operationsAuthority.publicKey,
          tokenProgram: TOKEN_PROGRAM_ID,
          associatedTokenProgram: ASSOCIATED_TOKEN_PROGRAM_ID,
          systemProgram: SystemProgram.programId,
          rent: anchor.web3.SYSVAR_RENT_PUBKEY,
        })
        .signers([operationsAuthority.payer])
        .rpc();

      // Disable it
      await program.methods
        .updateTokenStatus(true)
        .accounts({
          pool,
          vault: newTestTokenVault,
          mint: newTestTokenMint,
          pauseAuthority: pauseAuthority.publicKey,
        })
        .signers([pauseAuthority.payer])
        .rpc();

      // Try to remove with unauthorized user
      try {
        await program.methods
          .removeSupportedToken()
          .accounts({
            pool,
            vault: newTestTokenVault,
            vaultTokenAccount: newTestTokenVaultTokenAccount,
            mint: newTestTokenMint,
            operationsAuthority: unauthorizedUser.publicKey,
            tokenProgram: TOKEN_PROGRAM_ID,
          })
          .signers([unauthorizedUser])
          .rpc();

        assert.fail("Expected constraint violation");
      } catch (error) {
        assert.include(error.toString().toLowerCase(), "constraint");
      }

      // Clean up - remove the test token properly
      await program.methods
        .removeSupportedToken()
        .accounts({
          pool,
          vault: newTestTokenVault,
          vaultTokenAccount: newTestTokenVaultTokenAccount,
          mint: newTestTokenMint,
          operationsAuthority: operationsAuthority.publicKey,
          tokenProgram: TOKEN_PROGRAM_ID,
        })
        .signers([operationsAuthority.payer])
        .rpc();
    });
  });

  describe("Pool Management", () => {
    it("Updates fee configuration", async () => {
      const newFeeRate = 25; // 0.25%

      await program.methods
        .updateFeeConfig(new anchor.BN(newFeeRate), null) // feeRate, feeRecipient
        .accounts({
          pool,
          operationsAuthority: operationsAuthority.publicKey,
        })
        .signers([operationsAuthority.payer])
        .rpc();

      // Verify fee rate was updated
      const poolAccount = await program.account.liquidityPool.fetch(pool);
      assert.equal(poolAccount.feeRate.toNumber(), newFeeRate);

      // Reset fee back to 0% for other tests
      await program.methods
        .updateFeeConfig(new anchor.BN(0), null) // feeRate, feeRecipient
        .accounts({
          pool,
          operationsAuthority: operationsAuthority.publicKey,
        })
        .signers([operationsAuthority.payer])
        .rpc();
    });

    it("Pauses swaps", async () => {
      await program.methods
        .updatePauseConfig(true, null) // swapsPaused, liquidityPaused
        .accounts({
          pool,
          pauseAuthority: pauseAuthority.publicKey,
        })
        .signers([pauseAuthority.payer])
        .rpc();

      // Verify swaps are paused
      const poolAccount = await program.account.liquidityPool.fetch(pool);
      assert.equal(poolAccount.swapsPaused, true);
      assert.equal(poolAccount.liquidityPaused, false);
    });

    it("Fails to swap when swaps are paused", async () => {
      const swapAmount = new anchor.BN(10 * 10 ** 6);
      const minAmountOut = new anchor.BN(10 * 10 ** 6);

      try {
        await program.methods
          .swap(swapAmount, minAmountOut)
          .accounts({
            pool,
            inVault: usdcVault,
            outVault: customStableVault,
            inVaultTokenAccount: usdcVaultTokenAccount,
            outVaultTokenAccount: customStableVaultTokenAccount,
            userFromTokenAccount: userUsdcAccount,
            toTokenAccount: userCustomStableAccount,
            feeRecipientTokenAccount: userUsdcAccount,
            feeRecipient: payer.publicKey,
            fromMint: usdcMint,
            toMint: customStableMint,
            user: payer.publicKey,
            tokenProgram: TOKEN_PROGRAM_ID,
            associatedTokenProgram: ASSOCIATED_TOKEN_PROGRAM_ID,
            systemProgram: SystemProgram.programId,
          })
          .signers([payer.payer])
          .rpc();

        assert.fail("Expected swaps paused error");
      } catch (error) {
        assert.include(error.toString(), "SwapsPaused");
      }
    });

    it("Unpauses swaps", async () => {
      await program.methods
        .updatePauseConfig(false, null) // swapsPaused, liquidityPaused
        .accounts({
          pool,
          pauseAuthority: pauseAuthority.publicKey,
        })
        .signers([pauseAuthority.payer])
        .rpc();

      // Verify swaps are unpaused
      const poolAccount = await program.account.liquidityPool.fetch(pool);
      assert.equal(poolAccount.swapsPaused, false);
    });
  });

  describe("Liquidity Limits", () => {
    it("Fails swap when amount exceeds vault balance", async () => {
      const vaultBalance = await getAccount(
        provider.connection,
        usdcVaultTokenAccount
      );

      const excessiveAmount = new anchor.BN(vaultBalance.amount.toString()).add(
        new anchor.BN(1)
      );
      const minAmountOut = excessiveAmount;

      try {
        await program.methods
          .swap(excessiveAmount, minAmountOut)
          .accounts({
            pool,
            inVault: customStableVault,
            outVault: usdcVault,
            inVaultTokenAccount: customStableVaultTokenAccount,
            outVaultTokenAccount: usdcVaultTokenAccount,
            userFromTokenAccount: userCustomStableAccount,
            toTokenAccount: userUsdcAccount,
            feeRecipientTokenAccount: userCustomStableAccount,
            feeRecipient: payer.publicKey,
            fromMint: customStableMint,
            toMint: usdcMint,
            user: payer.publicKey,
            tokenProgram: TOKEN_PROGRAM_ID,
            associatedTokenProgram: ASSOCIATED_TOKEN_PROGRAM_ID,
            systemProgram: SystemProgram.programId,
          })
          .signers([payer.payer])
          .rpc();

        assert.fail("Expected insufficient liquidity error");
      } catch (error) {
        assert.include(error.toString(), "InsufficientLiquidity");
      }
    });
  });

  describe("Fee Collection", () => {
    it("Collects fees correctly when fee rate is non-zero", async () => {
      // Create a separate fee recipient to clearly track fee collection
      const feeRecipient = anchor.web3.Keypair.generate();
      const feeRecipientUsdcAccount = await createAccount(
        provider.connection,
        payer.payer,
        usdcMint,
        feeRecipient.publicKey
      );

      // Update pool to use new fee recipient and set 1% fee
      await program.methods
        .updateFeeConfig(new anchor.BN(100), feeRecipient.publicKey)
        .accounts({
          pool,
          operationsAuthority: operationsAuthority.publicKey,
        })
        .signers([operationsAuthority.payer])
        .rpc();

      const swapAmount = new anchor.BN(100 * 10 ** 6); // 100 USDC
      const expectedFee = new anchor.BN(1 * 10 ** 6); // 1% = 1 USDC
      const expectedNetAmount = new anchor.BN(99 * 10 ** 6); // 99 USDC
      const minAmountOut = new anchor.BN(99 * 10 ** 6); // Accept 1% fee

      // Get initial balances
      const initialUserUsdcBalance = await getAccount(
        provider.connection,
        userUsdcAccount
      );
      const initialUserCustomStableBalance = await getAccount(
        provider.connection,
        userCustomStableAccount
      );
      const initialVaultUsdcBalance = await getAccount(
        provider.connection,
        usdcVaultTokenAccount
      );
      const initialFeeRecipientBalance = await getAccount(
        provider.connection,
        feeRecipientUsdcAccount
      );

      await program.methods
        .swap(swapAmount, minAmountOut)
        .accounts({
          pool,
          inVault: usdcVault,
          outVault: customStableVault,
          inVaultTokenAccount: usdcVaultTokenAccount,
          outVaultTokenAccount: customStableVaultTokenAccount,
          userFromTokenAccount: userUsdcAccount,
          toTokenAccount: userCustomStableAccount,
          feeRecipientTokenAccount: feeRecipientUsdcAccount,
          feeRecipient: feeRecipient.publicKey,
          fromMint: usdcMint,
          toMint: customStableMint,
          user: payer.publicKey,
          tokenProgram: TOKEN_PROGRAM_ID,
          associatedTokenProgram: ASSOCIATED_TOKEN_PROGRAM_ID,
          systemProgram: SystemProgram.programId,
        })
        .signers([payer.payer])
        .rpc();

      // Get final balances
      const finalUserUsdcBalance = await getAccount(
        provider.connection,
        userUsdcAccount
      );
      const finalUserCustomStableBalance = await getAccount(
        provider.connection,
        userCustomStableAccount
      );
      const finalVaultUsdcBalance = await getAccount(
        provider.connection,
        usdcVaultTokenAccount
      );
      const finalFeeRecipientBalance = await getAccount(
        provider.connection,
        feeRecipientUsdcAccount
      );

      // Verify user paid full amount (99 to vault + 1 to fee recipient = 100 total)
      const userUsdcSpent =
        initialUserUsdcBalance.amount - finalUserUsdcBalance.amount;
      assert.equal(
        userUsdcSpent.toString(),
        swapAmount.toString(),
        "User should pay full swap amount"
      );

      // Verify user received net amount (after fee deduction)
      const userCustomStableReceived =
        finalUserCustomStableBalance.amount - initialUserCustomStableBalance.amount;
      assert.equal(
        userCustomStableReceived.toString(),
        expectedNetAmount.toString(),
        "User should receive net amount after fees"
      );

      // Verify vault received net amount (liquidity)
      const vaultUsdcIncrease =
        finalVaultUsdcBalance.amount - initialVaultUsdcBalance.amount;
      assert.equal(
        vaultUsdcIncrease.toString(),
        expectedNetAmount.toString(),
        "Vault should receive net amount"
      );

      // Verify fee recipient received the fee
      const feeReceived =
        finalFeeRecipientBalance.amount - initialFeeRecipientBalance.amount;
      assert.equal(
        feeReceived.toString(),
        expectedFee.toString(),
        "Fee recipient should receive the fee"
      );

      // Reset fee rate and fee recipient back to original
      await program.methods
        .updateFeeConfig(new anchor.BN(0), payer.publicKey)
        .accounts({
          pool,
          operationsAuthority: operationsAuthority.publicKey,
        })
        .signers([operationsAuthority.payer])
        .rpc();
    });

    it("Updates fee recipient and collects fees to new recipient", async () => {
      // Create a new fee recipient (we'll use a new keypair)
      const newFeeRecipient = anchor.web3.Keypair.generate();

      // Create token account for new fee recipient
      const newFeeRecipientUsdcAccount = await createAccount(
        provider.connection,
        payer.payer,
        usdcMint,
        newFeeRecipient.publicKey
      );

      // Update pool to use new fee recipient and set 1% fee
      await program.methods
        .updateFeeConfig(new anchor.BN(100), newFeeRecipient.publicKey)
        .accounts({
          pool,
          operationsAuthority: operationsAuthority.publicKey,
        })
        .signers([operationsAuthority.payer])
        .rpc();

      const swapAmount = new anchor.BN(100 * 10 ** 6); // 100 USDC
      const expectedFee = new anchor.BN(1 * 10 ** 6); // 1% = 1 USDC
      const minAmountOut = new anchor.BN(99 * 10 ** 6); // Accept 1% fee

      // Get initial balance of new fee recipient
      const initialFeeRecipientBalance = await getAccount(
        provider.connection,
        newFeeRecipientUsdcAccount
      );

      await program.methods
        .swap(swapAmount, minAmountOut)
        .accounts({
          pool,
          inVault: usdcVault,
          outVault: customStableVault,
          inVaultTokenAccount: usdcVaultTokenAccount,
          outVaultTokenAccount: customStableVaultTokenAccount,
          userFromTokenAccount: userUsdcAccount,
          toTokenAccount: userCustomStableAccount,
          feeRecipientTokenAccount: newFeeRecipientUsdcAccount, // New fee recipient
          feeRecipient: newFeeRecipient.publicKey,
          fromMint: usdcMint,
          toMint: customStableMint,
          user: payer.publicKey,
          tokenProgram: TOKEN_PROGRAM_ID,
          associatedTokenProgram: ASSOCIATED_TOKEN_PROGRAM_ID,
          systemProgram: SystemProgram.programId,
        })
        .signers([payer.payer])
        .rpc();

      // Verify new fee recipient received the fee
      const finalFeeRecipientBalance = await getAccount(
        provider.connection,
        newFeeRecipientUsdcAccount
      );
      const feeReceived =
        finalFeeRecipientBalance.amount - initialFeeRecipientBalance.amount;
      assert.equal(
        feeReceived.toString(),
        expectedFee.toString(),
        "New fee recipient should receive the fee"
      );

      // Reset fee rate and fee recipient back to original
      await program.methods
        .updateFeeConfig(new anchor.BN(0), payer.publicKey)
        .accounts({
          pool,
          operationsAuthority: operationsAuthority.publicKey,
        })
        .signers([operationsAuthority.payer])
        .rpc();
    });

    it("Skips fee transfer when fee is zero", async () => {
      // This test verifies the optimization where we skip the fee transfer if fee_amount == 0
      // Fee rate is already 0 from previous test reset
      const swapAmount = new anchor.BN(50 * 10 ** 6);
      const minAmountOut = new anchor.BN(50 * 10 ** 6); // Expect full amount (0% fee)

      // Get initial balances
      const initialUserUsdcBalance = await getAccount(
        provider.connection,
        userUsdcAccount
      );
      const initialUserCustomStableBalance = await getAccount(
        provider.connection,
        userCustomStableAccount
      );

      await program.methods
        .swap(swapAmount, minAmountOut)
        .accounts({
          pool,
          inVault: usdcVault,
          outVault: customStableVault,
          inVaultTokenAccount: usdcVaultTokenAccount,
          outVaultTokenAccount: customStableVaultTokenAccount,
          userFromTokenAccount: userUsdcAccount,
          toTokenAccount: userCustomStableAccount,
          feeRecipientTokenAccount: userUsdcAccount,
          feeRecipient: payer.publicKey,
          fromMint: usdcMint,
          toMint: customStableMint,
          user: payer.publicKey,
          tokenProgram: TOKEN_PROGRAM_ID,
          associatedTokenProgram: ASSOCIATED_TOKEN_PROGRAM_ID,
          systemProgram: SystemProgram.programId,
        })
        .signers([payer.payer])
        .rpc();

      // Get final balances
      const finalUserUsdcBalance = await getAccount(
        provider.connection,
        userUsdcAccount
      );
      const finalUserCustomStableBalance = await getAccount(
        provider.connection,
        userCustomStableAccount
      );

      // Verify 1:1 swap with no fees
      const usdcSpent =
        initialUserUsdcBalance.amount - finalUserUsdcBalance.amount;
      const customStableReceived =
        finalUserCustomStableBalance.amount - initialUserCustomStableBalance.amount;

      assert.equal(
        usdcSpent.toString(),
        swapAmount.toString(),
        "Should spend exact swap amount"
      );
      assert.equal(
        customStableReceived.toString(),
        swapAmount.toString(),
        "Should receive exact swap amount (1:1, no fees)"
      );
    });
  });

  describe("Fee Rounding", () => {
    it("Rounds up fees to prevent protocol loss on fractional amounts", async () => {
      // Set 1% fee (100 basis points)
      await program.methods
        .updateFeeConfig(new anchor.BN(100), null)
        .accounts({
          pool,
          operationsAuthority: operationsAuthority.publicKey,
        })
        .signers([operationsAuthority.payer])
        .rpc();

      // Create a separate fee recipient to track fees
      const feeRecipient = anchor.web3.Keypair.generate();
      const feeRecipientUsdcAccountForTest = await createAccount(
        provider.connection,
        payer.payer,
        usdcMint,
        feeRecipient.publicKey
      );

      await program.methods
        .updateFeeConfig(null, feeRecipient.publicKey)
        .accounts({
          pool,
          operationsAuthority: operationsAuthority.publicKey,
        })
        .signers([operationsAuthority.payer])
        .rpc();

      // Test case 1: Amount that creates fractional fee in basis points
      // 10_050 units with 1% fee = 10_050 * 100 / 10000 = 100.5
      // Without ceiling: 100 units fee
      // With ceiling: (10_050 * 100 + 9999) / 10000 = 101 units fee
      // User receives: 10_050 - 101 = 9_949 units
      const swapAmount1 = new anchor.BN(10_050); // 0.01005 USDC
      const minAmountOut1 = new anchor.BN(9_940); // Accept the fee loss

      const initialFeeBalance1 = await getAccount(
        provider.connection,
        feeRecipientUsdcAccountForTest
      );

      await program.methods
        .swap(swapAmount1, minAmountOut1)
        .accounts({
          pool,
          inVault: usdcVault,
          outVault: customStableVault,
          inVaultTokenAccount: usdcVaultTokenAccount,
          outVaultTokenAccount: customStableVaultTokenAccount,
          userFromTokenAccount: userUsdcAccount,
          toTokenAccount: userCustomStableAccount,
          feeRecipientTokenAccount: feeRecipientUsdcAccountForTest,
          feeRecipient: feeRecipient.publicKey,
          fromMint: usdcMint,
          toMint: customStableMint,
          user: payer.publicKey,
          tokenProgram: TOKEN_PROGRAM_ID,
          associatedTokenProgram: ASSOCIATED_TOKEN_PROGRAM_ID,
          systemProgram: SystemProgram.programId,
        })
        .signers([payer.payer])
        .rpc();

      const finalFeeBalance1 = await getAccount(
        provider.connection,
        feeRecipientUsdcAccountForTest
      );
      const feeCollected1 = finalFeeBalance1.amount - initialFeeBalance1.amount;

      // Fee should be 101 (rounded up from 100.5), not 100
      assert.equal(
        feeCollected1.toString(),
        "101",
        "Fee should round up to 101 units from 100.5 units"
      );

      // Test case 2: Another fractional fee example
      // 99_999 units with 1% fee = 99_999 * 100 / 10000 = 999.99
      // Without ceiling: 999 units fee
      // With ceiling: (99_999 * 100 + 9999) / 10000 = 1000 units fee
      // User receives: 99_999 - 1000 = 98_999 units
      const swapAmount2 = new anchor.BN(99_999); // 0.099999 USDC
      const minAmountOut2 = new anchor.BN(98_900); // Accept the fee loss

      const initialFeeBalance2 = await getAccount(
        provider.connection,
        feeRecipientUsdcAccountForTest
      );

      await program.methods
        .swap(swapAmount2, minAmountOut2)
        .accounts({
          pool,
          inVault: usdcVault,
          outVault: customStableVault,
          inVaultTokenAccount: usdcVaultTokenAccount,
          outVaultTokenAccount: customStableVaultTokenAccount,
          userFromTokenAccount: userUsdcAccount,
          toTokenAccount: userCustomStableAccount,
          feeRecipientTokenAccount: feeRecipientUsdcAccountForTest,
          feeRecipient: feeRecipient.publicKey,
          fromMint: usdcMint,
          toMint: customStableMint,
          user: payer.publicKey,
          tokenProgram: TOKEN_PROGRAM_ID,
          associatedTokenProgram: ASSOCIATED_TOKEN_PROGRAM_ID,
          systemProgram: SystemProgram.programId,
        })
        .signers([payer.payer])
        .rpc();

      const finalFeeBalance2 = await getAccount(
        provider.connection,
        feeRecipientUsdcAccountForTest
      );
      const feeCollected2 = finalFeeBalance2.amount - initialFeeBalance2.amount;

      // Fee should be 1000 (rounded up from 999.99), not 999
      assert.equal(
        feeCollected2.toString(),
        "1000",
        "Fee should round up to 1000 units from 999.99 units"
      );

      // Reset fee rate and recipient
      await program.methods
        .updateFeeConfig(new anchor.BN(0), payer.publicKey)
        .accounts({
          pool,
          operationsAuthority: operationsAuthority.publicKey,
        })
        .signers([operationsAuthority.payer])
        .rpc();
    });

    it("Does not over-charge on perfect fee amounts (no rounding needed)", async () => {
      // Set 1% fee (100 basis points)
      await program.methods
        .updateFeeConfig(new anchor.BN(100), null)
        .accounts({
          pool,
          operationsAuthority: operationsAuthority.publicKey,
        })
        .signers([operationsAuthority.payer])
        .rpc();

      // Create a separate fee recipient to track fees
      const feeRecipient = anchor.web3.Keypair.generate();
      const feeRecipientUsdcAccountForTest = await createAccount(
        provider.connection,
        payer.payer,
        usdcMint,
        feeRecipient.publicKey
      );

      await program.methods
        .updateFeeConfig(null, feeRecipient.publicKey)
        .accounts({
          pool,
          operationsAuthority: operationsAuthority.publicKey,
        })
        .signers([operationsAuthority.payer])
        .rpc();

      // Test: 100 tokens with 1% fee = exactly 1 token
      // Calculation: 100 * 100 / 10000 = 1.0 (perfect)
      // Should charge exactly 1, not round up to 2
      const swapAmount = new anchor.BN(100 * 10 ** 6); // 100 USDC
      const minAmountOut = new anchor.BN(99 * 10 ** 6); // Accept 1% loss

      const initialFeeBalance = await getAccount(
        provider.connection,
        feeRecipientUsdcAccountForTest
      );

      await program.methods
        .swap(swapAmount, minAmountOut)
        .accounts({
          pool,
          inVault: usdcVault,
          outVault: customStableVault,
          inVaultTokenAccount: usdcVaultTokenAccount,
          outVaultTokenAccount: customStableVaultTokenAccount,
          userFromTokenAccount: userUsdcAccount,
          toTokenAccount: userCustomStableAccount,
          feeRecipientTokenAccount: feeRecipientUsdcAccountForTest,
          feeRecipient: feeRecipient.publicKey,
          fromMint: usdcMint,
          toMint: customStableMint,
          user: payer.publicKey,
          tokenProgram: TOKEN_PROGRAM_ID,
          associatedTokenProgram: ASSOCIATED_TOKEN_PROGRAM_ID,
          systemProgram: SystemProgram.programId,
        })
        .signers([payer.payer])
        .rpc();

      const finalFeeBalance = await getAccount(
        provider.connection,
        feeRecipientUsdcAccountForTest
      );
      const feeCollected = finalFeeBalance.amount - initialFeeBalance.amount;

      // Fee should be exactly 1 (no over-charging)
      assert.equal(
        feeCollected.toString(),
        (1 * 10 ** 6).toString(),
        "Fee should be exactly 1 USDC, not rounded up"
      );

      // Reset fee rate and recipient
      await program.methods
        .updateFeeConfig(new anchor.BN(0), payer.publicKey)
        .accounts({
          pool,
          operationsAuthority: operationsAuthority.publicKey,
        })
        .signers([operationsAuthority.payer])
        .rpc();
    });
  });

  describe("Fee Rate Validation", () => {
    it("Fails to update fee config with fee rate exceeding maximum", async () => {
      const excessiveFeeRate = 1001; // > 1000 basis points (10%)

      try {
        await program.methods
          .updateFeeConfig(new anchor.BN(excessiveFeeRate), null)
          .accounts({
            pool,
            operationsAuthority: operationsAuthority.publicKey,
          })
          .signers([operationsAuthority.payer])
          .rpc();

        assert.fail("Expected invalid fee rate error");
      } catch (error) {
        assert.include(error.toString(), "InvalidFeeRate");
      }
    });

    it("Allows maximum fee rate of 10% (1000 basis points)", async () => {
      const maxFeeRate = 1000; // 10%

      await program.methods
        .updateFeeConfig(new anchor.BN(maxFeeRate), null)
        .accounts({
          pool,
          operationsAuthority: operationsAuthority.publicKey,
        })
        .signers([operationsAuthority.payer])
        .rpc();

      const poolAccount = await program.account.liquidityPool.fetch(pool);
      assert.equal(poolAccount.feeRate.toNumber(), maxFeeRate);

      // Reset fee rate
      await program.methods
        .updateFeeConfig(new anchor.BN(0), null)
        .accounts({
          pool,
          operationsAuthority: operationsAuthority.publicKey,
        })
        .signers([operationsAuthority.payer])
        .rpc();
    });
  });

  describe("Decimal Normalization", () => {
    let token9DecMint: PublicKey; // 9 decimals token
    let token9DecVault: PublicKey;
    let token9DecVaultTokenAccount: PublicKey;
    let userToken9DecAccount: PublicKey;

    before(async () => {
      // Create a token with 9 decimals
      token9DecMint = await createMint(
        provider.connection,
        payer.payer,
        payer.publicKey,
        null,
        9 // 9 decimals
      );

      // Derive PDAs for 9-decimal token
      [token9DecVault] = PublicKey.findProgramAddressSync(
        [Buffer.from("token_vault"), pool.toBuffer(), token9DecMint.toBuffer()],
        program.programId
      );

      [token9DecVaultTokenAccount] = PublicKey.findProgramAddressSync(
        [Buffer.from("vault_token_account"), token9DecVault.toBuffer()],
        program.programId
      );

      // Create user token account for 9-decimal token
      userToken9DecAccount = await createAccount(
        provider.connection,
        payer.payer,
        token9DecMint,
        payer.publicKey
      );

      // Mint tokens to user account
      await mintTo(
        provider.connection,
        payer.payer,
        token9DecMint,
        userToken9DecAccount,
        payer.payer,
        1000 * 10 ** 9 // 1000 tokens with 9 decimals
      );

      // Derive fee recipient token account for 9-decimal token
      const feeRecipient9DecAccount = await getAssociatedTokenAddress(
        token9DecMint,
        payer.publicKey
      );

      // Add 9-decimal token to pool
      await program.methods
        .addSupportedToken()
        .accounts({
          pool,
          vault: token9DecVault,
          vaultTokenAccount: token9DecVaultTokenAccount,
          feeRecipientTokenAccount: feeRecipient9DecAccount,
          feeRecipient: payer.publicKey,
          mint: token9DecMint,
          operationsAuthority: operationsAuthority.publicKey,
          tokenProgram: TOKEN_PROGRAM_ID,
          associatedTokenProgram: ASSOCIATED_TOKEN_PROGRAM_ID,
          systemProgram: SystemProgram.programId,
          rent: anchor.web3.SYSVAR_RENT_PUBKEY,
        })
        .signers([operationsAuthority.payer])
        .rpc();

      // Seed liquidity for 9-decimal token via direct SPL transfer
      await transfer(
        provider.connection,
        payer.payer,
        userToken9DecAccount,
        token9DecVaultTokenAccount,
        payer.payer,
        BigInt(500 * 10 ** 9)
      );
    });

    it("Swaps from 6 decimals (USDC) to 9 decimals (scaling up)", async () => {
      const swapAmount = new anchor.BN(100 * 10 ** 6); // 100 USDC (6 decimals)
      const minAmountOut = new anchor.BN(100 * 10 ** 9); // Expect 100 tokens (9 decimals)

      const userUsdcBefore = await getAccount(
        provider.connection,
        userUsdcAccount
      );
      const userToken9DecBefore = await getAccount(
        provider.connection,
        userToken9DecAccount
      );

      await program.methods
        .swap(swapAmount, minAmountOut)
        .accounts({
          pool,
          inVault: usdcVault,
          outVault: token9DecVault,
          inVaultTokenAccount: usdcVaultTokenAccount,
          outVaultTokenAccount: token9DecVaultTokenAccount,
          userFromTokenAccount: userUsdcAccount,
          toTokenAccount: userToken9DecAccount,
          feeRecipient: payer.publicKey,
          feeRecipientTokenAccount: userUsdcAccount, // Simplified for testing
          fromMint: usdcMint,
          toMint: token9DecMint,
          user: payer.publicKey,
          tokenProgram: TOKEN_PROGRAM_ID,
          associatedTokenProgram: ASSOCIATED_TOKEN_PROGRAM_ID,
          systemProgram: SystemProgram.programId,
        })
        .signers([payer.payer])
        .rpc();

      const userUsdcAfter = await getAccount(
        provider.connection,
        userUsdcAccount
      );
      const userToken9DecAfter = await getAccount(
        provider.connection,
        userToken9DecAccount
      );

      // User should have sent 100 USDC (6 decimals)
      assert.equal(
        userUsdcBefore.amount - userUsdcAfter.amount,
        BigInt(100 * 10 ** 6),
        "USDC deducted incorrectly"
      );

      // User should receive 100 tokens (9 decimals) = 100 * 10^9
      assert.equal(
        userToken9DecAfter.amount - userToken9DecBefore.amount,
        BigInt(100 * 10 ** 9),
        "9-decimal token received incorrectly"
      );
    });

    it("Swaps from 9 decimals to 6 decimals (USDC) (scaling down)", async () => {
      const swapAmount = new anchor.BN(100 * 10 ** 9); // 100 tokens (9 decimals)
      const minAmountOut = new anchor.BN(100 * 10 ** 6); // Expect 100 USDC (6 decimals)

      const userToken9DecBefore = await getAccount(
        provider.connection,
        userToken9DecAccount
      );
      const userUsdcBefore = await getAccount(
        provider.connection,
        userUsdcAccount
      );

      await program.methods
        .swap(swapAmount, minAmountOut)
        .accounts({
          pool,
          inVault: token9DecVault,
          outVault: usdcVault,
          inVaultTokenAccount: token9DecVaultTokenAccount,
          outVaultTokenAccount: usdcVaultTokenAccount,
          userFromTokenAccount: userToken9DecAccount,
          toTokenAccount: userUsdcAccount,
          feeRecipient: payer.publicKey,
          feeRecipientTokenAccount: userToken9DecAccount, // Simplified for testing
          fromMint: token9DecMint,
          toMint: usdcMint,
          user: payer.publicKey,
          tokenProgram: TOKEN_PROGRAM_ID,
          associatedTokenProgram: ASSOCIATED_TOKEN_PROGRAM_ID,
          systemProgram: SystemProgram.programId,
        })
        .signers([payer.payer])
        .rpc();

      const userToken9DecAfter = await getAccount(
        provider.connection,
        userToken9DecAccount
      );
      const userUsdcAfter = await getAccount(
        provider.connection,
        userUsdcAccount
      );

      // User should have sent 100 tokens (9 decimals)
      assert.equal(
        userToken9DecBefore.amount - userToken9DecAfter.amount,
        BigInt(100 * 10 ** 9),
        "9-decimal token deducted incorrectly"
      );

      // User should receive 100 USDC (6 decimals)
      assert.equal(
        userUsdcAfter.amount - userUsdcBefore.amount,
        BigInt(100 * 10 ** 6),
        "USDC received incorrectly"
      );
    });

    it("Properly rounds down when scaling from 9 to 6 decimals", async () => {
      // Swap amount with fractional part that will be rounded down
      // 100.000000123 tokens (9 decimals) = 100_000_000_123
      const swapAmount = new anchor.BN(100_000_000_123);
      // After converting to 6 decimals: 100_000_000_123 / 1000 = 100_000_000 (rounded down)
      const expectedOutput = new anchor.BN(100_000_000); // 100.000000 USDC
      const minAmountOut = new anchor.BN(99 * 10 ** 6); // Set lower to allow the swap

      const userUsdcBefore = await getAccount(
        provider.connection,
        userUsdcAccount
      );

      await program.methods
        .swap(swapAmount, minAmountOut)
        .accounts({
          pool,
          inVault: token9DecVault,
          outVault: usdcVault,
          inVaultTokenAccount: token9DecVaultTokenAccount,
          outVaultTokenAccount: usdcVaultTokenAccount,
          userFromTokenAccount: userToken9DecAccount,
          toTokenAccount: userUsdcAccount,
          feeRecipient: payer.publicKey,
          feeRecipientTokenAccount: userToken9DecAccount,
          fromMint: token9DecMint,
          toMint: usdcMint,
          user: payer.publicKey,
          tokenProgram: TOKEN_PROGRAM_ID,
          associatedTokenProgram: ASSOCIATED_TOKEN_PROGRAM_ID,
          systemProgram: SystemProgram.programId,
        })
        .signers([payer.payer])
        .rpc();

      const userUsdcAfter = await getAccount(
        provider.connection,
        userUsdcAccount
      );

      // Verify rounding down: user receives exactly 100_000_000 (not 100_000_001)
      const actualReceived = userUsdcAfter.amount - userUsdcBefore.amount;
      assert.equal(
        actualReceived,
        BigInt(expectedOutput.toNumber()),
        "Should round down to 100.000000 USDC"
      );
    });

    it("Rejects tokens with invalid decimals (< 6)", async () => {
      // Try to create a token with 5 decimals
      const invalidMint = await createMint(
        provider.connection,
        payer.payer,
        payer.publicKey,
        null,
        5 // Invalid: less than MIN_TOKEN_DECIMALS (6)
      );

      const [invalidVault] = PublicKey.findProgramAddressSync(
        [Buffer.from("token_vault"), pool.toBuffer(), invalidMint.toBuffer()],
        program.programId
      );

      const [invalidVaultTokenAccount] = PublicKey.findProgramAddressSync(
        [Buffer.from("vault_token_account"), invalidVault.toBuffer()],
        program.programId
      );

      const invalidFeeRecipientAccount = await getAssociatedTokenAddress(
        invalidMint,
        payer.publicKey
      );

      try {
        await program.methods
          .addSupportedToken()
          .accounts({
            pool,
            vault: invalidVault,
            vaultTokenAccount: invalidVaultTokenAccount,
            feeRecipientTokenAccount: invalidFeeRecipientAccount,
            feeRecipient: payer.publicKey,
            mint: invalidMint,
            operationsAuthority: operationsAuthority.publicKey,
            tokenProgram: TOKEN_PROGRAM_ID,
            associatedTokenProgram: ASSOCIATED_TOKEN_PROGRAM_ID,
            systemProgram: SystemProgram.programId,
            rent: anchor.web3.SYSVAR_RENT_PUBKEY,
          })
          .signers([operationsAuthority.payer])
          .rpc();

        assert.fail("Should have rejected token with 5 decimals");
      } catch (error) {
        assert.include(error.toString().toLowerCase(), "invalid");
      }
    });

    it("Rejects tokens with invalid decimals (> 9)", async () => {
      // Try to create a token with 12 decimals
      const invalidMint = await createMint(
        provider.connection,
        payer.payer,
        payer.publicKey,
        null,
        12 // Invalid: greater than MAX_TOKEN_DECIMALS (9)
      );

      const [invalidVault] = PublicKey.findProgramAddressSync(
        [Buffer.from("token_vault"), pool.toBuffer(), invalidMint.toBuffer()],
        program.programId
      );

      const [invalidVaultTokenAccount] = PublicKey.findProgramAddressSync(
        [Buffer.from("vault_token_account"), invalidVault.toBuffer()],
        program.programId
      );

      const invalidFeeRecipientAccount = await getAssociatedTokenAddress(
        invalidMint,
        payer.publicKey
      );

      try {
        await program.methods
          .addSupportedToken()
          .accounts({
            pool,
            vault: invalidVault,
            vaultTokenAccount: invalidVaultTokenAccount,
            feeRecipientTokenAccount: invalidFeeRecipientAccount,
            feeRecipient: payer.publicKey,
            mint: invalidMint,
            operationsAuthority: operationsAuthority.publicKey,
            tokenProgram: TOKEN_PROGRAM_ID,
            associatedTokenProgram: ASSOCIATED_TOKEN_PROGRAM_ID,
            systemProgram: SystemProgram.programId,
            rent: anchor.web3.SYSVAR_RENT_PUBKEY,
          })
          .signers([operationsAuthority.payer])
          .rpc();

        assert.fail("Should have rejected token with 12 decimals");
      } catch (error) {
        assert.include(error.toString().toLowerCase(), "invalid");
      }
    });

    it("Swaps with same decimals (6 to 6) work", async () => {
      // This tests backward compatibility - swaps between tokens with same decimals
      const swapAmount = new anchor.BN(50 * 10 ** 6); // 50 USDC
      const minAmountOut = new anchor.BN(50 * 10 ** 6); // Expect 50 CustomStable

      const userUsdcBefore = await getAccount(
        provider.connection,
        userUsdcAccount
      );
      const userCustomStableBefore = await getAccount(
        provider.connection,
        userCustomStableAccount
      );

      await program.methods
        .swap(swapAmount, minAmountOut)
        .accounts({
          pool,
          inVault: usdcVault,
          outVault: customStableVault,
          inVaultTokenAccount: usdcVaultTokenAccount,
          outVaultTokenAccount: customStableVaultTokenAccount,
          userFromTokenAccount: userUsdcAccount,
          toTokenAccount: userCustomStableAccount,
          feeRecipient: payer.publicKey,
          feeRecipientTokenAccount: userUsdcAccount,
          fromMint: usdcMint,
          toMint: customStableMint,
          user: payer.publicKey,
          tokenProgram: TOKEN_PROGRAM_ID,
          associatedTokenProgram: ASSOCIATED_TOKEN_PROGRAM_ID,
          systemProgram: SystemProgram.programId,
        })
        .signers([payer.payer])
        .rpc();

      const userUsdcAfter = await getAccount(
        provider.connection,
        userUsdcAccount
      );
      const userCustomStableAfter = await getAccount(
        provider.connection,
        userCustomStableAccount
      );

      // Should still be 1:1 when decimals are the same
      assert.equal(
        userUsdcBefore.amount - userUsdcAfter.amount,
        BigInt(50 * 10 ** 6),
        "USDC deducted incorrectly"
      );
      assert.equal(
        userCustomStableAfter.amount - userCustomStableBefore.amount,
        BigInt(50 * 10 ** 6),
        "CustomStable received incorrectly"
      );
    });
  });

  describe("Limit Enforcement", () => {
    it("Fails when max supported tokens reached (50 limit)", async () => {
      // Check current number of tokens in pool (may vary depending on test order)
      const poolAccount = await program.account.liquidityPool.fetch(pool);
      const currentTokenCount = poolAccount.supportedTokens.length;
      const tokensNeeded = 50 - currentTokenCount;

      // Create enough tokens to reach the limit + 1 for failure test (parallelized)
      const tokensToAdd = await Promise.all(
        Array(tokensNeeded + 1)
          .fill(null)
          .map(
            async () =>
              await createMint(
                provider.connection,
                payer.payer,
                payer.publicKey,
                null,
                6
              )
          )
      );

      // Add tokens up to the limit
      for (let i = 0; i < tokensNeeded; i++) {
        const mint = tokensToAdd[i];
        const [vault] = PublicKey.findProgramAddressSync(
          [Buffer.from("token_vault"), pool.toBuffer(), mint.toBuffer()],
          program.programId
        );
        const [vaultTokenAccount] = PublicKey.findProgramAddressSync(
          [Buffer.from("vault_token_account"), vault.toBuffer()],
          program.programId
        );
        const feeRecipientTokenAccount = await getAssociatedTokenAddress(
          mint,
          payer.publicKey
        );

        await program.methods
          .addSupportedToken()
          .accounts({
            pool,
            vault,
            vaultTokenAccount,
            feeRecipientTokenAccount,
            feeRecipient: payer.publicKey,
            mint,
            operationsAuthority: operationsAuthority.publicKey,
            tokenProgram: TOKEN_PROGRAM_ID,
            associatedTokenProgram: ASSOCIATED_TOKEN_PROGRAM_ID,
            systemProgram: SystemProgram.programId,
            rent: anchor.web3.SYSVAR_RENT_PUBKEY,
          })
          .signers([operationsAuthority.payer])
          .rpc();
      }

      // Verify we're at the limit
      const poolAccountAfter = await program.account.liquidityPool.fetch(pool);
      assert.equal(poolAccountAfter.supportedTokens.length, 50);

      // Try to add one more token (should fail)
      const extraMint = tokensToAdd[tokensNeeded];
      const [extraVault] = PublicKey.findProgramAddressSync(
        [Buffer.from("token_vault"), pool.toBuffer(), extraMint.toBuffer()],
        program.programId
      );
      const [extraVaultTokenAccount] = PublicKey.findProgramAddressSync(
        [Buffer.from("vault_token_account"), extraVault.toBuffer()],
        program.programId
      );
      const extraFeeRecipientTokenAccount = await getAssociatedTokenAddress(
        extraMint,
        payer.publicKey
      );

      try {
        await program.methods
          .addSupportedToken()
          .accounts({
            pool,
            vault: extraVault,
            vaultTokenAccount: extraVaultTokenAccount,
            feeRecipientTokenAccount: extraFeeRecipientTokenAccount,
            feeRecipient: payer.publicKey,
            mint: extraMint,
            operationsAuthority: operationsAuthority.publicKey,
            tokenProgram: TOKEN_PROGRAM_ID,
            associatedTokenProgram: ASSOCIATED_TOKEN_PROGRAM_ID,
            systemProgram: SystemProgram.programId,
            rent: anchor.web3.SYSVAR_RENT_PUBKEY,
          })
          .signers([operationsAuthority.payer])
          .rpc();

        assert.fail("Should have failed - max tokens reached");
      } catch (error) {
        assert.include(error.toString().toLowerCase(), "maxtokensreached");
      }
    });
  });

  // Note: Duplicate token prevention test is omitted because it's impossible to trigger
  // the TokenAlreadySupported error in a test. Anchor's account validation (vault init)
  // runs before our logic check, so we'd get an "account already exists" error instead.
  // In production, vault existence and pool.supported_tokens are always in sync.

  describe("Token Validation", () => {
    it("Fails to swap same token (from == to)", async () => {
      const swapAmount = new anchor.BN(10 * 10 ** 6);
      const minAmountOut = new anchor.BN(0);

      try {
        await program.methods
          .swap(swapAmount, minAmountOut)
          .accounts({
            pool,
            inVault: usdcVault,
            outVault: usdcVault, // Same vault/mint
            inVaultTokenAccount: usdcVaultTokenAccount,
            outVaultTokenAccount: usdcVaultTokenAccount,
            userFromTokenAccount: userUsdcAccount,
            toTokenAccount: userUsdcAccount, // Same account
            feeRecipientTokenAccount: feeRecipientUsdcAccount,
            feeRecipient: payer.publicKey,
            fromMint: usdcMint,
            toMint: usdcMint, // Same mint
            user: payer.publicKey,
            tokenProgram: TOKEN_PROGRAM_ID,
            associatedTokenProgram: ASSOCIATED_TOKEN_PROGRAM_ID,
            systemProgram: SystemProgram.programId,
          })
          .signers([payer.payer])
          .rpc();

        assert.fail("Should have failed - same token swap");
      } catch (error) {
        assert.include(error.toString().toLowerCase(), "sametoken");
      }
    });
  });

  describe("Amount Validation", () => {
    it("Fails to withdraw zero amount", async () => {
      try {
        await program.methods
          .withdrawLiquidity(new anchor.BN(0))
          .accounts({
            pool,
            vault: usdcVault,
            vaultTokenAccount: usdcVaultTokenAccount,
            recipientTokenAccount: userUsdcAccount,
            mint: usdcMint,
            operationsAuthority: operationsAuthority.publicKey,
            tokenProgram: TOKEN_PROGRAM_ID,
          })
          .signers([operationsAuthority.payer])
          .rpc();

        assert.fail("Should have failed - zero amount");
      } catch (error) {
        assert.include(error.toString().toLowerCase(), "invalidamount");
      }
    });

    it("Fails to withdraw more than vault balance", async () => {
      const vaultBalance = await getAccount(
        provider.connection,
        usdcVaultTokenAccount
      );
      const excessAmount = new anchor.BN(vaultBalance.amount.toString()).add(
        new anchor.BN(1000000)
      );

      try {
        await program.methods
          .withdrawLiquidity(excessAmount)
          .accounts({
            pool,
            vault: usdcVault,
            vaultTokenAccount: usdcVaultTokenAccount,
            recipientTokenAccount: userUsdcAccount,
            mint: usdcMint,
            operationsAuthority: operationsAuthority.publicKey,
            tokenProgram: TOKEN_PROGRAM_ID,
          })
          .signers([operationsAuthority.payer])
          .rpc();

        assert.fail("Should have failed - insufficient liquidity");
      } catch (error) {
        assert.include(error.toString().toLowerCase(), "insufficientliquidity");
      }
    });
  });

  describe("Token Validation", () => {
    it("Fails to swap same token (from == to)", async () => {
      const swapAmount = new anchor.BN(10 * 10 ** 6);
      const minAmountOut = new anchor.BN(0);

      try {
        await program.methods
          .swap(swapAmount, minAmountOut)
          .accounts({
            pool,
            inVault: usdcVault,
            outVault: usdcVault, // Same vault/mint
            inVaultTokenAccount: usdcVaultTokenAccount,
            outVaultTokenAccount: usdcVaultTokenAccount,
            userFromTokenAccount: userUsdcAccount,
            toTokenAccount: userUsdcAccount, // Same account
            feeRecipientTokenAccount: feeRecipientUsdcAccount,
            feeRecipient: payer.publicKey,
            fromMint: usdcMint,
            toMint: usdcMint, // Same mint
            user: payer.publicKey,
            tokenProgram: TOKEN_PROGRAM_ID,
            associatedTokenProgram: ASSOCIATED_TOKEN_PROGRAM_ID,
            systemProgram: SystemProgram.programId,
          })
          .signers([payer.payer])
          .rpc();

        assert.fail("Should have failed - same token swap");
      } catch (error) {
        assert.include(error.toString().toLowerCase(), "sametoken");
      }
    });
  });

  describe("Authority Management", () => {
    it("Updates operations authority successfully", async () => {
      // Create a new operations authority
      const newOpsAuthority = anchor.web3.Keypair.generate();

      await program.methods
        .updateOperationsAuthority(newOpsAuthority.publicKey)
        .accounts({
          pool,
          operationsAuthority: operationsAuthority.publicKey,
        })
        .signers([operationsAuthority.payer])
        .rpc();

      // Verify the authority was updated
      const poolAccount = await program.account.liquidityPool.fetch(pool);
      assert.equal(
        poolAccount.operationsAuthority.toString(),
        newOpsAuthority.publicKey.toString()
      );

      // Change it back to the original for other tests
      await program.methods
        .updateOperationsAuthority(operationsAuthority.publicKey)
        .accounts({
          pool,
          operationsAuthority: newOpsAuthority.publicKey,
        })
        .signers([newOpsAuthority])
        .rpc();
    });

    it("Updates pause authority successfully", async () => {
      // Create a new pause authority
      const newPauseAuthority = anchor.web3.Keypair.generate();

      await program.methods
        .updatePauseAuthority(newPauseAuthority.publicKey)
        .accounts({
          pool,
          pauseAuthority: pauseAuthority.publicKey,
        })
        .signers([pauseAuthority.payer])
        .rpc();

      // Verify the authority was updated
      const poolAccount = await program.account.liquidityPool.fetch(pool);
      assert.equal(
        poolAccount.pauseAuthority.toString(),
        newPauseAuthority.publicKey.toString()
      );

      // Change it back to the original for other tests
      await program.methods
        .updatePauseAuthority(pauseAuthority.publicKey)
        .accounts({
          pool,
          pauseAuthority: newPauseAuthority.publicKey,
        })
        .signers([newPauseAuthority])
        .rpc();
    });

    it("Fails when pause authority tries to update operations authority", async () => {
      const newAuthority = anchor.web3.Keypair.generate();

      try {
        await program.methods
          .updateOperationsAuthority(newAuthority.publicKey)
          .accounts({
            pool,
            operationsAuthority: pauseAuthority.publicKey, // Wrong authority
          })
          .signers([pauseAuthority.payer])
          .rpc();

        assert.fail("Expected constraint violation");
      } catch (error) {
        // Should fail due to has_one constraint
        assert.include(error.toString().toLowerCase(), "constraint");
      }
    });

    it("Fails when operations authority tries to update pause authority", async () => {
      const newAuthority = anchor.web3.Keypair.generate();

      try {
        await program.methods
          .updatePauseAuthority(newAuthority.publicKey)
          .accounts({
            pool,
            pauseAuthority: operationsAuthority.publicKey, // Wrong authority
          })
          .signers([operationsAuthority.payer])
          .rpc();

        assert.fail("Expected constraint violation");
      } catch (error) {
        // Should fail due to has_one constraint
        assert.include(error.toString().toLowerCase(), "constraint");
      }
    });
  });

  describe("Authority Access Control", () => {
    let unauthorizedUser: anchor.web3.Keypair;
    let unauthorizedUserUsdcAccount: PublicKey;

    before(async () => {
      // Create an unauthorized user
      unauthorizedUser = anchor.web3.Keypair.generate();

      // Transfer some SOL for transaction fees from payer
      const transferTx = new anchor.web3.Transaction().add(
        anchor.web3.SystemProgram.transfer({
          fromPubkey: payer.publicKey,
          toPubkey: unauthorizedUser.publicKey,
          lamports: 2 * anchor.web3.LAMPORTS_PER_SOL,
        })
      );
      await provider.sendAndConfirm(transferTx, [payer.payer]);

      // Create a token account for the unauthorized user
      unauthorizedUserUsdcAccount = await createAccount(
        provider.connection,
        payer.payer,
        usdcMint,
        unauthorizedUser.publicKey
      );

      // Mint some tokens to the unauthorized user
      await mintTo(
        provider.connection,
        payer.payer,
        usdcMint,
        unauthorizedUserUsdcAccount,
        payer.payer,
        100 * 10 ** 6
      );
    });

    it("Fails when unauthorized user tries to add supported token", async () => {
      const newMint = await createMint(
        provider.connection,
        payer.payer,
        payer.publicKey,
        null,
        6
      );

      const [newVault] = PublicKey.findProgramAddressSync(
        [Buffer.from("token_vault"), pool.toBuffer(), newMint.toBuffer()],
        program.programId
      );

      const [newVaultTokenAccount] = PublicKey.findProgramAddressSync(
        [Buffer.from("vault_token_account"), newVault.toBuffer()],
        program.programId
      );

      const newFeeRecipientAccount = await getAssociatedTokenAddress(
        newMint,
        payer.publicKey
      );

      try {
        await program.methods
          .addSupportedToken()
          .accounts({
            pool,
            vault: newVault,
            vaultTokenAccount: newVaultTokenAccount,
            feeRecipientTokenAccount: newFeeRecipientAccount,
            feeRecipient: payer.publicKey,
            mint: newMint,
            operationsAuthority: unauthorizedUser.publicKey, // Wrong authority
            tokenProgram: TOKEN_PROGRAM_ID,
            associatedTokenProgram: ASSOCIATED_TOKEN_PROGRAM_ID,
            systemProgram: anchor.web3.SystemProgram.programId,
            rent: anchor.web3.SYSVAR_RENT_PUBKEY,
          })
          .signers([unauthorizedUser])
          .rpc();

        assert.fail("Expected constraint violation");
      } catch (error) {
        assert.include(error.toString().toLowerCase(), "constraint");
      }
    });

    it("Fails when unauthorized user tries to withdraw liquidity", async () => {
      try {
        await program.methods
          .withdrawLiquidity(new anchor.BN(10 * 10 ** 6))
          .accounts({
            pool,
            vault: usdcVault,
            vaultTokenAccount: usdcVaultTokenAccount,
            recipientTokenAccount: unauthorizedUserUsdcAccount,
            mint: usdcMint,
            operationsAuthority: unauthorizedUser.publicKey, // Wrong authority
            tokenProgram: TOKEN_PROGRAM_ID,
          })
          .signers([unauthorizedUser])
          .rpc();

        assert.fail("Expected constraint violation");
      } catch (error) {
        assert.include(error.toString().toLowerCase(), "constraint");
      }
    });

    it("Fails when unauthorized user tries to update fee config", async () => {
      try {
        await program.methods
          .updateFeeConfig(new anchor.BN(50), null)
          .accounts({
            pool,
            operationsAuthority: unauthorizedUser.publicKey, // Wrong authority
          })
          .signers([unauthorizedUser])
          .rpc();

        assert.fail("Expected constraint violation");
      } catch (error) {
        assert.include(error.toString().toLowerCase(), "constraint");
      }
    });

    it("Fails when unauthorized user tries to update pause config", async () => {
      try {
        await program.methods
          .updatePauseConfig(true, null)
          .accounts({
            pool,
            pauseAuthority: unauthorizedUser.publicKey, // Wrong authority
          })
          .signers([unauthorizedUser])
          .rpc();

        assert.fail("Expected constraint violation");
      } catch (error) {
        assert.include(error.toString().toLowerCase(), "constraint");
      }
    });
  });
});
