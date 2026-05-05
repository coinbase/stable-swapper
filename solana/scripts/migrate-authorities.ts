import * as anchor from "@coral-xyz/anchor";
import { Program } from "@coral-xyz/anchor";
import { ScaasLiquidity } from "../target/types/scaas_liquidity";
import { PublicKey, SystemProgram } from "@solana/web3.js";

// On-chain layout sizes (must stay in sync with the local `LEGACY_INIT_SPACE` in
// `do_migrate_authorities` and `LiquidityPool::INIT_SPACE` in
// `programs/scaas-liquidity/src/{lib,state}.rs`):
//   pre-migration : 8 disc + 32*3 + (4 + 32*MAX_SUPPORTED_TOKENS) + 8 + 1 + 1 + 1 = 1719
//   post-migration: 8 disc + 32*6 + (4 + 32*MAX_SUPPORTED_TOKENS) + 8 + 1 + 1 + 1 = 1815
const LEGACY_POOL_SIZE = 1719;
const NEW_POOL_SIZE = 1815;

/**
 * One-shot migration of an existing legacy pool (operations + pause authority
 * layout) to the new role-based layout. Co-signed by the legacy operations
 * authority (the wallet running this script, pays the realloc rent diff) and
 * the legacy pause authority (passed as `--legacy-pause`, must sign separately
 * via the multi-sig flow used at deploy time).
 *
 * The script prints the unsigned transaction in base64 if --build-only is
 * passed so it can be co-signed offline by a cold wallet.
 *
 * Pre-flight: asserts the on-chain pool data length is exactly LEGACY_POOL_SIZE
 * before submitting. Post-submit: asserts the new size matches NEW_POOL_SIZE
 * and all six pubkey fields equal the args.
 */
