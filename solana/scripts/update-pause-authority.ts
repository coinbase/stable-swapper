import * as anchor from "@coral-xyz/anchor";
import { Program } from "@coral-xyz/anchor";
import { ScaasLiquidity } from "../target/types/scaas_liquidity";
import { PublicKey } from "@solana/web3.js";

async function main() {
  // Parse command line arguments
  const args = process.argv.slice(2);

  if (args.length < 1 || args[0] === "--help" || args[0] === "-h") {
    console.log(
      "Usage: yarn ts-node scripts/update-pause-authority.ts <NEW_PAUSE_AUTHORITY>"
    );
    console.log();
    console.log("Arguments:");
    console.log("  NEW_PAUSE_AUTHORITY    New pause authority address");
    console.log();
    console.log("Examples:");
    console.log("  # Update pause authority to a new address");
    console.log(
      "  yarn ts-node scripts/update-pause-authority.ts 9TcjK2ToqoAtCr5jrLdDXNTNbZBbDQB1zy2BNGMr7nQE"
    );
    console.log();
    console.log(
      "Note: You must be the current pause authority to execute this."
    );
    process.exit(args.length < 1 ? 1 : 0);
  }

  const newPauseAuthorityAddress = args[0];

  // Validate new pause authority address
  let newPauseAuthority: PublicKey;
  try {
    newPauseAuthority = new PublicKey(newPauseAuthorityAddress);
  } catch (error) {
    console.error(`❌ Error: Invalid address: ${newPauseAuthorityAddress}`);
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
  console.log("UPDATE PAUSE AUTHORITY");
  console.log("=".repeat(60));
  console.log();

  // Derive PDAs
  const [pool] = PublicKey.findProgramAddressSync(
    [Buffer.from("liquidity_pool")],
    program.programId
  );

  // Fetch pool to verify current pause authority
  const poolAccount = await program.account.liquidityPool.fetch(pool);

  console.log("Configuration:");
  console.log("- Program ID:", program.programId.toString());
  console.log("- Pool PDA:", pool.toString());
  console.log(
    "- Current Pause Authority:",
    poolAccount.pauseAuthority.toString()
  );
  console.log("- Your Wallet:", payer.publicKey.toString());
  console.log("- New Pause Authority:", newPauseAuthority.toString());
  console.log();

  // Verify you are the current pause authority
  if (!poolAccount.pauseAuthority.equals(payer.publicKey)) {
    console.error("❌ Error: You are not the current pause authority");
    console.error(
      `   Current pause authority is: ${poolAccount.pauseAuthority.toString()}`
    );
    console.error(`   Your wallet is: ${payer.publicKey.toString()}`);
    process.exit(1);
  }

  // Check if already set to new authority
  if (poolAccount.pauseAuthority.equals(newPauseAuthority)) {
    console.log("ℹ️  Pause authority is already set to this address");
    process.exit(0);
  }

  console.log("⚠️  WARNING: This will transfer pause authority control!");
  console.log("   The new pause authority will be able to:");
  console.log("   - Pause/unpause swaps and liquidity operations");
  console.log("   - Enable/disable tokens");
  console.log("   - Transfer pause authority to another address");
  console.log();
  console.log("Sending transaction...");
  console.log();

  try {
    const tx = await program.methods
      .updatePauseAuthority(newPauseAuthority)
      .accounts({
        pool: pool,
        pauseAuthority: payer.publicKey,
      } as any)
      .rpc();

    console.log("✅ Pause authority updated successfully!");
    console.log();
    console.log("Transaction Details:");
    console.log("- Signature:", tx);
    console.log("- Explorer:", `https://solscan.io/tx/${tx}`);
    console.log();

    console.log("Authority Transfer:");
    console.log(
      "- Old Pause Authority:",
      poolAccount.pauseAuthority.toString()
    );
    console.log("- New Pause Authority:", newPauseAuthority.toString());
    console.log();

    console.log("=".repeat(60));
    console.log("✅ Authority transfer complete!");
    console.log("=".repeat(60));
  } catch (error: any) {
    console.error("❌ Error updating pause authority:");
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
