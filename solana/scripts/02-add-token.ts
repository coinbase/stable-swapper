import * as anchor from "@coral-xyz/anchor";
import { Program } from "@coral-xyz/anchor";
import { ScaasLiquidity } from "../target/types/scaas_liquidity";
import { PublicKey, SystemProgram } from "@solana/web3.js";
import {
  TOKEN_PROGRAM_ID,
  ASSOCIATED_TOKEN_PROGRAM_ID,
  getAssociatedTokenAddress,
} from "@solana/spl-token";

async function main() {
  // Parse command line arguments
  const args = process.argv.slice(2);

  if (args.length === 0 || args[0] === "--help" || args[0] === "-h") {
    console.log(
      "Usage: yarn ts-node scripts/02-add-token.ts <TOKEN_MINT_ADDRESS>"
    );
    console.log();
    console.log("Arguments:");
    console.log("  TOKEN_MINT_ADDRESS    The mint address of the token to add");
    console.log();
    console.log("Examples:");
    console.log("  # Add custom token");
    console.log(
      "  yarn ts-node scripts/02-add-token.ts 9gJ94RYM3kUbFyKzzXAaGaRQ4n39XrDCLPZ1XnpZhnms"
    );
    console.log();
    console.log("  # Add USDC");
    console.log(
      "  yarn ts-node scripts/02-add-token.ts EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v"
    );
    process.exit(args.length === 0 ? 1 : 0);
  }

  const mintAddress = args[0];

  // Validate mint address
  let mint: PublicKey;
  try {
    mint = new PublicKey(mintAddress);
  } catch (error) {
    console.error("❌ Error: Invalid mint address");
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
  console.log("ADDING TOKEN TO POOL");
  console.log("=".repeat(60));
  console.log();

  // Derive PDAs
  const [pool] = PublicKey.findProgramAddressSync(
    [Buffer.from("liquidity_pool")],
    program.programId
  );

  const [vault] = PublicKey.findProgramAddressSync(
    [Buffer.from("token_vault"), pool.toBuffer(), mint.toBuffer()],
    program.programId
  );

  const [vaultTokenAccount] = PublicKey.findProgramAddressSync(
    [Buffer.from("vault_token_account"), vault.toBuffer()],
    program.programId
  );

  // Get fee recipient ATA
  const feeRecipientTokenAccount = await getAssociatedTokenAddress(
    mint,
    payer.publicKey
  );

  console.log("Configuration:");
  console.log("- Program ID:", program.programId.toString());
  console.log("- Pool PDA:", pool.toString());
  console.log("- Token Mint:", mint.toString());
  console.log("- Vault PDA:", vault.toString());
  console.log("- Vault Token Account:", vaultTokenAccount.toString());
  console.log(
    "- Fee Recipient Token Account:",
    feeRecipientTokenAccount.toString()
  );
  console.log("- Configure Authority:", payer.publicKey.toString());
  console.log();

  // Check if token already exists
  try {
    const poolAccount = await program.account.liquidityPool.fetch(pool);
    const tokenExists = poolAccount.supportedTokens.some(
      (tokenMint) => tokenMint.toString() === mint.toString()
    );

    if (tokenExists) {
      console.log("❌ Token already added to pool!");
      console.log();
      console.log("Supported tokens:");
      poolAccount.supportedTokens.forEach((tokenMint, index) => {
        console.log(`  ${index + 1}. ${tokenMint.toString()}`);
      });
      process.exit(0);
    }

    console.log("✓ Token not yet added, proceeding...");
    console.log();
  } catch (e) {
    console.error("❌ Error: Pool not initialized");
    process.exit(1);
  }

  console.log("Sending transaction...");

  try {
    const tx = await program.methods
      .addSupportedToken()
      .accounts({
        pool: pool,
        vault: vault,
        vaultTokenAccount: vaultTokenAccount,
        feeRecipientTokenAccount: feeRecipientTokenAccount,
        feeRecipient: payer.publicKey,
        mint: mint,
        configureAuthority: payer.publicKey,
        tokenProgram: TOKEN_PROGRAM_ID,
        associatedTokenProgram: ASSOCIATED_TOKEN_PROGRAM_ID,
        systemProgram: SystemProgram.programId,
        rent: anchor.web3.SYSVAR_RENT_PUBKEY,
      } as any)
      .rpc();

    console.log("✅ Token added successfully!");
    console.log();
    console.log("Transaction Details:");
    console.log("- Signature:", tx);
    console.log("- Explorer:", `https://solscan.io/tx/${tx}`);
    console.log();

    // Fetch and display updated pool state
    const poolAccount = await program.account.liquidityPool.fetch(pool);

    console.log("Updated Pool State:");
    console.log(
      "- Supported Tokens Count:",
      poolAccount.supportedTokens.length
    );
    console.log("- Supported Tokens:");
    poolAccount.supportedTokens.forEach((tokenMint, index) => {
      console.log(`  ${index + 1}. ${tokenMint.toString()}`);
    });
    console.log();

    console.log("=".repeat(60));
    console.log("SAVE THESE ADDRESSES:");
    console.log("=".repeat(60));
    console.log("Token Mint:", mint.toString());
    console.log("Vault:", vault.toString());
    console.log("Vault Token Account:", vaultTokenAccount.toString());
    console.log(
      "Fee Recipient Token Account:",
      feeRecipientTokenAccount.toString()
    );
    console.log("=".repeat(60));
  } catch (error: any) {
    console.error("❌ Error adding token:");
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
