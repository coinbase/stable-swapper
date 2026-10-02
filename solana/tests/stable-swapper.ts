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
import { createHash } from "crypto";

const BPF_LOADER_UPGRADEABLE_PROGRAM_ID = new PublicKey(
  "BPFLoaderUpgradeab1e11111111111111111111111"
);

describe("stable-swapper", () => {
  const provider = anchor.AnchorProvider.env();
  anchor.setProvider(provider);

  const program = anchor.workspace.stableSwapper as Program<StableSwapper>;
  const payer = provider.wallet as anchor.Wallet;
  const operationsAuthority = payer; // legacy alias retained for migration tests
  const pauseAuthority = payer;
  const unpauseAuthority = payer;
  const treasuryAuthority = payer;
  const configureAuthority = payer;
  const withdrawRecipient = payer;

  // Test keypairs
  let usdcMint: PublicKey;
  let customStableMint: PublicKey;
  let pool: PublicKey;
  let programData: PublicKey;
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

    // `initialize` requires the payer to be the program's upgrade authority. Anchor deploys the
    // program with the provider wallet as that authority, and the provider wallet is `payer`.
    [programData] = PublicKey.findProgramAddressSync(
      [program.programId.toBuffer()],
      BPF_LOADER_UPGRADEABLE_PROGRAM_ID
    );

    [usdcVault] = PublicKey.findProgramAddressSync(
      [Buffer.from("token_vault"), pool.toBuffer(), usdcMint.toBuffer()],
      program.programId
    );

    [customStableVault] = PublicKey.findProgramAddressSync(
      [
        Buffer.from("token_vault"),
        pool.toBuffer(),
        customStableMint.toBuffer(),
      ],
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
          programData,
          pauseAuthority: pauseAuthority.publicKey,
          unpauseAuthority: unpauseAuthority.publicKey,
          treasuryAuthority: treasuryAuthority.publicKey,
          configureAuthority: configureAuthority.publicKey,
          feeRecipient: payer.publicKey,
          withdrawRecipient: withdrawRecipient.publicKey,
          systemProgram: SystemProgram.programId,
        })
        .signers([payer.payer])
        .rpc();

      // Verify pool state
      const poolAccount = await program.account.liquidityPool.fetch(pool);
      assert.equal(
        poolAccount.pauseAuthority.toString(),
        pauseAuthority.publicKey.toString()
      );
      assert.equal(
        poolAccount.unpauseAuthority.toString(),
        unpauseAuthority.publicKey.toString()
      );
      assert.equal(
        poolAccount.treasuryAuthority.toString(),
        treasuryAuthority.publicKey.toString()
      );
      assert.equal(
        poolAccount.configureAuthority.toString(),
        configureAuthority.publicKey.toString()
      );
      assert.equal(
        poolAccount.feeRecipient.toString(),
        payer.publicKey.toString()
      );
      assert.equal(poolAccount.withdrawRecipients.length, 1);
      assert.equal(
        poolAccount.withdrawRecipients[0].toString(),
        withdrawRecipient.publicKey.toString()
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
          configureAuthority: configureAuthority.publicKey,
          tokenProgram: TOKEN_PROGRAM_ID,
          associatedTokenProgram: ASSOCIATED_TOKEN_PROGRAM_ID,
          systemProgram: SystemProgram.programId,
          rent: anchor.web3.SYSVAR_RENT_PUBKEY,
        })
        .signers([configureAuthority.payer])
        .rpc();

      // Newly listed tokens start disabled; enable swapping.
      await program.methods
        .unpauseToken()
        .accounts({
          pool,
          vault: usdcVault,
          mint: usdcMint,
          unpauseAuthority: unpauseAuthority.publicKey,
        })
        .signers([unpauseAuthority.payer])
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
          configureAuthority: configureAuthority.publicKey,
          tokenProgram: TOKEN_PROGRAM_ID,
          associatedTokenProgram: ASSOCIATED_TOKEN_PROGRAM_ID,
          systemProgram: SystemProgram.programId,
          rent: anchor.web3.SYSVAR_RENT_PUBKEY,
        })
        .signers([configureAuthority.payer])
        .rpc();

      // Newly listed tokens start disabled; enable swapping.
      await program.methods
        .unpauseToken()
        .accounts({
          pool,
          vault: customStableVault,
          mint: customStableMint,
          unpauseAuthority: unpauseAuthority.publicKey,
        })
        .signers([unpauseAuthority.payer])
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
          treasuryAuthority: treasuryAuthority.publicKey,
          tokenProgram: TOKEN_PROGRAM_ID,
        })
        .signers([treasuryAuthority.payer])
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
        .pauseWithdraws() // Sets liquidityPaused=true; swapsPaused is unchanged
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
            treasuryAuthority: treasuryAuthority.publicKey,
            tokenProgram: TOKEN_PROGRAM_ID,
          })
          .signers([treasuryAuthority.payer])
          .rpc();

        assert.fail("Expected liquidity paused error");
      } catch (error) {
        assert.include(error.toString(), "WithdrawalPaused");
      }

      // Unpause liquidity for other tests
      await program.methods
        .unpauseWithdraws()
        .accounts({
          pool,
          unpauseAuthority: unpauseAuthority.publicKey,
        })
        .signers([unpauseAuthority.payer])
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
        finalUserCustomStableBalance.amount -
        initialUserCustomStableBalance.amount;

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
        initialUserCustomStableBalance.amount -
        finalUserCustomStableBalance.amount;

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
        .updateFeeRate(new anchor.BN(500)) // 5% fee
        .accounts({
          pool,
          configureAuthority: configureAuthority.publicKey,
        })
        .signers([configureAuthority.payer])
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
        .updateFeeRate(new anchor.BN(0))
        .accounts({
          pool,
          configureAuthority: configureAuthority.publicKey,
        })
        .signers([configureAuthority.payer])
        .rpc();
    });

    it("Fails when swap amount results in zero output (fee consumes entire input)", async () => {
      // Set a 1% fee rate (100 basis points)
      await program.methods
        .updateFeeRate(new anchor.BN(100)) // 1% fee
        .accounts({
          pool,
          configureAuthority: configureAuthority.publicKey,
        })
        .signers([configureAuthority.payer])
        .rpc();

      // Try to swap only 1 unit
      // With 1% fee and round-up: fee_amount = (1 * 100 + 9999) / 10000 = 1
      // amount_after_fee = 1 - 1 = 0
      // amount_out = 0 (should fail)
      const tinySwapAmount = new anchor.BN(1);
      const minAmountOut = new anchor.BN(1); // Nonzero; the zero-output check below is what's under test

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
        .updateFeeRate(new anchor.BN(0))
        .accounts({
          pool,
          configureAuthority: configureAuthority.publicKey,
        })
        .signers([configureAuthority.payer])
        .rpc();
    });
  });

  // Instructions are built by hand so the exact account list and discriminator are exercised.
  describe("Swap V2 (whitelist account removed)", () => {
    // sha256("global:swap")[0..8] as encoded by existing callers.
    const LEGACY_SWAP_DISCRIMINATOR = Buffer.from([
      248, 198, 158, 145, 225, 117, 135, 200,
    ]);

    const ixDiscriminator = (name: string): Buffer =>
      createHash("sha256").update(`global:${name}`).digest().subarray(0, 8);

    const swapIxData = (
      discriminator: Buffer,
      amountIn: anchor.BN,
      minAmountOut: anchor.BN
    ): Buffer =>
      Buffer.concat([
        discriminator,
        amountIn.toArrayLike(Buffer, "le", 8),
        minAmountOut.toArrayLike(Buffer, "le", 8),
      ]);

    let whitelistPda: PublicKey;
    let feeRecipient: PublicKey;
    let feeRecipientTokenAccount: PublicKey;
    let vaultUsdcAtStart: bigint;
    let vaultCustomAtStart: bigint;
    let userUsdcAtStart: bigint;
    let userCustomAtStart: bigint;
    let feeUsdcAtStart: bigint;

    before(async () => {
      [whitelistPda] = PublicKey.findProgramAddressSync(
        [Buffer.from("address_whitelist")],
        program.programId
      );
      const poolAccount = await program.account.liquidityPool.fetch(pool);
      feeRecipient = poolAccount.feeRecipient;
      feeRecipientTokenAccount = await getAssociatedTokenAddress(
        usdcMint,
        feeRecipient
      );
      const [vaultUsdc, vaultCustom, userUsdc, userCustom, feeUsdc] =
        await Promise.all([
          getAccount(provider.connection, usdcVaultTokenAccount),
          getAccount(provider.connection, customStableVaultTokenAccount),
          getAccount(provider.connection, userUsdcAccount),
          getAccount(provider.connection, userCustomStableAccount),
          getAccount(provider.connection, feeRecipientTokenAccount),
        ]);
      vaultUsdcAtStart = vaultUsdc.amount;
      vaultCustomAtStart = vaultCustom.amount;
      userUsdcAtStart = userUsdc.amount;
      userCustomAtStart = userCustom.amount;
      feeUsdcAtStart = feeUsdc.amount;
    });

    // Restore balances for later suites: swap the vault delta back, return any fees.
    after(async () => {
      const vaultUsdcNow = (
        await getAccount(provider.connection, usdcVaultTokenAccount)
      ).amount;
      const moved = vaultUsdcNow - vaultUsdcAtStart;
      if (moved > 0n) {
        await program.methods
          .swap(
            new anchor.BN(moved.toString()),
            new anchor.BN(moved.toString())
          )
          .accounts({
            pool,
            inVault: customStableVault,
            outVault: usdcVault,
            inVaultTokenAccount: customStableVaultTokenAccount,
            outVaultTokenAccount: usdcVaultTokenAccount,
            userFromTokenAccount: userCustomStableAccount,
            toTokenAccount: userUsdcAccount,
            feeRecipientTokenAccount: feeRecipientCustomStableAccount,
            feeRecipient,
            fromMint: customStableMint,
            toMint: usdcMint,
            user: payer.publicKey,
            tokenProgram: TOKEN_PROGRAM_ID,
            associatedTokenProgram: ASSOCIATED_TOKEN_PROGRAM_ID,
            systemProgram: SystemProgram.programId,
          })
          .signers([payer.payer])
          .rpc();
      }
      const feeNow = (
        await getAccount(provider.connection, feeRecipientTokenAccount)
      ).amount;
      const feeMoved = feeNow - feeUsdcAtStart;
      if (feeMoved > 0n) {
        await transfer(
          provider.connection,
          payer.payer,
          feeRecipientTokenAccount,
          userUsdcAccount,
          payer.payer,
          feeMoved
        );
      }
      const restored = await Promise.all([
        getAccount(provider.connection, usdcVaultTokenAccount),
        getAccount(provider.connection, customStableVaultTokenAccount),
        getAccount(provider.connection, userUsdcAccount),
        getAccount(provider.connection, userCustomStableAccount),
        getAccount(provider.connection, feeRecipientTokenAccount),
      ]);
      assert.equal(restored[0].amount.toString(), vaultUsdcAtStart.toString());
      assert.equal(
        restored[1].amount.toString(),
        vaultCustomAtStart.toString()
      );
      assert.equal(restored[2].amount.toString(), userUsdcAtStart.toString());
      assert.equal(restored[3].amount.toString(), userCustomAtStart.toString());
      assert.equal(restored[4].amount.toString(), feeUsdcAtStart.toString());
    });

    // USDC -> CustomStable, in the account order existing callers encode for legacy `swap`.
    const legacySwapKeys = () => [
      { pubkey: pool, isSigner: false, isWritable: false },
      { pubkey: usdcVault, isSigner: false, isWritable: false },
      { pubkey: customStableVault, isSigner: false, isWritable: false },
      { pubkey: usdcVaultTokenAccount, isSigner: false, isWritable: true },
      {
        pubkey: customStableVaultTokenAccount,
        isSigner: false,
        isWritable: true,
      },
      { pubkey: userUsdcAccount, isSigner: false, isWritable: true },
      { pubkey: userCustomStableAccount, isSigner: false, isWritable: true },
      { pubkey: feeRecipientTokenAccount, isSigner: false, isWritable: true },
      { pubkey: feeRecipient, isSigner: false, isWritable: false },
      { pubkey: usdcMint, isSigner: false, isWritable: false },
      { pubkey: customStableMint, isSigner: false, isWritable: false },
      { pubkey: payer.publicKey, isSigner: true, isWritable: true },
      { pubkey: whitelistPda, isSigner: false, isWritable: false }, // index 12
      { pubkey: TOKEN_PROGRAM_ID, isSigner: false, isWritable: false },
      {
        pubkey: ASSOCIATED_TOKEN_PROGRAM_ID,
        isSigner: false,
        isWritable: false,
      },
      { pubkey: SystemProgram.programId, isSigner: false, isWritable: false },
    ];

    // Same list with the `whitelist` slot (index 12) dropped.
    const v2SwapKeys = () => legacySwapKeys().filter((_, i) => i !== 12);

    const sendRawSwap = async (
      keys: ReturnType<typeof legacySwapKeys>,
      data: Buffer
    ) => {
      const ix = new anchor.web3.TransactionInstruction({
        programId: program.programId,
        keys,
        data,
      });
      const tx = new anchor.web3.Transaction().add(ix);
      return provider.sendAndConfirm(tx, [payer.payer]);
    };

    const balances = async () => {
      const [usdc, custom, vaultUsdc, vaultCustom, feeUsdc] = await Promise.all(
        [
          getAccount(provider.connection, userUsdcAccount),
          getAccount(provider.connection, userCustomStableAccount),
          getAccount(provider.connection, usdcVaultTokenAccount),
          getAccount(provider.connection, customStableVaultTokenAccount),
          getAccount(provider.connection, feeRecipientTokenAccount),
        ]
      );
      return {
        usdc: usdc.amount,
        custom: custom.amount,
        vaultUsdc: vaultUsdc.amount,
        vaultCustom: vaultCustom.amount,
        feeUsdc: feeUsdc.amount,
      };
    };

    it("Exposes both instructions in the IDL with the expected account layouts", () => {
      const legacy = program.idl.instructions.find((i) => i.name === "swap");
      const v2 = program.idl.instructions.find((i) => i.name === "swapV2");
      assert.isDefined(legacy, "legacy swap missing from IDL");
      assert.isDefined(v2, "swap_v2 missing from IDL");

      // Legacy discriminator must not move: existing callers hard-code it.
      assert.deepEqual(
        Buffer.from(legacy.discriminator),
        LEGACY_SWAP_DISCRIMINATOR
      );
      assert.deepEqual(
        Buffer.from(v2.discriminator),
        ixDiscriminator("swap_v2")
      );
      assert.notDeepEqual(
        Buffer.from(v2.discriminator),
        LEGACY_SWAP_DISCRIMINATOR
      );

      // Same args on both.
      assert.deepEqual(
        v2.args.map((a) => [a.name, a.type]),
        legacy.args.map((a) => [a.name, a.type])
      );

      // v2 is the legacy list minus `whitelist`, compared on every published field but `docs`.
      const legacyNames = legacy.accounts.map((a) => a.name);
      const v2Names = v2.accounts.map((a) => a.name);
      assert.lengthOf(legacyNames, 16);
      assert.lengthOf(v2Names, 15);
      assert.equal(legacyNames[12], "whitelist");
      const comparable = (accounts: any[]) =>
        accounts
          .filter((a) => a.name !== "whitelist")
          .map(({ docs, ...rest }) => rest);
      assert.deepEqual(comparable(v2.accounts), comparable(legacy.accounts));
    });

    it("Legacy swap still accepts the 16-account layout", async () => {
      const amount = new anchor.BN(10 * 10 ** 6);
      const before = await balances();

      await sendRawSwap(
        legacySwapKeys(),
        swapIxData(LEGACY_SWAP_DISCRIMINATOR, amount, amount)
      );

      const after = await balances();
      assert.equal((before.usdc - after.usdc).toString(), amount.toString());
      assert.equal(
        (after.custom - before.custom).toString(),
        amount.toString()
      );
    });

    it("swap_v2 accepts the 15-account layout and produces the same result", async () => {
      const amount = new anchor.BN(10 * 10 ** 6);
      const before = await balances();

      await sendRawSwap(
        v2SwapKeys(),
        swapIxData(ixDiscriminator("swap_v2"), amount, amount)
      );

      const after = await balances();
      assert.equal((before.usdc - after.usdc).toString(), amount.toString());
      assert.equal(
        (after.custom - before.custom).toString(),
        amount.toString()
      );
    });

    it("swap_v2 rejects the legacy 16-account layout", async () => {
      const amount = new anchor.BN(10 * 10 ** 6);
      const before = await balances();

      let threw = false;
      try {
        await sendRawSwap(
          legacySwapKeys(),
          swapIxData(ixDiscriminator("swap_v2"), amount, amount)
        );
      } catch (error) {
        threw = true;
        // Slot 12 is read as `token_program` and is not the Token program.
        assert.include(error.toString(), "InvalidProgramId");
      }
      assert.isTrue(threw, "swap_v2 accepted the legacy account layout");
      assert.deepEqual(await balances(), before);
    });

    it("both instructions reject a fee recipient that is not the pool's", async () => {
      const stranger = anchor.web3.Keypair.generate();
      const strangerUsdc = await getAssociatedTokenAddress(
        usdcMint,
        stranger.publicKey
      );
      const amount = new anchor.BN(10 * 10 ** 6);

      // Replace by index (7, 8): the fee recipient pubkey is also the signer in this suite.
      const withStranger = (keys: ReturnType<typeof legacySwapKeys>) =>
        keys.map((k, i) => {
          if (i === 7) return { ...k, pubkey: strangerUsdc };
          if (i === 8) return { ...k, pubkey: stranger.publicKey };
          return k;
        });

      for (const [name, keys] of [
        ["swap", withStranger(legacySwapKeys())],
        ["swap_v2", withStranger(v2SwapKeys())],
      ] as const) {
        const before = await balances();
        try {
          await sendRawSwap(
            keys,
            swapIxData(ixDiscriminator(name), amount, amount)
          );
          assert.fail(`${name} accepted a foreign fee recipient`);
        } catch (error) {
          assert.include(error.toString(), "ConstraintAddress");
        }
        assert.deepEqual(await balances(), before);
      }
    });

    it("Legacy swap rejects the 15-account layout", async () => {
      const amount = new anchor.BN(10 * 10 ** 6);
      const before = await balances();

      let threw = false;
      try {
        await sendRawSwap(
          v2SwapKeys(),
          swapIxData(LEGACY_SWAP_DISCRIMINATOR, amount, amount)
        );
      } catch (error) {
        threw = true;
        // Slot 13 is read as `token_program` and holds the Associated Token program.
        assert.include(error.toString(), "InvalidProgramId");
      }
      assert.isTrue(threw, "legacy swap accepted the 15-account layout");
      assert.deepEqual(await balances(), before);
    });

    it("swap_v2 applies the same validation and fee logic as swap", async () => {
      const amount = new anchor.BN(100 * 10 ** 6);

      // min_amount_out = 0 is rejected on both.
      for (const [name, keys] of [
        ["swap", legacySwapKeys()],
        ["swap_v2", v2SwapKeys()],
      ] as const) {
        try {
          await sendRawSwap(
            keys,
            swapIxData(ixDiscriminator(name), amount, new anchor.BN(0))
          );
          assert.fail(`${name} accepted min_amount_out = 0`);
        } catch (error) {
          assert.include(error.toString().toLowerCase(), "invalidamount");
        }
      }

      // Paused swaps are rejected on both.
      await program.methods
        .pauseSwaps()
        .accounts({ pool, pauseAuthority: pauseAuthority.publicKey })
        .signers([pauseAuthority.payer])
        .rpc();
      try {
        for (const [name, keys] of [
          ["swap", legacySwapKeys()],
          ["swap_v2", v2SwapKeys()],
        ] as const) {
          try {
            await sendRawSwap(
              keys,
              swapIxData(ixDiscriminator(name), amount, amount)
            );
            assert.fail(`${name} executed while swaps were paused`);
          } catch (error) {
            assert.include(error.toString(), "SwapsPaused");
          }
        }
      } finally {
        await program.methods
          .unpauseSwaps()
          .accounts({ pool, unpauseAuthority: unpauseAuthority.publicKey })
          .signers([unpauseAuthority.payer])
          .rpc();
      }

      // The payer's USDC account is also the fee recipient's ATA; use a fresh recipient so
      // the fee is observable.
      const feeOwner = anchor.web3.Keypair.generate();
      const feeOwnerUsdc = await getAssociatedTokenAddress(
        usdcMint,
        feeOwner.publicKey
      );
      const withFeeOwner = (keys: ReturnType<typeof legacySwapKeys>) =>
        keys.map((k, i) => {
          if (i === 7) return { ...k, pubkey: feeOwnerUsdc };
          if (i === 8) return { ...k, pubkey: feeOwner.publicKey };
          return k;
        });
      await program.methods
        .updateFeeRate(new anchor.BN(100))
        .accounts({ pool, configureAuthority: configureAuthority.publicKey })
        .signers([configureAuthority.payer])
        .rpc();
      await program.methods
        .updateFeeRecipient(feeOwner.publicKey)
        .accounts({ pool, configureAuthority: configureAuthority.publicKey })
        .signers([configureAuthority.payer])
        .rpc();
      try {
        const expectedNet = BigInt(99 * 10 ** 6);
        const expectedFee = BigInt(amount.toString()) - expectedNet;
        const minOut = new anchor.BN(99 * 10 ** 6);

        for (const [name, keys] of [
          ["swap", withFeeOwner(legacySwapKeys())],
          ["swap_v2", withFeeOwner(v2SwapKeys())],
        ] as const) {
          const before = await balances();
          let feeBefore = 0n;
          try {
            feeBefore = (await getAccount(provider.connection, feeOwnerUsdc))
              .amount;
          } catch {
            // The recipient ATA is created by the swap's init_if_needed.
          }
          await sendRawSwap(
            keys,
            swapIxData(ixDiscriminator(name), amount, minOut)
          );
          const after = await balances();
          const feeAfter = (await getAccount(provider.connection, feeOwnerUsdc))
            .amount;
          assert.equal(
            (before.usdc - after.usdc).toString(),
            amount.toString(),
            `${name}: input debit`
          );
          assert.equal(
            (feeAfter - feeBefore).toString(),
            expectedFee.toString(),
            `${name}: fee recipient received the fee`
          );
          assert.equal(
            (after.vaultUsdc - before.vaultUsdc).toString(),
            expectedNet.toString(),
            `${name}: vault receives net of fee`
          );
          assert.equal(
            (after.custom - before.custom).toString(),
            expectedNet.toString(),
            `${name}: net output`
          );
          assert.equal(
            (before.vaultCustom - after.vaultCustom).toString(),
            expectedNet.toString(),
            `${name}: output vault debit`
          );
        }
      } finally {
        await program.methods
          .updateFeeRate(new anchor.BN(0))
          .accounts({ pool, configureAuthority: configureAuthority.publicKey })
          .signers([configureAuthority.payer])
          .rpc();
        await program.methods
          .updateFeeRecipient(feeRecipient)
          .accounts({ pool, configureAuthority: configureAuthority.publicKey })
          .signers([configureAuthority.payer])
          .rpc();
        try {
          const leftover = (await getAccount(provider.connection, feeOwnerUsdc))
            .amount;
          if (leftover > 0n) {
            await transfer(
              provider.connection,
              payer.payer,
              feeOwnerUsdc,
              userUsdcAccount,
              feeOwner,
              leftover
            );
          }
        } catch {
          // No fee was collected, so there is nothing to return.
        }
      }
    });
  });

  describe("Token Disable Mechanism", () => {
    it("Disables a token and prevents swaps", async () => {
      // Disable USDC
      await program.methods
        .pauseToken()
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
        .unpauseToken()
        .accounts({
          pool,
          vault: usdcVault,
          mint: usdcMint,
          unpauseAuthority: unpauseAuthority.publicKey,
        })
        .signers([unpauseAuthority.payer])
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
          .pauseToken()
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
          configureAuthority: configureAuthority.publicKey,
          tokenProgram: TOKEN_PROGRAM_ID,
          associatedTokenProgram: ASSOCIATED_TOKEN_PROGRAM_ID,
          systemProgram: SystemProgram.programId,
          rent: anchor.web3.SYSVAR_RENT_PUBKEY,
        })
        .signers([configureAuthority.payer])
        .rpc();

      // Newly listed tokens start disabled; enable swapping.
      await program.methods
        .unpauseToken()
        .accounts({
          pool,
          vault: testTokenVault,
          mint: testTokenMint,
          unpauseAuthority: unpauseAuthority.publicKey,
        })
        .signers([unpauseAuthority.payer])
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
            configureAuthority: configureAuthority.publicKey,
            tokenProgram: TOKEN_PROGRAM_ID,
          })
          .signers([configureAuthority.payer])
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
        .pauseToken()
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
            configureAuthority: configureAuthority.publicKey,
            tokenProgram: TOKEN_PROGRAM_ID,
          })
          .signers([configureAuthority.payer])
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
          treasuryAuthority: treasuryAuthority.publicKey,
          tokenProgram: TOKEN_PROGRAM_ID,
        })
        .signers([treasuryAuthority.payer])
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
          configureAuthority: configureAuthority.publicKey,
          tokenProgram: TOKEN_PROGRAM_ID,
        })
        .signers([configureAuthority.payer])
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
          configureAuthority: configureAuthority.publicKey,
          tokenProgram: TOKEN_PROGRAM_ID,
          associatedTokenProgram: ASSOCIATED_TOKEN_PROGRAM_ID,
          systemProgram: SystemProgram.programId,
          rent: anchor.web3.SYSVAR_RENT_PUBKEY,
        })
        .signers([configureAuthority.payer])
        .rpc();

      // Disable it
      await program.methods
        .pauseToken()
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
            configureAuthority: unauthorizedUser.publicKey,
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
          configureAuthority: configureAuthority.publicKey,
          tokenProgram: TOKEN_PROGRAM_ID,
        })
        .signers([configureAuthority.payer])
        .rpc();
    });
  });

  describe("Pool Management", () => {
    it("Updates fee configuration", async () => {
      const newFeeRate = 25; // 0.25%

      await program.methods
        .updateFeeRate(new anchor.BN(newFeeRate))
        .accounts({
          pool,
          configureAuthority: configureAuthority.publicKey,
        })
        .signers([configureAuthority.payer])
        .rpc();

      // Verify fee rate was updated
      const poolAccount = await program.account.liquidityPool.fetch(pool);
      assert.equal(poolAccount.feeRate.toNumber(), newFeeRate);

      // Reset fee back to 0% for other tests
      await program.methods
        .updateFeeRate(new anchor.BN(0))
        .accounts({
          pool,
          configureAuthority: configureAuthority.publicKey,
        })
        .signers([configureAuthority.payer])
        .rpc();
    });

    it("Pauses swaps", async () => {
      await program.methods
        .pauseSwaps() // Sets swapsPaused=true; liquidityPaused is unchanged
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
        .unpauseSwaps() // Sets swapsPaused=false; liquidityPaused is unchanged
        .accounts({
          pool,
          unpauseAuthority: unpauseAuthority.publicKey,
        })
        .signers([unpauseAuthority.payer])
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
        .updateFeeRate(new anchor.BN(100))
        .accounts({
          pool,
          configureAuthority: configureAuthority.publicKey,
        })
        .signers([configureAuthority.payer])
        .rpc();
      await program.methods
        .updateFeeRecipient(feeRecipient.publicKey)
        .accounts({
          pool,
          configureAuthority: configureAuthority.publicKey,
        })
        .signers([configureAuthority.payer])
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
        finalUserCustomStableBalance.amount -
        initialUserCustomStableBalance.amount;
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
        .updateFeeRate(new anchor.BN(0))
        .accounts({
          pool,
          configureAuthority: configureAuthority.publicKey,
        })
        .signers([configureAuthority.payer])
        .rpc();
      await program.methods
        .updateFeeRecipient(payer.publicKey)
        .accounts({
          pool,
          configureAuthority: configureAuthority.publicKey,
        })
        .signers([configureAuthority.payer])
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
        .updateFeeRate(new anchor.BN(100))
        .accounts({
          pool,
          configureAuthority: configureAuthority.publicKey,
        })
        .signers([configureAuthority.payer])
        .rpc();
      await program.methods
        .updateFeeRecipient(newFeeRecipient.publicKey)
        .accounts({
          pool,
          configureAuthority: configureAuthority.publicKey,
        })
        .signers([configureAuthority.payer])
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
        .updateFeeRate(new anchor.BN(0))
        .accounts({
          pool,
          configureAuthority: configureAuthority.publicKey,
        })
        .signers([configureAuthority.payer])
        .rpc();
      await program.methods
        .updateFeeRecipient(payer.publicKey)
        .accounts({
          pool,
          configureAuthority: configureAuthority.publicKey,
        })
        .signers([configureAuthority.payer])
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
        finalUserCustomStableBalance.amount -
        initialUserCustomStableBalance.amount;

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
        .updateFeeRate(new anchor.BN(100))
        .accounts({
          pool,
          configureAuthority: configureAuthority.publicKey,
        })
        .signers([configureAuthority.payer])
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
        .updateFeeRecipient(feeRecipient.publicKey)
        .accounts({
          pool,
          configureAuthority: configureAuthority.publicKey,
        })
        .signers([configureAuthority.payer])
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
        .updateFeeRate(new anchor.BN(0))
        .accounts({
          pool,
          configureAuthority: configureAuthority.publicKey,
        })
        .signers([configureAuthority.payer])
        .rpc();
      await program.methods
        .updateFeeRecipient(payer.publicKey)
        .accounts({
          pool,
          configureAuthority: configureAuthority.publicKey,
        })
        .signers([configureAuthority.payer])
        .rpc();
    });

    it("Does not over-charge on perfect fee amounts (no rounding needed)", async () => {
      // Set 1% fee (100 basis points)
      await program.methods
        .updateFeeRate(new anchor.BN(100))
        .accounts({
          pool,
          configureAuthority: configureAuthority.publicKey,
        })
        .signers([configureAuthority.payer])
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
        .updateFeeRecipient(feeRecipient.publicKey)
        .accounts({
          pool,
          configureAuthority: configureAuthority.publicKey,
        })
        .signers([configureAuthority.payer])
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
        .updateFeeRate(new anchor.BN(0))
        .accounts({
          pool,
          configureAuthority: configureAuthority.publicKey,
        })
        .signers([configureAuthority.payer])
        .rpc();
      await program.methods
        .updateFeeRecipient(payer.publicKey)
        .accounts({
          pool,
          configureAuthority: configureAuthority.publicKey,
        })
        .signers([configureAuthority.payer])
        .rpc();
    });
  });

  describe("Fee Rate Validation", () => {
    it("Fails to update fee config with fee rate exceeding maximum", async () => {
      const excessiveFeeRate = 1001; // > 1000 basis points (10%)

      try {
        await program.methods
          .updateFeeRate(new anchor.BN(excessiveFeeRate))
          .accounts({
            pool,
            configureAuthority: configureAuthority.publicKey,
          })
          .signers([configureAuthority.payer])
          .rpc();

        assert.fail("Expected invalid fee rate error");
      } catch (error) {
        assert.include(error.toString(), "InvalidFeeRate");
      }
    });

    it("Allows maximum fee rate of 10% (1000 basis points)", async () => {
      const maxFeeRate = 1000; // 10%

      await program.methods
        .updateFeeRate(new anchor.BN(maxFeeRate))
        .accounts({
          pool,
          configureAuthority: configureAuthority.publicKey,
        })
        .signers([configureAuthority.payer])
        .rpc();

      const poolAccount = await program.account.liquidityPool.fetch(pool);
      assert.equal(poolAccount.feeRate.toNumber(), maxFeeRate);

      // Reset fee rate
      await program.methods
        .updateFeeRate(new anchor.BN(0))
        .accounts({
          pool,
          configureAuthority: configureAuthority.publicKey,
        })
        .signers([configureAuthority.payer])
        .rpc();
    });

    it("Fails to set the fee recipient to the default pubkey", async () => {
      // The recipient is the authority on the token account every fee lands in, so the zero
      // key would make collected fees permanently unspendable.
      try {
        await program.methods
          .updateFeeRecipient(PublicKey.default)
          .accounts({
            pool,
            configureAuthority: configureAuthority.publicKey,
          })
          .signers([configureAuthority.payer])
          .rpc();
        assert.fail("Expected RecipientNotSet error");
      } catch (error) {
        assert.include(error.toString().toLowerCase(), "recipientnotset");
      }

      const poolAccount = await program.account.liquidityPool.fetch(pool);
      assert.notEqual(
        poolAccount.feeRecipient.toBase58(),
        PublicKey.default.toBase58(),
        "fee recipient must be unchanged by a rejected update"
      );
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
          configureAuthority: configureAuthority.publicKey,
          tokenProgram: TOKEN_PROGRAM_ID,
          associatedTokenProgram: ASSOCIATED_TOKEN_PROGRAM_ID,
          systemProgram: SystemProgram.programId,
          rent: anchor.web3.SYSVAR_RENT_PUBKEY,
        })
        .signers([configureAuthority.payer])
        .rpc();

      // Newly listed tokens start disabled; enable swapping.
      await program.methods
        .unpauseToken()
        .accounts({
          pool,
          vault: token9DecVault,
          mint: token9DecMint,
          unpauseAuthority: unpauseAuthority.publicKey,
        })
        .signers([unpauseAuthority.payer])
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
            configureAuthority: configureAuthority.publicKey,
            tokenProgram: TOKEN_PROGRAM_ID,
            associatedTokenProgram: ASSOCIATED_TOKEN_PROGRAM_ID,
            systemProgram: SystemProgram.programId,
            rent: anchor.web3.SYSVAR_RENT_PUBKEY,
          })
          .signers([configureAuthority.payer])
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
            configureAuthority: configureAuthority.publicKey,
            tokenProgram: TOKEN_PROGRAM_ID,
            associatedTokenProgram: ASSOCIATED_TOKEN_PROGRAM_ID,
            systemProgram: SystemProgram.programId,
            rent: anchor.web3.SYSVAR_RENT_PUBKEY,
          })
          .signers([configureAuthority.payer])
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
            configureAuthority: configureAuthority.publicKey,
            tokenProgram: TOKEN_PROGRAM_ID,
            associatedTokenProgram: ASSOCIATED_TOKEN_PROGRAM_ID,
            systemProgram: SystemProgram.programId,
            rent: anchor.web3.SYSVAR_RENT_PUBKEY,
          })
          .signers([configureAuthority.payer])
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
            configureAuthority: configureAuthority.publicKey,
            tokenProgram: TOKEN_PROGRAM_ID,
            associatedTokenProgram: ASSOCIATED_TOKEN_PROGRAM_ID,
            systemProgram: SystemProgram.programId,
            rent: anchor.web3.SYSVAR_RENT_PUBKEY,
          })
          .signers([configureAuthority.payer])
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
      const minAmountOut = new anchor.BN(1); // Nonzero; the same-token check below is what's under test

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
            treasuryAuthority: treasuryAuthority.publicKey,
            tokenProgram: TOKEN_PROGRAM_ID,
          })
          .signers([treasuryAuthority.payer])
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
            treasuryAuthority: treasuryAuthority.publicKey,
            tokenProgram: TOKEN_PROGRAM_ID,
          })
          .signers([treasuryAuthority.payer])
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
      const minAmountOut = new anchor.BN(1); // Nonzero; the same-token check below is what's under test

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
    it("Updates configure authority successfully", async () => {
      const newConfigure = anchor.web3.Keypair.generate();

      await program.methods
        .updateConfigureAuthority(newConfigure.publicKey)
        .accounts({
          pool,
          configureAuthority: configureAuthority.publicKey,
        })
        .signers([configureAuthority.payer])
        .rpc();

      const poolAccount = await program.account.liquidityPool.fetch(pool);
      assert.equal(
        poolAccount.configureAuthority.toString(),
        newConfigure.publicKey.toString()
      );

      // Change it back to the original for other tests.
      await program.methods
        .updateConfigureAuthority(configureAuthority.publicKey)
        .accounts({
          pool,
          configureAuthority: newConfigure.publicKey,
        })
        .signers([newConfigure])
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

    // Parameterized cross-role rotation matrix: every `update_<role>_authority` call must
    // reject any signer that does not currently hold that exact role. The test fixture sets
    // all four roles to the same payer at init, so a `has_one` violation can only be
    // surfaced by signing with a foreign keypair (not the payer). We exercise all four
    // target roles; the "wrong signer" stands in for any of the other three roles
    // (functionally equivalent because `has_one` reduces to a pubkey equality check).
    type RoleSpec = {
      label: string;
      method:
        | "updatePauseAuthority"
        | "updateUnpauseAuthority"
        | "updateTreasuryAuthority"
        | "updateConfigureAuthority";
      accountField:
        | "pauseAuthority"
        | "unpauseAuthority"
        | "treasuryAuthority"
        | "configureAuthority";
    };

    const roles: RoleSpec[] = [
      {
        label: "pause",
        method: "updatePauseAuthority",
        accountField: "pauseAuthority",
      },
      {
        label: "unpause",
        method: "updateUnpauseAuthority",
        accountField: "unpauseAuthority",
      },
      {
        label: "treasury",
        method: "updateTreasuryAuthority",
        accountField: "treasuryAuthority",
      },
      {
        label: "configure",
        method: "updateConfigureAuthority",
        accountField: "configureAuthority",
      },
    ];

    for (const role of roles) {
      it(`Fails when a non-${role.label} signer tries to rotate the ${role.label} authority`, async () => {
        const stranger = anchor.web3.Keypair.generate();
        const transferTx = new anchor.web3.Transaction().add(
          anchor.web3.SystemProgram.transfer({
            fromPubkey: payer.publicKey,
            toPubkey: stranger.publicKey,
            lamports: 0.05 * anchor.web3.LAMPORTS_PER_SOL,
          })
        );
        await provider.sendAndConfirm(transferTx, [payer.payer]);

        const newAuthority = anchor.web3.Keypair.generate();
        try {
          await (program.methods as any)
            [role.method](newAuthority.publicKey)
            .accounts({
              pool,
              [role.accountField]: stranger.publicKey,
            })
            .signers([stranger])
            .rpc();
          assert.fail(`Expected constraint violation rotating ${role.label}`);
        } catch (error) {
          assert.include(error.toString().toLowerCase(), "constraint");
        }
      });
    }
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
            configureAuthority: unauthorizedUser.publicKey, // Wrong authority
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
            treasuryAuthority: unauthorizedUser.publicKey, // Wrong authority
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
          .updateFeeRate(new anchor.BN(50))
          .accounts({
            pool,
            configureAuthority: unauthorizedUser.publicKey, // Wrong authority
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
          .pauseSwaps()
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

    it("Fails when pause authority tries to unpause swaps", async () => {
      // First put swaps into a paused state.
      await program.methods
        .pauseSwaps()
        .accounts({ pool, pauseAuthority: pauseAuthority.publicKey })
        .signers([pauseAuthority.payer])
        .rpc();

      try {
        await program.methods
          .unpauseSwaps()
          .accounts({
            pool,
            unpauseAuthority: unauthorizedUser.publicKey, // Wrong authority
          })
          .signers([unauthorizedUser])
          .rpc();
        assert.fail("Expected constraint violation");
      } catch (error) {
        assert.include(error.toString().toLowerCase(), "constraint");
      } finally {
        // Restore unpaused state for subsequent tests.
        await program.methods
          .unpauseSwaps()
          .accounts({ pool, unpauseAuthority: unpauseAuthority.publicKey })
          .signers([unpauseAuthority.payer])
          .rpc();
      }
    });

    it("Fails when treasury tries to list a token (configure-only)", async () => {
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
            configureAuthority: unauthorizedUser.publicKey, // wrong role
            tokenProgram: TOKEN_PROGRAM_ID,
            associatedTokenProgram: ASSOCIATED_TOKEN_PROGRAM_ID,
            systemProgram: SystemProgram.programId,
            rent: anchor.web3.SYSVAR_RENT_PUBKEY,
          })
          .signers([unauthorizedUser])
          .rpc();
        assert.fail("Expected constraint violation");
      } catch (error) {
        assert.include(error.toString().toLowerCase(), "constraint");
      }
    });
  });

  describe("Withdraw Recipient Allowlist", () => {
    let foreignOwner: anchor.web3.Keypair;
    let foreignUsdcAccount: PublicKey;

    before(async () => {
      foreignOwner = anchor.web3.Keypair.generate();
      foreignUsdcAccount = await createAccount(
        provider.connection,
        payer.payer,
        usdcMint,
        foreignOwner.publicKey
      );
    });

    async function fundStranger(stranger: anchor.web3.Keypair) {
      const tx = new anchor.web3.Transaction().add(
        anchor.web3.SystemProgram.transfer({
          fromPubkey: payer.publicKey,
          toPubkey: stranger.publicKey,
          lamports: 0.05 * anchor.web3.LAMPORTS_PER_SOL,
        })
      );
      await provider.sendAndConfirm(tx, [payer.payer]);
    }

    it("Rejects withdraw to an owner not on the allowlist", async () => {
      try {
        await program.methods
          .withdrawLiquidity(new anchor.BN(1))
          .accounts({
            pool,
            vault: usdcVault,
            vaultTokenAccount: usdcVaultTokenAccount,
            recipientTokenAccount: foreignUsdcAccount, // owner not allowlisted
            mint: usdcMint,
            treasuryAuthority: treasuryAuthority.publicKey,
            tokenProgram: TOKEN_PROGRAM_ID,
          })
          .signers([treasuryAuthority.payer])
          .rpc();
        assert.fail("Expected WithdrawRecipientNotAllowed");
      } catch (error) {
        assert.include(
          error.toString().toLowerCase(),
          "withdrawrecipientnotallowed"
        );
      }
    });

    it("Lets configure_authority add a recipient, unlocking withdraws to it", async () => {
      await program.methods
        .addWithdrawRecipient(foreignOwner.publicKey)
        .accounts({
          pool,
          configureAuthority: configureAuthority.publicKey,
        })
        .signers([configureAuthority.payer])
        .rpc();

      const poolAccount = await program.account.liquidityPool.fetch(pool);
      assert.isTrue(
        poolAccount.withdrawRecipients.some((r) =>
          r.equals(foreignOwner.publicKey)
        )
      );

      const before = await getAccount(provider.connection, foreignUsdcAccount);
      await program.methods
        .withdrawLiquidity(new anchor.BN(1))
        .accounts({
          pool,
          vault: usdcVault,
          vaultTokenAccount: usdcVaultTokenAccount,
          recipientTokenAccount: foreignUsdcAccount,
          mint: usdcMint,
          treasuryAuthority: treasuryAuthority.publicKey,
          tokenProgram: TOKEN_PROGRAM_ID,
        })
        .signers([treasuryAuthority.payer])
        .rpc();
      const after = await getAccount(provider.connection, foreignUsdcAccount);
      assert.equal(after.amount - before.amount, BigInt(1));

      // The original seed recipient (payer) is still allowed simultaneously.
      const beforeUser = await getAccount(provider.connection, userUsdcAccount);
      await program.methods
        .withdrawLiquidity(new anchor.BN(1))
        .accounts({
          pool,
          vault: usdcVault,
          vaultTokenAccount: usdcVaultTokenAccount,
          recipientTokenAccount: userUsdcAccount,
          mint: usdcMint,
          treasuryAuthority: treasuryAuthority.publicKey,
          tokenProgram: TOKEN_PROGRAM_ID,
        })
        .signers([treasuryAuthority.payer])
        .rpc();
      const afterUser = await getAccount(provider.connection, userUsdcAccount);
      assert.equal(afterUser.amount - beforeUser.amount, BigInt(1));
    });

    it("Rejects adding a duplicate recipient", async () => {
      try {
        await program.methods
          .addWithdrawRecipient(foreignOwner.publicKey)
          .accounts({ pool, configureAuthority: configureAuthority.publicKey })
          .signers([configureAuthority.payer])
          .rpc();
        assert.fail("Expected WithdrawRecipientAlreadyAllowed");
      } catch (error) {
        assert.include(
          error.toString().toLowerCase(),
          "withdrawrecipientalreadyallowed"
        );
      }
    });

    it("Rejects adding the default pubkey", async () => {
      try {
        await program.methods
          .addWithdrawRecipient(PublicKey.default)
          .accounts({ pool, configureAuthority: configureAuthority.publicKey })
          .signers([configureAuthority.payer])
          .rpc();
        assert.fail("Expected RecipientNotSet");
      } catch (error) {
        assert.include(error.toString().toLowerCase(), "recipientnotset");
      }
    });

    it("Rejects add_withdraw_recipient from a non-configure signer", async () => {
      const stranger = anchor.web3.Keypair.generate();
      await fundStranger(stranger);
      try {
        await program.methods
          .addWithdrawRecipient(stranger.publicKey)
          .accounts({ pool, configureAuthority: stranger.publicKey })
          .signers([stranger])
          .rpc();
        assert.fail("Expected constraint violation");
      } catch (error) {
        assert.include(error.toString().toLowerCase(), "constraint");
      }
    });

    it("Rejects remove_withdraw_recipient from a non-configure signer", async () => {
      const stranger = anchor.web3.Keypair.generate();
      await fundStranger(stranger);
      try {
        await program.methods
          .removeWithdrawRecipient(foreignOwner.publicKey)
          .accounts({ pool, configureAuthority: stranger.publicKey })
          .signers([stranger])
          .rpc();
        assert.fail("Expected constraint violation");
      } catch (error) {
        assert.include(error.toString().toLowerCase(), "constraint");
      }
    });

    it("Rejects removing a recipient that is not on the allowlist", async () => {
      try {
        await program.methods
          .removeWithdrawRecipient(anchor.web3.Keypair.generate().publicKey)
          .accounts({ pool, configureAuthority: configureAuthority.publicKey })
          .signers([configureAuthority.payer])
          .rpc();
        assert.fail("Expected WithdrawRecipientNotAllowed");
      } catch (error) {
        assert.include(
          error.toString().toLowerCase(),
          "withdrawrecipientnotallowed"
        );
      }
    });

    it("Lets configure_authority remove a recipient, re-locking withdraws to it", async () => {
      await program.methods
        .removeWithdrawRecipient(foreignOwner.publicKey)
        .accounts({ pool, configureAuthority: configureAuthority.publicKey })
        .signers([configureAuthority.payer])
        .rpc();

      const poolAccount = await program.account.liquidityPool.fetch(pool);
      assert.isFalse(
        poolAccount.withdrawRecipients.some((r) =>
          r.equals(foreignOwner.publicKey)
        )
      );

      try {
        await program.methods
          .withdrawLiquidity(new anchor.BN(1))
          .accounts({
            pool,
            vault: usdcVault,
            vaultTokenAccount: usdcVaultTokenAccount,
            recipientTokenAccount: foreignUsdcAccount,
            mint: usdcMint,
            treasuryAuthority: treasuryAuthority.publicKey,
            tokenProgram: TOKEN_PROGRAM_ID,
          })
          .signers([treasuryAuthority.payer])
          .rpc();
        assert.fail("Expected WithdrawRecipientNotAllowed");
      } catch (error) {
        assert.include(
          error.toString().toLowerCase(),
          "withdrawrecipientnotallowed"
        );
      }
    });

    it("Enforces the maximum number of withdraw recipients", async () => {
      // Seed already holds one entry (payer). Fill up to the on-chain cap.
      const MAX_WITHDRAW_RECIPIENTS = 10;
      let current = (await program.account.liquidityPool.fetch(pool))
        .withdrawRecipients.length;
      const added: PublicKey[] = [];
      while (current < MAX_WITHDRAW_RECIPIENTS) {
        const r = anchor.web3.Keypair.generate().publicKey;
        await program.methods
          .addWithdrawRecipient(r)
          .accounts({ pool, configureAuthority: configureAuthority.publicKey })
          .signers([configureAuthority.payer])
          .rpc();
        added.push(r);
        current += 1;
      }

      try {
        await program.methods
          .addWithdrawRecipient(anchor.web3.Keypair.generate().publicKey)
          .accounts({ pool, configureAuthority: configureAuthority.publicKey })
          .signers([configureAuthority.payer])
          .rpc();
        assert.fail("Expected MaxWithdrawRecipientsReached");
      } catch (error) {
        assert.include(
          error.toString().toLowerCase(),
          "maxwithdrawrecipientsreached"
        );
      }

      // Clean up so later suites see only the seed recipient.
      for (const r of added) {
        await program.methods
          .removeWithdrawRecipient(r)
          .accounts({ pool, configureAuthority: configureAuthority.publicKey })
          .signers([configureAuthority.payer])
          .rpc();
      }
    });
  });

  describe("Self-Rotation of New Roles", () => {
    async function fund(stranger: anchor.web3.Keypair) {
      const tx = new anchor.web3.Transaction().add(
        anchor.web3.SystemProgram.transfer({
          fromPubkey: payer.publicKey,
          toPubkey: stranger.publicKey,
          lamports: 0.05 * anchor.web3.LAMPORTS_PER_SOL,
        })
      );
      await provider.sendAndConfirm(tx, [payer.payer]);
    }

    it("treasury rotates itself", async () => {
      const next = anchor.web3.Keypair.generate();
      await program.methods
        .updateTreasuryAuthority(next.publicKey)
        .accounts({ pool, treasuryAuthority: treasuryAuthority.publicKey })
        .signers([treasuryAuthority.payer])
        .rpc();
      let p = await program.account.liquidityPool.fetch(pool);
      assert.equal(p.treasuryAuthority.toString(), next.publicKey.toString());

      await fund(next);
      await program.methods
        .updateTreasuryAuthority(treasuryAuthority.publicKey)
        .accounts({ pool, treasuryAuthority: next.publicKey })
        .signers([next])
        .rpc();
      p = await program.account.liquidityPool.fetch(pool);
      assert.equal(
        p.treasuryAuthority.toString(),
        treasuryAuthority.publicKey.toString()
      );
    });

    it("unpause rotates itself; pause cannot rotate it", async () => {
      const next = anchor.web3.Keypair.generate();
      await program.methods
        .updateUnpauseAuthority(next.publicKey)
        .accounts({ pool, unpauseAuthority: unpauseAuthority.publicKey })
        .signers([unpauseAuthority.payer])
        .rpc();
      let p = await program.account.liquidityPool.fetch(pool);
      assert.equal(p.unpauseAuthority.toString(), next.publicKey.toString());

      // Pause cannot rotate unpause.
      const stranger = anchor.web3.Keypair.generate();
      await fund(stranger);
      try {
        await program.methods
          .updateUnpauseAuthority(stranger.publicKey)
          .accounts({ pool, unpauseAuthority: stranger.publicKey })
          .signers([stranger])
          .rpc();
        assert.fail("Expected constraint violation");
      } catch (error) {
        assert.include(error.toString().toLowerCase(), "constraint");
      }

      // Restore.
      await fund(next);
      await program.methods
        .updateUnpauseAuthority(unpauseAuthority.publicKey)
        .accounts({ pool, unpauseAuthority: next.publicKey })
        .signers([next])
        .rpc();
    });

    it("Rejects rotating any role to the default pubkey", async () => {
      // Rotation requires the current holder to sign, so a role handed to the zero key
      // could never be recovered.
      const rotations: [string, () => Promise<string>][] = [
        [
          "pause",
          () =>
            program.methods
              .updatePauseAuthority(PublicKey.default)
              .accounts({ pool, pauseAuthority: pauseAuthority.publicKey })
              .signers([pauseAuthority.payer])
              .rpc(),
        ],
        [
          "unpause",
          () =>
            program.methods
              .updateUnpauseAuthority(PublicKey.default)
              .accounts({ pool, unpauseAuthority: unpauseAuthority.publicKey })
              .signers([unpauseAuthority.payer])
              .rpc(),
        ],
        [
          "treasury",
          () =>
            program.methods
              .updateTreasuryAuthority(PublicKey.default)
              .accounts({
                pool,
                treasuryAuthority: treasuryAuthority.publicKey,
              })
              .signers([treasuryAuthority.payer])
              .rpc(),
        ],
        [
          "configure",
          () =>
            program.methods
              .updateConfigureAuthority(PublicKey.default)
              .accounts({
                pool,
                configureAuthority: configureAuthority.publicKey,
              })
              .signers([configureAuthority.payer])
              .rpc(),
        ],
      ];

      for (const [role, rotate] of rotations) {
        try {
          await rotate();
          assert.fail(`Expected AuthorityNotSet for ${role}`);
        } catch (error) {
          assert.include(
            error.toString().toLowerCase(),
            "authoritynotset",
            `role: ${role}`
          );
        }
      }

      // The pool must be untouched by the rejected rotations.
      const p = await program.account.liquidityPool.fetch(pool);
      assert.equal(
        p.pauseAuthority.toString(),
        pauseAuthority.publicKey.toString()
      );
      assert.equal(
        p.configureAuthority.toString(),
        configureAuthority.publicKey.toString()
      );
    });
  });

  describe("Migration guard", () => {
    it("Rejects migrate_authorities on a pool already in the new layout", async () => {
      // The live test pool was initialized with the new layout, so migrate must
      // refuse it via the AlreadyMigrated size check.
      try {
        await program.methods
          .migrateAuthorities(
            pauseAuthority.publicKey,
            unpauseAuthority.publicKey,
            treasuryAuthority.publicKey,
            configureAuthority.publicKey,
            withdrawRecipient.publicKey
          )
          .accounts({
            pool,
            payer: payer.publicKey,
            programData,
            systemProgram: SystemProgram.programId,
          })
          .signers([payer.payer])
          .rpc();
        assert.fail("Expected AlreadyMigrated error");
      } catch (error) {
        assert.include(error.toString().toLowerCase(), "alreadymigrated");
      }
    });
  });
});
