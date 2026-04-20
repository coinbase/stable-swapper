# USDF Token Details

- **Token Name**: USDF
- **Network**: Solana (Mainnet)
- **Mint Address**: 5AMAA9JV9H97YYVxx8F6FsCMmTwXSuTTQneiup4RYAUQ
- **Decimals**: 6
- **Supply**: Fixed initial mint (~10,000 USDF) for testing
- **Backing**: Unbacked for testing phase, with full 1:1 backing and reserve management enabled in the full production release


# Custom Stablecoin Swap

## Overview

This document provides instructions for interacting with the stablecoin liquidity pool swap instruction for the custom stablecoin program on Solana.

## Understanding Solana Transactions & Instructions

### Key Concepts

A Solana **transaction** contains one or more **instructions**. Each instruction requires:

1. **Program ID**: The address of the on-chain program to execute
2. **Accounts**: All accounts the instruction needs to read from or write to
3. **Instruction Data**: The parameters (arguments) for the instruction

### Account Types in Solana

- **Signer**: Account that must sign the transaction (e.g., user wallet)
- **Writable**: Account that will be modified by the instruction
- **Read-only**: Account that is only read from

---

## Program Details

**Program ID**: `pqgqKahpG1y2wsgxFhzaAnkV1cL9vk8MSg9qm4q646F`

**Network**: Mainnet

---

## Swap Instruction

### Purpose

The `swap` instruction allows users to exchange one supported token for another at a 1:1 ratio (accounting for decimal normalization).

**Key Features:**
- Supports swapping tokens to **any destination token account**, not just the signer's account
- Destination token account must exist before the swap executes (can be created in the same transaction before the swap instruction - see examples)

### Parameters

```typescript
{
  amount_in: u64,        // Amount of input tokens to swap (in token's native decimals)
  min_amount_out: u64    // Minimum acceptable output tokens (slippage protection)
}
```

### Required Accounts

| Account | Type | Description |
|---------|------|-------------|
| `pool` | Read-only | Liquidity pool PDA (derived from seed `"liquidity_pool"`) |
| `inVault` | Read-only | Token vault for input token |
| `outVault` | Read-only | Token vault for output token |
| `inVaultTokenAccount` | Writable | Token account holding input token reserves |
| `outVaultTokenAccount` | Writable | Token account holding output token reserves |
| `userFromTokenAccount` | Writable | User's token account for input token |
| `toTokenAccount` | Writable | Destination token account for output token |
| `feeRecipientTokenAccount` | Writable | Fee recipient's token account for input token |
| `feeRecipient` | Read-only | Fee recipient authority (validated against pool) |
| `fromMint` | Read-only | Mint address of input token |
| `toMint` | Read-only | Mint address of output token |
| `user` | Signer, Writable | User wallet signing the transaction |
| `whitelist` | Read-only | Address whitelist PDA |
| `tokenProgram` | Read-only | SPL Token Program |
| `associatedTokenProgram` | Read-only | Associated Token Program |
| `systemProgram` | Read-only | System Program |

**Constant Addresses (same for all swaps):**

- **Pool PDA**: `CrDL9SoCyW1tBgn8k7rgGSpWhnszneWDbvKvqPAU4PL9`

- **Whitelist PDA**: `24UrnpmHQWUgTYjovHWySFg1JT4AXUCUp4Ly25C25GNj`

- **Token Program**: `TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA`

- **Associated Token Program**: `ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL`

- **System Program**: `11111111111111111111111111111111`

---

## TypeScript/JavaScript Example

### Prerequisites

**1. Install Dependencies**
```bash
npm install @coral-xyz/anchor @solana/web3.js @solana/spl-token
npm install --save-dev ts-node typescript @types/node
```

**2. Create `tsconfig.json`**
```json
{
  "compilerOptions": {
    "target": "ES2020",
    "module": "commonjs",
    "esModuleInterop": true,
    "resolveJsonModule": true,
    "skipLibCheck": true,
    "strict": true
  }
}
```

**3. Run TypeScript Files**
```bash
npx ts-node your-script.ts
```

### Getting the IDL

The program's IDL (Interface Definition Language) is published on-chain. You need it to interact with the program.

