import * as anchor from "@coral-xyz/anchor";
import { Program } from "@coral-xyz/anchor";
import { ScaasLiquidity } from "../target/types/scaas_liquidity";
import { PublicKey, SystemProgram } from "@solana/web3.js";

async function main() {
  // Parse command line arguments
  const args = process.argv.slice(2);

  if (args.length === 0 || args[0] === "--help" || args[0] === "-h") {
    console.log(
      "Usage: yarn ts-node scripts/01-initialize-pool.ts <FEE_RATE_BPS>"
    );
    console.log();
    console.log("Arguments:");
    console.log("  FEE_RATE_BPS    Fee rate in basis points (0-1000)");
    console.log("                  Examples:");
    console.log("                    0    = 0% fee (1:1 swaps)");
    console.log("                    10   = 0.1% fee");
    console.log("                    100  = 1% fee");
    console.log("                    1000 = 10% fee (maximum)");
    console.log();
    console.log("Example:");
    console.log("  yarn ts-node scripts/01-initialize-pool.ts 0");
    console.log();
    console.log(
      "Note: Make sure Anchor.toml [provider] cluster is set to mainnet-beta"
    );
    process.exit(args.length === 0 ? 1 : 0);
  }

  const feeRateBps = parseInt(args[0], 10);

  if (isNaN(feeRateBps) || feeRateBps < 0 || feeRateBps > 1000) {
    console.error(
      "❌ Error: Fee rate must be a number between 0 and 1000 basis points"
    );
    console.error("   (0 = 0%, 100 = 1%, 1000 = 10%)");
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
  console.log("INITIALIZING LIQUIDITY POOL");
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

  console.log("Configuration:");
  console.log("- Program ID:", program.programId.toString());
  console.log("- Pool PDA:", pool.toString());
  console.log("- Whitelist PDA:", whitelist.toString());
  console.log("- Deployer/Authority:", payer.publicKey.toString());
  console.log();

  // Check if pool already exists
  try {
    const poolAccount = await program.account.liquidityPool.fetch(pool);
    console.log("❌ Pool already initialized!");
    console.log("Pool state:");
    console.log(
      "- Operations Authority:",
      poolAccount.operationsAuthority.toString()
    );
    console.log("- Pause Authority:", poolAccount.pauseAuthority.toString());
    console.log("- Fee Recipient:", poolAccount.feeRecipient.toString());
    console.log("- Fee Rate:", poolAccount.feeRate.toNumber(), "bps");
    console.log("- Supported Tokens:", poolAccount.supportedTokens.length);
    process.exit(0);
  } catch (e) {
    // Pool doesn't exist, continue with initialization
    console.log("✓ Pool not yet initialized, proceeding...");
  }

  // Use fee rate from command line argument
  const feeRate = new anchor.BN(feeRateBps);

  console.log();
  console.log("Initialization Parameters:");
  console.log(
    "- Fee Rate:",
    feeRate.toNumber(),
    `basis points (${feeRate.toNumber() / 100}%)`
  );
  console.log("- Operations Authority:", payer.publicKey.toString());
  console.log("- Pause Authority:", payer.publicKey.toString());
  console.log("- Fee Recipient:", payer.publicKey.toString());
  console.log();

  console.log("Sending transaction...");

  try {
    const tx = await program.methods
      .initialize(feeRate)
      .accounts({
        pool: pool,
        whitelist: whitelist,
        payer: payer.publicKey,
        operationsAuthority: payer.publicKey,
        pauseAuthority: payer.publicKey,
        feeRecipient: payer.publicKey,
        systemProgram: SystemProgram.programId,
      } as any)
      .rpc();

    console.log("✅ Pool initialized successfully!");
    console.log();
    console.log("Transaction Details:");
    console.log("- Signature:", tx);
    console.log("- Explorer:", `https://solscan.io/tx/${tx}`);
    console.log();

    // Fetch and display pool state
    const poolAccount = await program.account.liquidityPool.fetch(pool);
    const whitelistAccount = await program.account.addressWhitelist.fetch(
      whitelist
    );

    console.log("Pool State:");
    console.log(
      "- Operations Authority:",
      poolAccount.operationsAuthority.toString()
    );
    console.log("- Pause Authority:", poolAccount.pauseAuthority.toString());
    console.log("- Fee Recipient:", poolAccount.feeRecipient.toString());
    console.log("- Fee Rate:", poolAccount.feeRate.toNumber(), "bps");
    console.log("- Swaps Paused:", poolAccount.swapsPaused);
    console.log("- Liquidity Paused:", poolAccount.liquidityPaused);
    console.log("- Supported Tokens:", poolAccount.supportedTokens.length);
    console.log();

    console.log("Whitelist State:");
    console.log("- Enabled:", whitelistAccount.enabled);
    console.log("- Addresses:", whitelistAccount.addresses.length);
    console.log();

    console.log("=".repeat(60));
    console.log("SAVE THESE ADDRESSES:");
    console.log("=".repeat(60));
    console.log("Pool:", pool.toString());
    console.log("Whitelist:", whitelist.toString());
    console.log("=".repeat(60));
  } catch (error: any) {
    console.error("❌ Error initializing pool:");
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
