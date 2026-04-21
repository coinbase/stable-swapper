import * as anchor from "@coral-xyz/anchor";
import { Program } from "@coral-xyz/anchor";
import { ScaasLiquidity } from "../target/types/scaas_liquidity";
import { PublicKey } from "@solana/web3.js";

async function main() {
  // Parse command line arguments
  const args = process.argv.slice(2);

  if (args.length < 2 || args[0] === "--help" || args[0] === "-h") {
    console.log("Usage: yarn ts-node scripts/update-token-status.ts <TOKEN_MINT> <DISABLED>");
    console.log();
    console.log("Arguments:");
    console.log("  TOKEN_MINT    Token mint address to update");
    console.log("  DISABLED      true to disable token, false to enable");
    console.log();
    console.log("Examples:");
    console.log("  # Disable a token (prevent swaps)");
    console.log("  yarn ts-node scripts/update-token-status.ts EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v true");
    console.log();
    console.log("  # Enable a token (allow swaps)");
    console.log("  yarn ts-node scripts/update-token-status.ts EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v false");
    process.exit(args.length < 2 ? 1 : 0);
  }

  const mintAddress = args[0];
  const disabledArg = args[1].toLowerCase();
  const disabled = disabledArg === "true" || disabledArg === "1" || disabledArg === "yes";

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
    process.env.ANCHOR_WALLET = require('os').homedir() + "/.config/solana/id.json";
  }

  // Load provider from environment
  const provider = anchor.AnchorProvider.env();
  anchor.setProvider(provider);

  const payer = provider.wallet as anchor.Wallet;
  const program = anchor.workspace.scaasLiquidity as Program<ScaasLiquidity>;

  console.log("=".repeat(60));
  console.log("UPDATE TOKEN STATUS");
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

  // Fetch pool to verify pause authority
  const poolAccount = await program.account.liquidityPool.fetch(pool);

  console.log("Configuration:");
  console.log("- Program ID:", program.programId.toString());
  console.log("- Pool PDA:", pool.toString());
  console.log("- Token Mint:", mint.toString());
  console.log("- Vault PDA:", vault.toString());
  console.log("- Pause Authority:", poolAccount.pauseAuthority.toString());
  console.log("- Your Wallet:", payer.publicKey.toString());
  console.log();

  // Verify you are the pause authority
  if (!poolAccount.pauseAuthority.equals(payer.publicKey)) {
    console.error("❌ Error: You are not the pause authority");
    console.error(`   Pause authority is: ${poolAccount.pauseAuthority.toString()}`);
    console.error(`   Your wallet is: ${payer.publicKey.toString()}`);
    process.exit(1);
  }

  // Fetch current vault state
  const vaultAccount = await program.account.tokenVault.fetch(vault);

  console.log("Current State:");
  console.log("- Token Disabled:", vaultAccount.disabled);
  console.log();

  if (vaultAccount.disabled === disabled) {
    console.log(`ℹ️  Token is already ${disabled ? 'disabled' : 'enabled'}`);
    process.exit(0);
  }

  console.log(`Setting token to: ${disabled ? 'DISABLED' : 'ENABLED'}`);
  console.log("Sending transaction...");
  console.log();

  try {
    const tx = await program.methods
      .updateTokenStatus(disabled)
      .accounts({
        pool: pool,
        vault: vault,
        mint: mint,
        pauseAuthority: payer.publicKey,
      } as any)
      .rpc();

    console.log(`${disabled ? '🛑' : '✅'} Token status updated successfully!`);
    console.log();
    console.log("Transaction Details:");
    console.log("- Signature:", tx);
    console.log("- Explorer:", `https://solscan.io/tx/${tx}`);
    console.log();

    console.log("New State:");
    console.log("- Token Disabled:", disabled);
    console.log();

    console.log("=".repeat(60));
    console.log(`${disabled ? '🛑 TOKEN DISABLED' : '✅ TOKEN ENABLED'}`);
    console.log("=".repeat(60));

    if (disabled) {
      console.log();
      console.log("Note: Disabled tokens cannot be used in swaps.");
      console.log("This is useful for emergency situations or token migrations.");
    }

  } catch (error: any) {
    console.error("❌ Error updating token status:");
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