**Option 1: Fetch using Anchor CLI**
```bash
anchor idl fetch pqgqKahpG1y2wsgxFhzaAnkV1cL9vk8MSg9qm4q646F \
  --provider.cluster mainnet > scaas_liquidity.json
```

This will save the IDL directly to `scaas_liquidity.json` in your current directory.

**Option 2: View on Explorer**

Visit: https://www.orbmarkets.io/address/pqgqKahpG1y2wsgxFhzaAnkV1cL9vk8MSg9qm4q646F/anchor-idl

### Setup

**Important:** Before running any swap, verify your `ANCHOR_WALLET` environment variable points to the correct wallet (e.g., `~/.config/solana/your-wallet.json`).

The following setup code should be placed at the top of your TypeScript file:

```typescript
import * as anchor from "@coral-xyz/anchor";
import { Program, AnchorProvider } from "@coral-xyz/anchor";
import { PublicKey } from "@solana/web3.js";
import {
  TOKEN_PROGRAM_ID,
  ASSOCIATED_TOKEN_PROGRAM_ID,
  getAssociatedTokenAddress,
  getAccount,
  createAssociatedTokenAccountInstruction
} from "@solana/spl-token";
import idl from "./scaas_liquidity.json"; // The IDL JSON file you fetched

// Set environment variables for Anchor provider
if (!process.env.ANCHOR_PROVIDER_URL) {
  process.env.ANCHOR_PROVIDER_URL = "https://api.mainnet-beta.solana.com";
}
if (!process.env.ANCHOR_WALLET) {
  process.env.ANCHOR_WALLET = require('os').homedir() + "/.config/solana/id.json";
}

// Initialize provider and program
const provider = anchor.AnchorProvider.env();
anchor.setProvider(provider);

// Create program instance with the IDL (program ID is in the IDL)
const program = new Program(idl as anchor.Idl, provider);
```

### Example: Swap USDC for Custom Token

This example swaps **0.1 USDC** (10 cents) for the custom token. Adjust the amount for your needs.

**File:** `swap_usdc_to_custom.ts`

Combine the Setup code above with this example in a single file:

```typescript
async function swapUsdcForCustomToken() {
  // Define swap parameters - swapping 0.1 USDC
  const swapAmount = new anchor.BN(0.1 * 10**6); // 0.1 USDC (6 decimals)
  const minAmountOut = new anchor.BN(0.09 * 10**6); // 10% slippage tolerance

  // Token mints
  const usdcMint = new PublicKey("EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v");
  const customTokenMint = new PublicKey("5AMAA9JV9H97YYVxx8F6FsCMmTwXSuTTQneiup4RYAUQ");

  // Derive PDAs
  const [pool] = PublicKey.findProgramAddressSync(
    [Buffer.from("liquidity_pool")],
    program.programId
  );

  const [usdcVault] = PublicKey.findProgramAddressSync(
    [Buffer.from("token_vault"), pool.toBuffer(), usdcMint.toBuffer()],
    program.programId
  );

  const [customTokenVault] = PublicKey.findProgramAddressSync(
    [Buffer.from("token_vault"), pool.toBuffer(), customTokenMint.toBuffer()],
    program.programId
  );

  const [usdcVaultTokenAccount] = PublicKey.findProgramAddressSync(
    [Buffer.from("vault_token_account"), usdcVault.toBuffer()],
    program.programId
  );

  const [customTokenVaultTokenAccount] = PublicKey.findProgramAddressSync(
    [Buffer.from("vault_token_account"), customTokenVault.toBuffer()],
    program.programId
  );

  const [whitelist] = PublicKey.findProgramAddressSync(
    [Buffer.from("address_whitelist")],
    program.programId
  );

  // Get user's token accounts (ATAs)
  const userUsdcAccount = await getAssociatedTokenAddress(
    usdcMint,
    provider.wallet.publicKey
  );

  const userCustomTokenAccount = await getAssociatedTokenAddress(
    customTokenMint,
    provider.wallet.publicKey
  );

  // Fetch pool account to get fee recipient
  const poolAccount = await (program.account as any).liquidityPool.fetch(pool);

  // Get fee recipient's USDC token account (fee is in input token)
  const feeRecipientUsdcAccount = await getAssociatedTokenAddress(
    usdcMint,
    poolAccount.feeRecipient
  );

  // Check if destination token account exists
  let needsAccountCreation = false;
  try {
    await getAccount(provider.connection, userCustomTokenAccount);
  } catch (error) {
    needsAccountCreation = true;
  }

  // Build swap instruction
  const swapIx = await program.methods
    .swap(swapAmount, minAmountOut)
    .accounts({
      pool: pool,
      inVault: usdcVault,
      outVault: customTokenVault,
      inVaultTokenAccount: usdcVaultTokenAccount,
      outVaultTokenAccount: customTokenVaultTokenAccount,
      userFromTokenAccount: userUsdcAccount,
      toTokenAccount: userCustomTokenAccount,
      feeRecipientTokenAccount: feeRecipientUsdcAccount,
      feeRecipient: poolAccount.feeRecipient,
      fromMint: usdcMint,
      toMint: customTokenMint,
      user: provider.wallet.publicKey,
      whitelist: whitelist,
      tokenProgram: TOKEN_PROGRAM_ID,
      associatedTokenProgram: ASSOCIATED_TOKEN_PROGRAM_ID,
      systemProgram: anchor.web3.SystemProgram.programId,
    } as any)
    .instruction();

  // Build transaction with optional account creation
  const transaction = new anchor.web3.Transaction();

  if (needsAccountCreation) {
    const createAtaIx = createAssociatedTokenAccountInstruction(
      provider.wallet.publicKey,
      userCustomTokenAccount,
      provider.wallet.publicKey,
      customTokenMint
    );
    transaction.add(createAtaIx);
  }

  transaction.add(swapIx);

  // Send transaction
  const tx = await provider.sendAndConfirm(transaction);

  console.log("Swap successful! Transaction signature:", tx);
  console.log("View on Solscan:", `https://solscan.io/tx/${tx}`);
}

