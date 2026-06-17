import * as anchor from "@coral-xyz/anchor";
import { Program } from "@coral-xyz/anchor";
import { ScaasLiquidity } from "../target/types/scaas_liquidity";
import { PublicKey } from "@solana/web3.js";

async function main() {
  const args = process.argv.slice(2);
  if (args.length < 1 || args[0] === "--help" || args[0] === "-h") {
    console.log(
      "Usage: yarn ts-node scripts/add-withdraw-recipient.ts <WITHDRAW_RECIPIENT>"
    );
    console.log();
    console.log(
      "Adds an owner to the withdraw allowlist. The Treasury Authority may only"
    );
    console.log(
      "withdraw to a token account owned by an allowlisted address. Only the"
    );
    console.log("Configure Authority (cold key) can change the list.");
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
  console.log("ADD WITHDRAW RECIPIENT");
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
  console.log("- Recipient to add:", recipient.toString());

  if (!poolAccount.configureAuthority.equals(payer.publicKey)) {
    console.error("❌ Error: You are not the configure authority");
    process.exit(1);
  }
  if (poolAccount.withdrawRecipients.some((r) => r.equals(recipient))) {
    console.log("ℹ️  Recipient is already on the allowlist");
    process.exit(0);
  }

  console.log();
  console.log("Sending transaction...");
  const tx = await program.methods
    .addWithdrawRecipient(recipient)
    .accounts({
      pool,
      configureAuthority: payer.publicKey,
    } as any)
    .rpc();
  console.log("✅ Withdraw recipient added.");
  console.log("- Signature:", tx);
  console.log("- Explorer:", `https://solscan.io/tx/${tx}`);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
