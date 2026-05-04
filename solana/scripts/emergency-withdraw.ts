import * as anchor from "@coral-xyz/anchor";
import { Program } from "@coral-xyz/anchor";
import { ScaasLiquidity } from "../target/types/scaas_liquidity";
import { PublicKey } from "@solana/web3.js";
import { getAccount, getAssociatedTokenAddress } from "@solana/spl-token";

async function main() {
  // Parse command line arguments
  const args = process.argv.slice(2);

  if (args.length < 1 || args[0] === "--help" || args[0] === "-h") {
    console.log(
      "Usage: yarn ts-node scripts/emergency-withdraw.ts <TOKEN_MINT> [AMOUNT]"
    );
    console.log();
    console.log("Arguments:");
    console.log("  TOKEN_MINT    Token mint address to withdraw");
    console.log(
      "  AMOUNT        Amount to withdraw in tokens (optional, defaults to 'max' for all available)"
    );
    console.log();
    console.log("Examples:");
    console.log("  # Withdraw all available liquidity");
    console.log(
      "  yarn ts-node scripts/emergency-withdraw.ts EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v"
    );
    console.log(
      "  yarn ts-node scripts/emergency-withdraw.ts EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v max"
    );
    console.log();
    console.log("  # Withdraw specific amount");
    console.log(
      "  yarn ts-node scripts/emergency-withdraw.ts EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v 100"
    );
    process.exit(args.length < 1 ? 1 : 0);
  }

  const mintAddress = args[0];
  const amountArg = args[1] || "max";

  // Validate mint address
  let mint: PublicKey;
  try {
    mint = new PublicKey(mintAddress);
  } catch (error) {
    console.error(`❌ Error: Invalid mint address: ${mintAddress}`);
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
  console.log("EMERGENCY WITHDRAW LIQUIDITY");
  console.log("=".repeat(60));
  console.log();

  // Derive PDAs
  const [pool] = PublicKey.findProgramAddressSync(
    [Buffer.from("liquidity_pool")],
    program.programId
  );

  const [vault] = PublicKey.findProgramAddressSync(
    [Buffer.from("token_vault"), pool.toBuffer(), mint.toBuffer()],
    program.programId
  );

  const [vaultTokenAccount] = PublicKey.findProgramAddressSync(
    [Buffer.from("vault_token_account"), vault.toBuffer()],
    program.programId
  );

  // Fetch accounts
  const poolAccount = await program.account.liquidityPool.fetch(pool);
  const vaultAccount = await program.account.tokenVault.fetch(vault);
  const mintAccount = await provider.connection.getAccountInfo(mint);

  if (!mintAccount) {
    console.error("❌ Error: Mint account not found");
    process.exit(1);
  }

  // Recipient is locked on-chain to the ATA owned by `pool.withdraw_recipient`.
  // The treasury authority cannot redirect funds elsewhere.
  const withdrawRecipientTokenAccount = await getAssociatedTokenAddress(
    mint,
    poolAccount.withdrawRecipient,
    false
  );

  const mintData = await provider.connection.getParsedAccountInfo(mint);
  const decimals = (mintData.value?.data as any).parsed.info.decimals;

  console.log("Configuration:");
  console.log("- Program ID:", program.programId.toString());
  console.log("- Pool PDA:", pool.toString());
  console.log("- Token Mint:", mint.toString());
  console.log("- Token Decimals:", decimals);
  console.log("- Vault PDA:", vault.toString());
  console.log("- Vault Token Account:", vaultTokenAccount.toString());
  console.log(
    "- Treasury Authority:",
    poolAccount.treasuryAuthority.toString()
  );
  console.log(
    "- Withdraw Recipient (owner):",
    poolAccount.withdrawRecipient.toString()
  );
  console.log(
    "- Withdraw Recipient ATA:",
    withdrawRecipientTokenAccount.toString()
  );
  console.log("- Your Wallet:", payer.publicKey.toString());
  console.log();

  // Verify you are the treasury authority.
  if (!poolAccount.treasuryAuthority.equals(payer.publicKey)) {
    console.error("❌ Error: You are not the treasury authority");
    console.error(
      `   Treasury authority is: ${poolAccount.treasuryAuthority.toString()}`
    );
    console.error(`   Your wallet is: ${payer.publicKey.toString()}`);
    process.exit(1);
  }

  // Fetch vault balance
  const vaultTokenAccountInfo = await getAccount(
    provider.connection,
    vaultTokenAccount
  );
  const vaultBalance =
    Number(vaultTokenAccountInfo.amount) / Math.pow(10, decimals);

  console.log("Current State:");
  console.log(
    "- Vault Total Balance:",
    vaultBalance.toLocaleString(),
    "tokens"
  );
  console.log("- Token Disabled:", vaultAccount.disabled);
  console.log();

  if (vaultBalance === 0) {
    console.log("ℹ️  Vault is already empty, nothing to withdraw");
    process.exit(0);
  }

  // Determine amount to withdraw
  let withdrawAmount: number;
  let withdrawAmountBaseUnits: anchor.BN;

  if (amountArg.toLowerCase() === "max") {
    withdrawAmount = vaultBalance;
    withdrawAmountBaseUnits = new anchor.BN(
      vaultTokenAccountInfo.amount.toString()
    );
    console.log("⚠️  WITHDRAWING ALL LIQUIDITY (MAX)");
  } else {
    withdrawAmount = parseFloat(amountArg);
    if (isNaN(withdrawAmount) || withdrawAmount <= 0) {
      console.error(`❌ Error: Invalid amount: ${amountArg}`);
      process.exit(1);
    }
    if (withdrawAmount > vaultBalance) {
      console.error(
        `❌ Error: Amount ${withdrawAmount} exceeds vault balance ${vaultBalance}`
      );
      process.exit(1);
    }
    withdrawAmountBaseUnits = new anchor.BN(
      Math.floor(withdrawAmount * Math.pow(10, decimals))
    );
    console.log(`⚠️  WITHDRAWING ${withdrawAmount.toLocaleString()} TOKENS`);
  }

  console.log();
  console.log("Withdrawal Details:");
  console.log("- Amount (tokens):", withdrawAmount.toLocaleString());
  console.log("- Amount (base units):", withdrawAmountBaseUnits.toString());
  console.log();
  console.log("Sending transaction...");
  console.log();

  try {
    const tx = await program.methods
      .withdrawLiquidity(withdrawAmountBaseUnits)
      .accounts({
        pool: pool,
        vault: vault,
        vaultTokenAccount: vaultTokenAccount,
        recipientTokenAccount: withdrawRecipientTokenAccount,
        mint: mint,
        treasuryAuthority: payer.publicKey,
        tokenProgram: anchor.utils.token.TOKEN_PROGRAM_ID,
      } as any)
      .rpc();

    console.log("✅ Liquidity withdrawn successfully!");
    console.log();
    console.log("Transaction Details:");
    console.log("- Signature:", tx);
    console.log("- Explorer:", `https://solscan.io/tx/${tx}`);
    console.log();

    // Fetch updated balance
    const updatedVaultTokenAccountInfo = await getAccount(
      provider.connection,
      vaultTokenAccount
    );
    const updatedVaultBalance =
      Number(updatedVaultTokenAccountInfo.amount) / Math.pow(10, decimals);

    console.log("Updated State:");
    console.log(
      "- Vault Balance After:",
      updatedVaultBalance.toLocaleString(),
      "tokens"
    );
    console.log(
      "- Amount Withdrawn:",
      withdrawAmount.toLocaleString(),
      "tokens"
    );
    console.log();

    console.log("=".repeat(60));
    console.log("✅ EMERGENCY WITHDRAWAL COMPLETE");
    console.log("=".repeat(60));
  } catch (error: any) {
    console.error("❌ Error withdrawing liquidity:");
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
