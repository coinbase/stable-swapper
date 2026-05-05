import * as anchor from "@coral-xyz/anchor";
import { Program } from "@coral-xyz/anchor";
import { ScaasLiquidity } from "../target/types/scaas_liquidity";
import { PublicKey } from "@solana/web3.js";

async function main() {
  const args = process.argv.slice(2);

  if (args.length < 1 || args[0] === "--help" || args[0] === "-h") {
    console.log(
      "Usage: yarn ts-node scripts/update-configure-authority.ts <NEW_CONFIGURE_AUTHORITY>"
    );
    console.log();
    console.log(
      "Note: You must currently hold the role to rotate it (strict self-rotation)."
    );
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
  const current = poolAccount.configureAuthority;

  console.log("=".repeat(60));
  console.log("UPDATE CONFIGURE AUTHORITY");
  console.log("=".repeat(60));
  console.log("- Program ID:", program.programId.toString());
  console.log("- Pool PDA:", pool.toString());
  console.log("- Current Configure Authority:", current.toString());
  console.log("- Your Wallet:", payer.publicKey.toString());
  console.log("- New Configure Authority:", next.toString());

  if (!current.equals(payer.publicKey)) {
    console.error("❌ Error: You are not the current configure authority");
    process.exit(1);
  }
  if (current.equals(next)) {
    console.log("ℹ️  Configure Authority is already set to this address");
    process.exit(0);
  }

  console.log();
  console.log("Sending transaction...");
  const tx = await program.methods
    .updateConfigureAuthority(next)
    .accounts({
      pool,
      configureAuthority: payer.publicKey,
    } as any)
    .rpc();

  console.log("✅ Configure Authority rotated.");
  console.log("- Signature:", tx);
  console.log("- Explorer:", `https://solscan.io/tx/${tx}`);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