async function main() {
  const args = process.argv.slice(2);
  const params: Record<string, string> = {};
  let buildOnly = false;
  for (let i = 0; i < args.length; i++) {
    if (args[i] === "--help" || args[i] === "-h") {
      printUsage();
      process.exit(0);
    } else if (args[i] === "--build-only") {
      buildOnly = true;
    } else if (args[i].startsWith("--")) {
      params[args[i].slice(2)] = args[i + 1];
      i += 1;
    }
  }

  const required = [
    "pause",
    "unpause",
    "treasury",
    "configure",
    "withdraw-recipient",
    "legacy-pause",
  ];
  for (const k of required) {
    if (!params[k]) {
      console.error(`❌ Error: missing --${k}`);
      printUsage();
      process.exit(1);
    }
  }

  const newPause = new PublicKey(params["pause"]);
  const newUnpause = new PublicKey(params["unpause"]);
  const newTreasury = new PublicKey(params["treasury"]);
  const newConfigure = new PublicKey(params["configure"]);
  const newWithdrawRecipient = new PublicKey(params["withdraw-recipient"]);
  const legacyPause = new PublicKey(params["legacy-pause"]);

  if (!process.env.ANCHOR_PROVIDER_URL) {
    process.env.ANCHOR_PROVIDER_URL = "https://api.mainnet-beta.solana.com";
  }
  if (!process.env.ANCHOR_WALLET) {
    process.env.ANCHOR_WALLET =
      require("os").homedir() + "/.config/solana/id.json";
  }

  const provider = anchor.AnchorProvider.env();
  anchor.setProvider(provider);
  const payer = provider.wallet as anchor.Wallet;
  const program = anchor.workspace.scaasLiquidity as Program<ScaasLiquidity>;

  const [pool] = PublicKey.findProgramAddressSync(
    [Buffer.from("liquidity_pool")],
    program.programId
  );

  console.log("=".repeat(60));
  console.log("MIGRATE AUTHORITIES (LEGACY -> ROLE-BASED)");
  console.log("=".repeat(60));
  console.log("- Program ID:", program.programId.toString());
  console.log("- Pool PDA:", pool.toString());
  console.log(
    "- Legacy operations authority (signer/payer):",
    payer.publicKey.toString()
  );
  console.log("- Legacy pause authority (cosigner):", legacyPause.toString());
  console.log();
  console.log("Will set:");
  console.log("- pause_authority    =", newPause.toString());
  console.log("- unpause_authority  =", newUnpause.toString());
  console.log("- treasury_authority =", newTreasury.toString());
  console.log("- configure_authority=", newConfigure.toString());
  console.log("- withdraw_recipient =", newWithdrawRecipient.toString());
  console.log();

  // Pre-flight: ensure the on-chain pool is exactly the legacy size. If it isn't, the
  // on-chain `migrate_authorities` will return AlreadyMigrated, but bailing here gives a
  // much clearer signal to the operator (and avoids burning a co-signing round-trip).
  const preInfo = await provider.connection.getAccountInfo(pool);
  if (!preInfo) {
    console.error(`❌ Error: pool account ${pool.toString()} does not exist`);
    process.exit(1);
  }
  if (!preInfo.owner.equals(program.programId)) {
    console.error(
      `❌ Error: pool account is owned by ${preInfo.owner.toString()}, ` +
        `expected ${program.programId.toString()}`
    );
    process.exit(1);
  }
  if (preInfo.data.length !== LEGACY_POOL_SIZE) {
    console.error(
      `❌ Error: pool account size is ${preInfo.data.length} bytes, ` +
        `expected ${LEGACY_POOL_SIZE} (legacy layout). ` +
        (preInfo.data.length === NEW_POOL_SIZE
          ? "Pool appears to already be migrated."
          : "Pool layout does not match the migration assumptions; abort.")
    );
    process.exit(1);
  }
  console.log(
    `✓ Pre-flight: pool is ${preInfo.data.length} bytes (legacy layout).`
  );
  console.log();

  const ix = await program.methods
    .migrateAuthorities(
      newPause,
      newUnpause,
      newTreasury,
      newConfigure,
      newWithdrawRecipient
    )
    .accounts({
      pool,
      legacyOperationsAuthority: payer.publicKey,
      legacyPauseAuthority: legacyPause,
      systemProgram: SystemProgram.programId,
    } as any)
    .instruction();

  const blockhash = await provider.connection.getLatestBlockhash();
  const tx = new anchor.web3.Transaction({
    feePayer: payer.publicKey,
    recentBlockhash: blockhash.blockhash,
  }).add(ix);

  if (buildOnly) {
    console.log("Unsigned transaction (base64):");
    console.log(
      tx
        .serialize({ requireAllSignatures: false, verifySignatures: false })
        .toString("base64")
    );
    console.log();
    console.log("Sign with the legacy pause authority offline, then submit.");
    process.exit(0);
  }

  console.log("Sending transaction...");
  const sig = await provider.sendAndConfirm(tx, [payer.payer]);
  console.log("✅ Migration submitted.");
  console.log("- Signature:", sig);
  console.log("- Explorer:", `https://solscan.io/tx/${sig}`);
  console.log();

  // Post-submit: confirm on-chain state matches what we asked for.
  const postInfo = await provider.connection.getAccountInfo(pool);
  if (!postInfo) {
    console.error("❌ Post-check failed: pool account no longer exists");
    process.exit(1);
  }
  if (postInfo.data.length !== NEW_POOL_SIZE) {
    console.error(
      `❌ Post-check failed: pool size is ${postInfo.data.length}, ` +
        `expected ${NEW_POOL_SIZE}`
    );
    process.exit(1);
  }
  const poolAccount = await program.account.liquidityPool.fetch(pool);
  const expected: [string, PublicKey, PublicKey][] = [
    ["pause_authority", poolAccount.pauseAuthority, newPause],
    ["unpause_authority", poolAccount.unpauseAuthority, newUnpause],
    ["treasury_authority", poolAccount.treasuryAuthority, newTreasury],
    ["configure_authority", poolAccount.configureAuthority, newConfigure],
    ["withdraw_recipient", poolAccount.withdrawRecipient, newWithdrawRecipient],
  ];
  let mismatch = false;
  for (const [name, actual, want] of expected) {
    if (!actual.equals(want)) {
      console.error(
        `❌ Post-check: ${name} = ${actual.toString()}, expected ${want.toString()}`
      );
      mismatch = true;
    }
  }
  if (mismatch) {
    process.exit(1);
  }
  console.log(
    `✓ Post-check: pool is ${postInfo.data.length} bytes and all six fields match args.`
  );
}

function printUsage() {
  console.log(
    "Usage: yarn ts-node scripts/migrate-authorities.ts \\\n" +
      "  --pause <PUBKEY> --unpause <PUBKEY> --treasury <PUBKEY> \\\n" +
      "  --configure <PUBKEY> --withdraw-recipient <PUBKEY> \\\n" +
      "  --legacy-pause <PUBKEY> [--build-only]"
  );
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