// Execute the swap
swapUsdcForCustomToken()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
```

**Run the script:**
```bash
npx ts-node swap_usdc_to_custom.ts
```

---

### Example: Swap Custom Token for USDC

This example swaps **0.1 Custom Tokens** for USDC. Adjust the amount for your needs.

**File:** `swap_custom_to_usdc.ts`

Combine the Setup code above with this example in a single file:

```typescript
async function swapCustomTokenForUsdc() {
  // Define swap parameters - swapping 0.1 Custom Tokens
  const swapAmount = new anchor.BN(0.1 * 10**6); // 0.1 Custom Tokens (6 decimals)
  const minAmountOut = new anchor.BN(0.09 * 10**6); // 10% slippage tolerance

  // Token mints
  const usdcMint = new PublicKey("EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v");
  const customTokenMint = new PublicKey("5AMAA9JV9H97YYVxx8F6FsCMmTwXSuTTQneiup4RYAUQ");

  // Derive PDAs
  const [pool] = PublicKey.findProgramAddressSync(
    [Buffer.from("liquidity_pool")],
    program.programId
  );

  const [customTokenVault] = PublicKey.findProgramAddressSync(
    [Buffer.from("token_vault"), pool.toBuffer(), customTokenMint.toBuffer()],
    program.programId
  );

  const [usdcVault] = PublicKey.findProgramAddressSync(
    [Buffer.from("token_vault"), pool.toBuffer(), usdcMint.toBuffer()],
    program.programId
  );

  const [customTokenVaultTokenAccount] = PublicKey.findProgramAddressSync(
    [Buffer.from("vault_token_account"), customTokenVault.toBuffer()],
    program.programId
  );

  const [usdcVaultTokenAccount] = PublicKey.findProgramAddressSync(
    [Buffer.from("vault_token_account"), usdcVault.toBuffer()],
    program.programId
  );

  const [whitelist] = PublicKey.findProgramAddressSync(
    [Buffer.from("address_whitelist")],
    program.programId
  );

  // Get user's token accounts (ATAs)
  const userCustomTokenAccount = await getAssociatedTokenAddress(
    customTokenMint,
    provider.wallet.publicKey
  );

  const userUsdcAccount = await getAssociatedTokenAddress(
    usdcMint,
    provider.wallet.publicKey
  );

  // Fetch pool account to get fee recipient
  const poolAccount = await (program.account as any).liquidityPool.fetch(pool);

  // Get fee recipient's custom token account (fee is in input token)
  const feeRecipientCustomTokenAccount = await getAssociatedTokenAddress(
    customTokenMint,
    poolAccount.feeRecipient
  );

  // Build swap instruction
  const swapIx = await program.methods
    .swap(swapAmount, minAmountOut)
    .accounts({
      pool: pool,
      inVault: customTokenVault,
      outVault: usdcVault,
      inVaultTokenAccount: customTokenVaultTokenAccount,
      outVaultTokenAccount: usdcVaultTokenAccount,
      userFromTokenAccount: userCustomTokenAccount,
      toTokenAccount: userUsdcAccount,
      feeRecipientTokenAccount: feeRecipientCustomTokenAccount, // Fee in input token
      feeRecipient: poolAccount.feeRecipient,
      fromMint: customTokenMint,
      toMint: usdcMint,
      user: provider.wallet.publicKey,
      whitelist: whitelist,
      tokenProgram: TOKEN_PROGRAM_ID,
      associatedTokenProgram: ASSOCIATED_TOKEN_PROGRAM_ID,
      systemProgram: anchor.web3.SystemProgram.programId,
    } as any)
    .instruction();

  // Build and send transaction
  const transaction = new anchor.web3.Transaction();
  transaction.add(swapIx);

  const tx = await provider.sendAndConfirm(transaction);

  console.log("Swap successful! Transaction signature:", tx);
  console.log("View on Solscan:", `https://solscan.io/tx/${tx}`);
}

