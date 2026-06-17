import * as anchor from "@coral-xyz/anchor";
import { Program } from "@coral-xyz/anchor";
import { ScaasLiquidity } from "../target/types/scaas_liquidity";
import { PublicKey } from "@solana/web3.js";

async function main() {
  const args = process.argv.slice(2);
  if (args.length < 1 || args[0] === "--help" || args[0] === "-h") {
    console.log(
      "Usage: yarn ts-node scripts/remove-withdraw-recipient.ts <WITHDRAW_RECIPIENT>"
    );
    console.log();
    console.log(
      "Removes an owner from the withdraw allowlist. Only the Configure Authority"
    );
    console.log(
      "(cold key) can change the list. Removing the last entry blocks all withdraws"
    );
    console.log("until a new recipient is added.");
    process.exit(args.length < 1 ? 1 : 0);
  }

  let recipient: PublicKey;
  try {
    recipient = new PublicKey(args[0]);
  } catch {
    console.error(`❌ Error: Invalid address: ${args[0]}`);
    process.exit(1);
  }

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
  const poolAccount = await program.account.liquidityPool.fetch(pool);

  console.log("=".repeat(60));
  console.log("REMOVE WITHDRAW RECIPIENT");
  console.log("=".repeat(60));
  console.log("- Pool PDA:", pool.toString());
  console.log(
    "- Configure Authority:",
    poolAccount.configureAuthority.toString()
  );
  console.log(
    "- Current Allowlist:",
    poolAccount.withdrawRecipients.map((r) => r.toString())
  );
  console.log("- Your Wallet:", payer.publicKey.toString());
  console.log("- Recipient to remove:", recipient.toString());

  if (!poolAccount.configureAuthority.equals(payer.publicKey)) {
    console.error("❌ Error: You are not the configure authority");
    process.exit(1);
  }
  if (!poolAccount.withdrawRecipients.some((r) => r.equals(recipient))) {
    console.log("ℹ️  Recipient is not on the allowlist");
    process.exit(0);
  }
  if (poolAccount.withdrawRecipients.length === 1) {
    console.log(
      "⚠️  This is the last allowlisted recipient. Removing it will block all"
    );
    console.log("    withdraws until a new recipient is added.");
  }

  console.log();
  console.log("Sending transaction...");
  const tx = await program.methods
    .removeWithdrawRecipient(recipient)
    .accounts({
      pool,
      configureAuthority: payer.publicKey,
    } as any)
    .rpc();
  console.log("✅ Withdraw recipient removed.");
  console.log("- Signature:", tx);
  console.log("- Explorer:", `https://solscan.io/tx/${tx}`);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
