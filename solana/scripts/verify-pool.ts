import * as anchor from "@coral-xyz/anchor";
import { Program } from "@coral-xyz/anchor";
import { ScaasLiquidity } from "../target/types/scaas_liquidity";
import { PublicKey } from "@solana/web3.js";
import { getAccount } from "@solana/spl-token";

async function main() {
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

  const program = anchor.workspace.scaasLiquidity as Program<ScaasLiquidity>;

  // Derive PDAs
  const [pool] = PublicKey.findProgramAddressSync(
    [Buffer.from("liquidity_pool")],
    program.programId
  );

  console.log("=".repeat(60));
  console.log("POOL STATE VERIFICATION");
  console.log("=".repeat(60));
  console.log();

  console.log("Addresses:");
  console.log("- Program ID:", program.programId.toString());
  console.log("- Pool PDA:", pool.toString());
  console.log();

  try {
    // Fetch pool state
    const poolAccount = await program.account.liquidityPool.fetch(pool);

    console.log("Pool Configuration:");
    console.log("- Pause Authority:", poolAccount.pauseAuthority.toString());
    console.log(
      "- Unpause Authority:",
      poolAccount.unpauseAuthority.toString()
    );
    console.log(
      "- Treasury Authority:",
      poolAccount.treasuryAuthority.toString()
    );
    console.log(
      "- Configure Authority:",
      poolAccount.configureAuthority.toString()
    );
    console.log("- Fee Recipient:", poolAccount.feeRecipient.toString());
    console.log(
      "- Withdraw Recipient:",
      poolAccount.withdrawRecipient.toString()
    );
    console.log(
      "- Fee Rate:",
      poolAccount.feeRate.toNumber(),
      "bps (" + poolAccount.feeRate.toNumber() / 100 + "%)"
    );
    console.log("- Swaps Paused:", poolAccount.swapsPaused);
    console.log("- Liquidity Paused:", poolAccount.liquidityPaused);
    console.log();

    console.log("Supported Tokens:");
    console.log("- Count:", poolAccount.supportedTokens.length);
    console.log();

    if (poolAccount.supportedTokens.length > 0) {
      for (let index = 0; index < poolAccount.supportedTokens.length; index++) {
        const mint = poolAccount.supportedTokens[index];
        console.log(`Token ${index + 1}:`);
        console.log(`- Mint: ${mint.toString()}`);

        // Derive vault PDA
        const [vault] = PublicKey.findProgramAddressSync(
          [Buffer.from("token_vault"), pool.toBuffer(), mint.toBuffer()],
          program.programId
        );

        // Derive vault token account PDA
        const [vaultTokenAccount] = PublicKey.findProgramAddressSync(
          [Buffer.from("vault_token_account"), vault.toBuffer()],
          program.programId
        );

        try {
          // Fetch vault state
          const vaultAccount = await program.account.tokenVault.fetch(vault);

          // Fetch mint info for decimals
          const mintInfo = await provider.connection.getParsedAccountInfo(mint);
          let decimals = 0;
          if (mintInfo.value && "parsed" in mintInfo.value.data) {
            decimals = (mintInfo.value.data as any).parsed.info.decimals;
          }

          // Fetch vault token account balance
          const vaultTokenAccountInfo = await getAccount(
            provider.connection,
            vaultTokenAccount
          );
          const balance =
            Number(vaultTokenAccountInfo.amount) / Math.pow(10, decimals);

          console.log(`- Vault: ${vault.toString()}`);
          console.log(`- Vault Token Account: ${vaultTokenAccount.toString()}`);
          console.log(`- Decimals: ${decimals}`);
          console.log(`- Total Balance: ${balance.toLocaleString()} tokens`);
          console.log(`- Disabled: ${vaultAccount.disabled}`);
        } catch (error: any) {
          console.log(`- Error fetching vault info: ${error.message}`);
        }
        console.log();
      }
    } else {
      console.log();
    }

    console.log("=".repeat(60));
    console.log("✅ Pool verification complete!");
    console.log("=".repeat(60));
  } catch (error: any) {
    console.error("❌ Error fetching pool state:");
    console.error(error.message);

    if (error.message.includes("Account does not exist")) {
      console.error("\nThe pool has not been initialized yet.");
      console.error("Run: yarn ts-node scripts/01-initialize-pool.ts 0");
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
