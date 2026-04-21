import * as anchor from "@coral-xyz/anchor";
import { Program } from "@coral-xyz/anchor";
import { ScaasLiquidity } from "../target/types/scaas_liquidity";
import { PublicKey, SystemProgram } from "@solana/web3.js";
import {
  TOKEN_PROGRAM_ID,
  ASSOCIATED_TOKEN_PROGRAM_ID,
  getAssociatedTokenAddress,
  getAccount,
  createAssociatedTokenAccountInstruction,
} from "@solana/spl-token";

async function main() {
  // Parse command line arguments
  const args = process.argv.slice(2);

  if (args.length < 3 || args[0] === "--help" || args[0] === "-h") {
    console.log(
      "Usage: yarn ts-node scripts/04-test-swap.ts <FROM_MINT> <TO_MINT> <AMOUNT> [RECIPIENT]"
    );
    console.log();
    console.log("Arguments:");
    console.log("  FROM_MINT    The mint address of the token to swap from");
    console.log("  TO_MINT      The mint address of the token to swap to");
    console.log("  AMOUNT       Amount to swap (in token units)");
    console.log(
      "  RECIPIENT    (Optional) Recipient wallet address. If not provided, swaps to your own account"
    );
    console.log();
    console.log("Examples:");
    console.log("  # Swap 1 USDC -> Custom Token (to your own account)");
    console.log(
      "  yarn ts-node scripts/04-test-swap.ts EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v 9gJ94RYM3kUbFyKzzXAaGaRQ4n39XrDCLPZ1XnpZhnms 1"
    );
    console.log();
    console.log("  # Swap 1 Custom Token -> USDC (to another user's account)");
    console.log(
      "  yarn ts-node scripts/04-test-swap.ts 9gJ94RYM3kUbFyKzzXAaGaRQ4n39XrDCLPZ1XnpZhnms EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v 1 <RECIPIENT_WALLET_ADDRESS>"
    );
    process.exit(args.length < 3 ? 1 : 0);
  }

  const fromMintAddress = args[0];
  const toMintAddress = args[1];
  const amountTokens = parseFloat(args[2]);
  const recipientAddress = args[3]; // Optional

  // Validate mint addresses
  let fromMint: PublicKey;
  let toMint: PublicKey;
  let recipient: PublicKey | undefined;

  try {
    fromMint = new PublicKey(fromMintAddress);
    toMint = new PublicKey(toMintAddress);

    if (recipientAddress) {
      recipient = new PublicKey(recipientAddress);
    }
  } catch (error) {
    console.error("❌ Error: Invalid mint or recipient address");
    process.exit(1);
  }

  if (fromMint.equals(toMint)) {
    console.error("❌ Error: Cannot swap a token for itself");
    process.exit(1);
  }

  // Validate amount
  if (isNaN(amountTokens) || amountTokens <= 0) {
    console.error("❌ Error: Amount must be a positive number");
    process.exit(1);
  }

  // Set default environment variables if not already set
  if (!process.env.ANCHOR_PROVIDER_URL) {
    process.env.ANCHOR_PROVIDER_URL = "https://api.mainnet-beta.solana.com";
  }
  if (!process.env.ANCHOR_WALLET) {
    process.env.ANCHOR_WALLET =
      require("os").homedir() + "/.config/solana/id.json";
  }

  // Load provider from environment
  const provider = anchor.AnchorProvider.env();
  anchor.setProvider(provider);

  const payer = provider.wallet as anchor.Wallet;
  const program = anchor.workspace.scaasLiquidity as Program<ScaasLiquidity>;

  console.log("=".repeat(60));
  console.log("TEST SWAP");
  console.log("=".repeat(60));
  console.log();

  // Derive PDAs
  const [pool] = PublicKey.findProgramAddressSync(
    [Buffer.from("liquidity_pool")],
    program.programId
  );

  const [whitelist] = PublicKey.findProgramAddressSync(
    [Buffer.from("address_whitelist")],
    program.programId
  );

  const [inVault] = PublicKey.findProgramAddressSync(
    [Buffer.from("token_vault"), pool.toBuffer(), fromMint.toBuffer()],
    program.programId
  );

  const [outVault] = PublicKey.findProgramAddressSync(
    [Buffer.from("token_vault"), pool.toBuffer(), toMint.toBuffer()],
    program.programId
  );

  const [inVaultTokenAccount] = PublicKey.findProgramAddressSync(
    [Buffer.from("vault_token_account"), inVault.toBuffer()],
    program.programId
  );

  const [outVaultTokenAccount] = PublicKey.findProgramAddressSync(
    [Buffer.from("vault_token_account"), outVault.toBuffer()],
    program.programId
  );

  // Get user token accounts
  const userFromTokenAccount = await getAssociatedTokenAddress(
    fromMint,
    payer.publicKey
  );

  // Determine recipient (use provided recipient or default to user)
  const recipientWallet = recipient || payer.publicKey;
  const userToTokenAccount = await getAssociatedTokenAddress(
    toMint,
    recipientWallet
  );

  // Get fee recipient token account
  const poolAccount = await program.account.liquidityPool.fetch(pool);
  const feeRecipientFromTokenAccount = await getAssociatedTokenAddress(
    fromMint,
    poolAccount.feeRecipient
  );

  // Fetch mint info to get decimals
  const fromMintInfo = await provider.connection.getParsedAccountInfo(fromMint);
  const toMintInfo = await provider.connection.getParsedAccountInfo(toMint);

  if (
    !fromMintInfo.value ||
    !("parsed" in fromMintInfo.value.data) ||
    !toMintInfo.value ||
    !("parsed" in toMintInfo.value.data)
  ) {
    console.error("❌ Error: Could not fetch mint info");
    process.exit(1);
  }

  const fromDecimals = (fromMintInfo.value.data as any).parsed.info.decimals;
  const toDecimals = (toMintInfo.value.data as any).parsed.info.decimals;
  const amountIn = new anchor.BN(amountTokens * Math.pow(10, fromDecimals));

  // For 1:1 swap with 0% fee, min_amount_out should be the same (adjusted for decimals)
  const minAmountOut = new anchor.BN(
    amountTokens * Math.pow(10, toDecimals) * 0.99
  ); // 1% slippage tolerance

  console.log("Configuration:");
  console.log("- Program ID:", program.programId.toString());
  console.log("- Pool PDA:", pool.toString());
  console.log("- User (Signer):", payer.publicKey.toString());
  if (recipient) {
    console.log("- Recipient (Destination):", recipientWallet.toString());
  }
  console.log();

  console.log("Swap Details:");
  console.log("- From Token:", fromMint.toString());
  console.log("- To Token:", toMint.toString());
  console.log("- Amount In:", amountTokens, "tokens");
  console.log("- Amount In (base units):", amountIn.toString());
  console.log("- Min Amount Out (base units):", minAmountOut.toString());
  console.log("- From Decimals:", fromDecimals);
  console.log("- To Decimals:", toDecimals);
  console.log();

  // Check balances before
  try {
    const fromAccount = await getAccount(
      provider.connection,
      userFromTokenAccount
    );
    const fromBalance = Number(fromAccount.amount) / Math.pow(10, fromDecimals);
    console.log("Your Balance (From Token):", fromBalance, "tokens");

    if (fromBalance < amountTokens) {
      console.error("❌ Error: Insufficient balance");
      console.error(
        `   You have ${fromBalance} tokens but trying to swap ${amountTokens}`
      );
      process.exit(1);
    }
  } catch (error) {
    console.error("❌ Error: You don't have the from token in your account");
    process.exit(1);
  }

  // Check if destination token account exists, create if needed
  let needsToAccountCreation = false;
  try {
    const toAccount = await getAccount(provider.connection, userToTokenAccount);
    const toBalance = Number(toAccount.amount) / Math.pow(10, toDecimals);
    if (recipient) {
      console.log("Recipient Balance (To Token):", toBalance, "tokens");
    } else {
      console.log("Your Balance (To Token):", toBalance, "tokens");
    }
  } catch (error) {
    if (recipient) {
      console.log(
        "Recipient Balance (To Token): 0 tokens (account doesn't exist)"
      );
    } else {
      console.log("Your Balance (To Token): 0 tokens (account doesn't exist)");
    }
    needsToAccountCreation = true;
  }
  console.log();

  console.log("Sending transaction...");

  try {
    // Build the swap instruction
    const swapIx = await program.methods
      .swap(amountIn, minAmountOut)
      .accounts({
        pool: pool,
        inVault: inVault,
        outVault: outVault,
        inVaultTokenAccount: inVaultTokenAccount,
        outVaultTokenAccount: outVaultTokenAccount,
        userFromTokenAccount: userFromTokenAccount,
        toTokenAccount: userToTokenAccount,
        feeRecipientTokenAccount: feeRecipientFromTokenAccount,
        feeRecipient: poolAccount.feeRecipient,
        fromMint: fromMint,
        toMint: toMint,
        user: payer.publicKey,
        whitelist: whitelist,
        tokenProgram: TOKEN_PROGRAM_ID,
        associatedTokenProgram: ASSOCIATED_TOKEN_PROGRAM_ID,
        systemProgram: SystemProgram.programId,
      } as any)
      .instruction();

    // Build transaction with optional ATA creation
    const transaction = new anchor.web3.Transaction();

    if (needsToAccountCreation) {
      if (recipient) {
        console.log("Creating destination token account for recipient...");
      } else {
        console.log("Creating destination token account...");
      }
      const createAtaIx = createAssociatedTokenAccountInstruction(
        payer.publicKey, // Payer (signer pays for account creation)
        userToTokenAccount,
        recipientWallet, // Authority (owner of the new account)
        toMint
      );
      transaction.add(createAtaIx);
    }

    transaction.add(swapIx);

    // Send transaction
    const tx = await provider.sendAndConfirm(transaction);

    console.log("✅ Swap successful!");
    console.log();
    console.log("Transaction Details:");
    console.log("- Signature:", tx);
    console.log("- Explorer:", `https://solscan.io/tx/${tx}`);
    console.log();

    // Check balances after
    const fromAccountAfter = await getAccount(
      provider.connection,
      userFromTokenAccount
    );
    const fromBalanceAfter =
      Number(fromAccountAfter.amount) / Math.pow(10, fromDecimals);

    const toAccountAfter = await getAccount(
      provider.connection,
      userToTokenAccount
    );
    const toBalanceAfter =
      Number(toAccountAfter.amount) / Math.pow(10, toDecimals);

    console.log("Your Balance After (From Token):", fromBalanceAfter, "tokens");
    if (recipient) {
      console.log(
        "Recipient Balance After (To Token):",
        toBalanceAfter,
        "tokens"
      );
    } else {
      console.log("Your Balance After (To Token):", toBalanceAfter, "tokens");
    }
    console.log();

    console.log("=".repeat(60));
    console.log("✅ Swap complete!");
    console.log("=".repeat(60));
  } catch (error: any) {
    console.error("❌ Error performing swap:");
    console.error(error);

    if (error.logs) {
      console.error("\nProgram Logs:");
      error.logs.forEach((log: string) => console.error(log));
    }

    process.exit(1);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
