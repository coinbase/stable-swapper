import * as anchor from "@coral-xyz/anchor";
import { Program } from "@coral-xyz/anchor";
import { ScaasLiquidity } from "../target/types/scaas_liquidity";
import { PublicKey } from "@solana/web3.js";
import {
  TOKEN_PROGRAM_ID,
  getAssociatedTokenAddress,
  getAccount,
} from "@solana/spl-token";

async function main() {
  // Parse command line arguments
  const args = process.argv.slice(2);

  if (args.length < 2 || args[0] === "--help" || args[0] === "-h") {
    console.log(
      "Usage: yarn ts-node scripts/03-deposit-liquidity.ts <TOKEN_MINT_ADDRESS> <AMOUNT>"
    );
    console.log();
    console.log("Arguments:");
    console.log(
      "  TOKEN_MINT_ADDRESS    The mint address of the token to deposit"
    );
    console.log(
      "  AMOUNT               Amount to deposit (in token units, not base units)"
    );
    console.log();
    console.log("Examples:");
    console.log("  # Deposit 10 custom tokens (6 decimals)");
    console.log(
      "  yarn ts-node scripts/03-deposit-liquidity.ts 9gJ94RYM3kUbFyKzzXAaGaRQ4n39XrDCLPZ1XnpZhnms 10"
    );
    console.log();
    console.log("  # Deposit 5 USDC (6 decimals)");
    console.log(
      "  yarn ts-node scripts/03-deposit-liquidity.ts EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v 5"
    );
    process.exit(args.length < 2 ? 1 : 0);
  }

  const mintAddress = args[0];
  const amountTokens = parseFloat(args[1]);

  // Validate mint address
  let mint: PublicKey;
  try {
    mint = new PublicKey(mintAddress);
  } catch (error) {
    console.error("❌ Error: Invalid mint address");
    process.exit(1);
  }

  // Validate amount
  if (isNaN(amountTokens) || amountTokens <= 0) {
    console.error("❌ Error: Amount must be a positive number");
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
  console.log("DEPOSITING LIQUIDITY");
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

  // Get operations authority token account
  const operationsAuthorityTokenAccount = await getAssociatedTokenAddress(
    mint,
    payer.publicKey
  );

  // Fetch mint info to get decimals
  const mintInfo = await provider.connection.getParsedAccountInfo(mint);
  if (!mintInfo.value || !("parsed" in mintInfo.value.data)) {
    console.error("❌ Error: Could not fetch mint info");
    process.exit(1);
  }
  const decimals = (mintInfo.value.data as any).parsed.info.decimals;
  const amountBaseUnits = new anchor.BN(amountTokens * Math.pow(10, decimals));

  console.log("Configuration:");
  console.log("- Program ID:", program.programId.toString());
  console.log("- Pool PDA:", pool.toString());
  console.log("- Token Mint:", mint.toString());
  console.log("- Token Decimals:", decimals);
  console.log("- Vault PDA:", vault.toString());
  console.log("- Vault Token Account:", vaultTokenAccount.toString());
  console.log("- Operations Authority:", payer.publicKey.toString());
  console.log(
    "- Operations Authority Token Account:",
    operationsAuthorityTokenAccount.toString()
  );
  console.log();

  console.log("Deposit Details:");
  console.log("- Amount (tokens):", amountTokens);
  console.log("- Amount (base units):", amountBaseUnits.toString());
  console.log();

  // Check balance before deposit
  try {
    const userTokenAccount = await getAccount(
      provider.connection,
      operationsAuthorityTokenAccount
    );
    const userBalance =
      Number(userTokenAccount.amount) / Math.pow(10, decimals);
    console.log("Your Balance:", userBalance, "tokens");

    if (userBalance < amountTokens) {
      console.error("❌ Error: Insufficient balance");
      console.error(
        `   You have ${userBalance} tokens but trying to deposit ${amountTokens}`
      );
      process.exit(1);
    }
  } catch (error) {
    console.error(
      "❌ Error: Could not fetch your token account. Do you have this token?"
    );
    process.exit(1);
  }

  // Check vault balance before
  let vaultBalanceBefore = 0;
  try {
    const vaultAccount = await getAccount(
      provider.connection,
      vaultTokenAccount
    );
    vaultBalanceBefore = Number(vaultAccount.amount) / Math.pow(10, decimals);
    console.log("Vault Balance Before:", vaultBalanceBefore, "tokens");
  } catch (error) {
    console.log("Vault Balance Before: 0 tokens (new vault)");
  }
  console.log();

  console.log("Sending transaction...");

  try {
    const tx = await program.methods
      .depositLiquidity(amountBaseUnits)
      .accounts({
        pool: pool,
        vault: vault,
        vaultTokenAccount: vaultTokenAccount,
        operationsAuthorityTokenAccount: operationsAuthorityTokenAccount,
        mint: mint,
        operationsAuthority: payer.publicKey,
        tokenProgram: TOKEN_PROGRAM_ID,
      } as any)
      .rpc();

    console.log("✅ Liquidity deposited successfully!");
    console.log();
    console.log("Transaction Details:");
    console.log("- Signature:", tx);
    console.log("- Explorer:", `https://solscan.io/tx/${tx}`);
    console.log();

    // Check vault balance after
    const vaultAccount = await getAccount(
      provider.connection,
      vaultTokenAccount
    );
    const vaultBalanceAfter =
      Number(vaultAccount.amount) / Math.pow(10, decimals);

    console.log("Vault Balance After:", vaultBalanceAfter, "tokens");
    console.log(
      "Amount Deposited:",
      vaultBalanceAfter - vaultBalanceBefore,
      "tokens"
    );
    console.log();

    console.log("=".repeat(60));
    console.log("✅ Deposit complete!");
    console.log("=".repeat(60));
  } catch (error: any) {
    console.error("❌ Error depositing liquidity:");
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
