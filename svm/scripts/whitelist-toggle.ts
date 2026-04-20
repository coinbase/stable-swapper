import * as anchor from "@coral-xyz/anchor";
import { Program } from "@coral-xyz/anchor";
import { ScaasLiquidity } from "../target/types/scaas_liquidity";
import { PublicKey } from "@solana/web3.js";

async function main() {
  // Parse command line arguments
  const args = process.argv.slice(2);

  if (args.length < 1 || args[0] === "--help" || args[0] === "-h") {
    console.log("Usage: yarn ts-node scripts/whitelist-toggle.ts <ENABLED>");
    console.log();
    console.log("Arguments:");
    console.log("  ENABLED    true to enable whitelist, false to disable");
    console.log();
    console.log("Examples:");
    console.log("  # Enable whitelist");
    console.log("  yarn ts-node scripts/whitelist-toggle.ts true");
    console.log();
    console.log("  # Disable whitelist");
    console.log("  yarn ts-node scripts/whitelist-toggle.ts false");
    process.exit(args.length < 1 ? 1 : 0);
  }

  const enabledArg = args[0].toLowerCase();
  const enabled =
    enabledArg === "true" || enabledArg === "1" || enabledArg === "yes";

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
  console.log("TOGGLE WHITELIST");
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

  // Fetch pool to verify pause authority
  const poolAccount = await program.account.liquidityPool.fetch(pool);

  console.log("Configuration:");
  console.log("- Program ID:", program.programId.toString());
  console.log("- Pool PDA:", pool.toString());
  console.log("- Whitelist PDA:", whitelist.toString());
  console.log("- Pause Authority:", poolAccount.pauseAuthority.toString());
  console.log("- Your Wallet:", payer.publicKey.toString());
  console.log();

  // Verify you are the pause authority
  if (!poolAccount.pauseAuthority.equals(payer.publicKey)) {
    console.error("❌ Error: You are not the pause authority");
    console.error(
      `   Pause authority is: ${poolAccount.pauseAuthority.toString()}`
    );
    console.error(`   Your wallet is: ${payer.publicKey.toString()}`);
    process.exit(1);
  }

  // Fetch current whitelist state
  const whitelistAccount = await program.account.addressWhitelist.fetch(
    whitelist
  );

  console.log("Current State:");
  console.log("- Whitelist Enabled:", whitelistAccount.enabled);
  console.log("- Addresses in Whitelist:", whitelistAccount.addresses.length);
  console.log();

  if (whitelistAccount.enabled === enabled) {
    console.log(`ℹ️  Whitelist is already ${enabled ? "enabled" : "disabled"}`);
    process.exit(0);
  }

  console.log(`Setting whitelist to: ${enabled ? "ENABLED" : "DISABLED"}`);
  console.log("Sending transaction...");
  console.log();

  try {
    const tx = await program.methods
      .toggleWhitelist(enabled)
      .accounts({
        pool: pool,
        whitelist: whitelist,
        pauseAuthority: payer.publicKey,
      } as any)
      .rpc();

    console.log("✅ Whitelist toggled successfully!");
    console.log();
    console.log("Transaction Details:");
    console.log("- Signature:", tx);
    console.log("- Explorer:", `https://solscan.io/tx/${tx}`);
    console.log();

    console.log("New State:");
    console.log("- Whitelist Enabled:", enabled);
    console.log();

    console.log("=".repeat(60));
    console.log("✅ Complete!");
    console.log("=".repeat(60));
  } catch (error: any) {
    console.error("❌ Error toggling whitelist:");
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
