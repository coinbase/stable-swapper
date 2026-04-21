import * as anchor from "@coral-xyz/anchor";
import { Program } from "@coral-xyz/anchor";
import { ScaasLiquidity } from "../target/types/scaas_liquidity";
import { PublicKey } from "@solana/web3.js";

async function main() {
  // Parse command line arguments
  const args = process.argv.slice(2);

  if (args.length < 1 || args[0] === "--help" || args[0] === "-h") {
    console.log(
      "Usage: yarn ts-node scripts/whitelist-add.ts <ADDRESS> [ADDRESS2] [ADDRESS3] ..."
    );
    console.log();
    console.log("Arguments:");
    console.log(
      "  ADDRESS    Wallet address to add to whitelist (can specify multiple)"
    );
    console.log();
    console.log("Examples:");
    console.log("  # Add single address");
    console.log(
      "  yarn ts-node scripts/whitelist-add.ts 9TcjK2ToqoAtCr5jrLdDXNTNbZBbDQB1zy2BNGMr7nQE"
    );
    console.log();
    console.log("  # Add multiple addresses");
    console.log(
      "  yarn ts-node scripts/whitelist-add.ts 9TcjK2ToqoAtCr5jrLdDXNTNbZBbDQB1zy2BNGMr7nQE 13V7ou4zHHwDVaAGWxqHSwU2sVzRR4m62XWqCFxhA5fD"
    );
    process.exit(args.length < 1 ? 1 : 0);
  }

  // Validate addresses
  const addresses: PublicKey[] = [];
  for (const arg of args) {
    try {
      addresses.push(new PublicKey(arg));
    } catch (error) {
      console.error(`❌ Error: Invalid address: ${arg}`);
      process.exit(1);
    }
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
  console.log("ADD TO WHITELIST");
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

  console.log("Current Whitelist State:");
  console.log("- Enabled:", whitelistAccount.enabled);
  console.log("- Current Addresses:", whitelistAccount.addresses.length);
  whitelistAccount.addresses.forEach((addr, index) => {
    console.log(`  ${index + 1}. ${addr.toString()}`);
  });
  console.log();

  console.log(`Adding ${addresses.length} address(es) to whitelist:`);
  addresses.forEach((addr, index) => {
    console.log(`  ${index + 1}. ${addr.toString()}`);
  });
  console.log();

  // Add each address
  let successCount = 0;
  let skipCount = 0;

  for (const address of addresses) {
    // Check if already whitelisted
    if (whitelistAccount.addresses.some((addr) => addr.equals(address))) {
      console.log(`⏭️  Skipping ${address.toString()} - already whitelisted`);
      skipCount++;
      continue;
    }

    console.log(`Adding ${address.toString()}...`);

    try {
      const tx = await program.methods
        .addToWhitelist(address)
        .accounts({
          pool: pool,
          whitelist: whitelist,
          pauseAuthority: payer.publicKey,
        } as any)
        .rpc();

      console.log(`✅ Added successfully! Tx: ${tx}`);
      successCount++;
    } catch (error: any) {
      console.error(`❌ Error adding ${address.toString()}:`);
      console.error(error.message);

      if (error.logs) {
        console.error("Program Logs:");
        error.logs.forEach((log: string) => console.error(log));
      }
    }
  }

  console.log();
  console.log("=".repeat(60));
  console.log("Summary:");
  console.log(`- Successfully added: ${successCount}`);
  console.log(`- Already whitelisted: ${skipCount}`);
  console.log(`- Failed: ${addresses.length - successCount - skipCount}`);
  console.log("=".repeat(60));

  // Fetch updated whitelist
  const updatedWhitelist = await program.account.addressWhitelist.fetch(
    whitelist
  );
  console.log();
  console.log("Updated Whitelist:");
  console.log("- Total Addresses:", updatedWhitelist.addresses.length);
  updatedWhitelist.addresses.forEach((addr, index) => {
    console.log(`  ${index + 1}. ${addr.toString()}`);
  });
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
