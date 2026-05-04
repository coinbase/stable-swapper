import * as anchor from "@coral-xyz/anchor";
import { Program } from "@coral-xyz/anchor";
import { ScaasLiquidity } from "../target/types/scaas_liquidity";
import { PublicKey } from "@solana/web3.js";

async function main() {
  const args = process.argv.slice(2);
  if (args.length < 1 || args[0] === "--help" || args[0] === "-h") {
    console.log(
      "Usage: yarn ts-node scripts/update-withdraw-recipient.ts <NEW_WITHDRAW_RECIPIENT>"
    );
    console.log();
    console.log(
      "The withdraw recipient is the wallet that owns the only token"
    );
    console.log(
      "account `withdraw_liquidity` is allowed to send funds to. Only the"
    );
    console.log("Configure Authority (cold key) can rotate it.");
    process.exit(args.length < 1 ? 1 : 0);
  }

  let next: PublicKey;
  try {
    next = new PublicKey(args[0]);
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
  console.log("UPDATE WITHDRAW RECIPIENT");
  console.log("=".repeat(60));
  console.log("- Pool PDA:", pool.toString());
  console.log(
    "- Configure Authority:",
    poolAccount.configureAuthority.toString()
  );
  console.log(
    "- Current Withdraw Recipient:",
    poolAccount.withdrawRecipient.toString()
  );
  console.log("- Your Wallet:", payer.publicKey.toString());
  console.log("- New Withdraw Recipient:", next.toString());

  if (!poolAccount.configureAuthority.equals(payer.publicKey)) {
    console.error("❌ Error: You are not the configure authority");
    process.exit(1);
  }
  if (poolAccount.withdrawRecipient.equals(next)) {
    console.log("ℹ️  Withdraw recipient is already set to this address");
    process.exit(0);
  }

  console.log();
  console.log("Sending transaction...");
  const tx = await program.methods
    .updateWithdrawRecipient(next)
    .accounts({
      pool,
      configureAuthority: payer.publicKey,
    } as any)
    .rpc();
  console.log("✅ Withdraw recipient updated.");
  console.log("- Signature:", tx);
  console.log("- Explorer:", `https://solscan.io/tx/${tx}`);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
