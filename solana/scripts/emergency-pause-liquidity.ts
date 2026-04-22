import * as anchor from "@coral-xyz/anchor";
import { Program } from "@coral-xyz/anchor";
import { ScaasLiquidity } from "../target/types/scaas_liquidity";
import { PublicKey } from "@solana/web3.js";

async function main() {
  // Parse command line arguments
  const args = process.argv.slice(2);

  if (args[0] === "--help" || args[0] === "-h") {
    console.log("Usage: yarn ts-node scripts/emergency-pause-liquidity.ts [PAUSED]");
    console.log();
    console.log("Arguments:");
    console.log("  PAUSED     true to pause liquidity operations, false to unpause (optional, defaults to true)");
    console.log();
    console.log("Examples:");
    console.log("  # Pause liquidity operations (emergency)");
    console.log("  yarn ts-node scripts/emergency-pause-liquidity.ts");
    console.log("  yarn ts-node scripts/emergency-pause-liquidity.ts true");
    console.log();
    console.log("  # Unpause liquidity operations (restore normal operations)");
    console.log("  yarn ts-node scripts/emergency-pause-liquidity.ts false");
    process.exit(0);
  }

  // Default to pausing if no argument provided (emergency mode)
  const pausedArg = args[0]?.toLowerCase();
  const paused = pausedArg === undefined || pausedArg === "true" || pausedArg === "1" || pausedArg === "yes";

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
  console.log("EMERGENCY PAUSE LIQUIDITY");
  console.log("=".repeat(60));
  console.log();

  // Derive PDAs
  const [pool] = PublicKey.findProgramAddressSync(
    [Buffer.from("liquidity_pool")],
    program.programId
  );

  // Fetch pool to verify pause authority
  const poolAccount = await program.account.liquidityPool.fetch(pool);

  console.log("Configuration:");
  console.log("- Program ID:", program.programId.toString());
  console.log("- Pool PDA:", pool.toString());
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

  console.log("Current State:");
  console.log("- Swaps Paused:", poolAccount.swapsPaused);
  console.log("- Liquidity Paused:", poolAccount.liquidityPaused);
  console.log();

  if (poolAccount.liquidityPaused === paused) {
    console.log(`ℹ️  Liquidity operations are already ${paused ? 'paused' : 'unpaused'}`);
    process.exit(0);
  }

  console.log(`${paused ? '⚠️  PAUSING LIQUIDITY OPERATIONS' : '✅ UNPAUSING LIQUIDITY OPERATIONS'}`);
  console.log("Sending transaction...");
  console.log();

  try {
    const tx = await program.methods
      .updatePauseConfig(null, paused)
      .accounts({
        pool: pool,
        pauseAuthority: payer.publicKey,
      } as any)
      .rpc();

    console.log(`${paused ? '🛑' : '✅'} Liquidity operations ${paused ? 'paused' : 'unpaused'} successfully!`);
    console.log();
    console.log("Transaction Details:");
    console.log("- Signature:", tx);
    console.log("- Explorer:", `https://solscan.io/tx/${tx}`);
    console.log();

    console.log("New State:");
    console.log("- Liquidity Paused:", paused);
    console.log();

    console.log("=".repeat(60));
    console.log(`${paused ? '🛑 LIQUIDITY PAUSED' : '✅ LIQUIDITY RESTORED'}`);
    console.log("=".repeat(60));

  } catch (error: any) {
    console.error("❌ Error updating pause config:");
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