// Execute the swap
swapCustomTokenForUsdc()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
```

**Run the script:**
```bash
npx ts-node swap_custom_to_usdc.ts
```

---

## Important Notes

### Token Decimals

- The program supports tokens with **6 to 9 decimals**
- Amounts are automatically normalized during swaps
- Example: 100 USDC (6 decimals) → 100 SOL (9 decimals) = 100_000_000 → 100_000_000_000

### Slippage Protection

Always set `min_amount_out` to protect against:
- Fee rate changes between when you fetch pool state and when the transaction executes
- Stale or cached fee rate data
- Potential decimal rounding issues

Formula:
```javascript
const minAmountOut = expectedOutput * (1 - slippageTolerance);
// For 2% slippage tolerance: minAmountOut = expectedOutput * 0.98
```

### Address Whitelist

**Status:** Whitelist may currently be **enabled** for this pool.

When the whitelist is enabled:
- Only whitelisted **wallet addresses** can execute swaps
- The whitelist checks the transaction signer's address (not token accounts)
- Transaction will fail with `NotWhitelisted` error if user is not on the list
- If you need to be whitelisted, please check with the team

**For Smart Contract Integration:**

PDAs can execute swaps via Cross-Program Invocation (CPI). The **PDA address** (not its token accounts) must be whitelisted. The PDA must have sufficient SOL to cover potential account creation fees when calling via CPI with `invoke_signed`.

### Common Errors

| Error | Description | Solution |
|-------|-------------|----------|
| `InsufficientLiquidity` | Not enough liquidity in destination vault | Reduce swap amount or wait for liquidity |
| `SlippageExceeded` | Output amount less than `min_amount_out` | Increase slippage tolerance or check fee rate |
| `NotWhitelisted` | User not on whitelist (when enabled) | Contact support to be added to whitelist |

---

## Testing Checklist

Before using on mainnet, verify:

- [ ] User has sufficient balance of input token
- [ ] User has sufficient SOL for transaction fees (small amount for swap, additional SOL if creating destination token account)
- [ ] Destination token account exists OR you've included the account creation instruction before the swap (see examples)
- [ ] Pool has sufficient liquidity for the swap
- [ ] User is whitelisted (if whitelist is enabled)
- [ ] Tokens are not disabled
- [ ] Fee rate is acceptable
- [ ] Slippage tolerance is reasonable

---

## Getting Help

For issues or questions:
- Review transaction logs on Solana Explorer
- Check program logs for specific error messages
- Verify all PDAs are correctly derived
- Ensure all accounts are in the correct order

---

## Security Considerations

1. **Always verify the Program ID** before sending transactions
2. **Double-check token mint addresses** to avoid scams
3. **Test with small amounts first** before large swaps
4. **Verify transaction details** before signing
5. **Use appropriate slippage protection** to prevent unexpected losses
