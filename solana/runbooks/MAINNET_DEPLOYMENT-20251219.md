# Mainnet Deployment Runbook - Liquidity Pool Program

**Status:** In Progress
**Date Started:** 2025-12-19
**Deployer:** Saliou Diallo

---

## Overview

This runbook guides you through deploying the liquidity pool program to Solana mainnet and initializing it with your custom token and USDC.

**Program ID:** `GadmXgM1J4NhkbqbpnAbEQxHssZAavWxG5uV6AHiLMHv`

---

## Key Information

### Addresses
- **Deployer Wallet:** `13V7ou4zHHwDVaAGWxqHSwU2sVzRR4m62XWqCFxhA5fD`
- **Custom Token Mint:** `9gJ94RYM3kUbFyKzzXAaGaRQ4n39XrDCLPZ1XnpZhnms`
- **Custom Token Decimals:** `6`
- **USDC Mint:** `EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v`
- **Pool PDA:** `5QoFtuiVkt5cXcBxmPUGp1waq3b9H5Q9RgKTpV3NcjEh`
- **Whitelist PDA:** `9bEDjK1LWyi9dxWcW2qNbYqc6MWTmwoMuX6qucEyJTmm`
- **Custom Token Vault:** `EPFgtsNL4VVqwbh6cPwFoWCoqjW1WQvgbRAcitV49HYH`
- **Custom Token Vault Token Account:** `3y6MPgBvQqCS5EJkWE8w6dYwVLT3sue4s6inP8AoAkJv`
- **USDC Vault:** `GZHACYSwd3TWc4AVjWnHVwudVXrXWdh6qqKhgGcf1aFx`
- **USDC Vault Token Account:** `9XX1dwrvpxAqzZ8jEbE8NMmTA7nGK2eVApuoXJxPGrfS`

### Configuration
- **Fee Rate:** 0 basis points (0% - for 1:1 swaps)
- **Operations Authority:** Deployer wallet
- **Pause Authority:** Deployer wallet
- **Fee Recipient:** Deployer wallet

---

## PHASE 1: Pre-Deployment Setup

Install `solana`, `anchor`, and `spl-token`.

```bash
❯ solana --version
solana-cli 2.2.21 (src:23e01995; feat:3073396398, client:Agave)
❯ anchor --version
anchor-cli 0.31.1
❯ spl-token --version
spl-token-cli 5.3.0
```

### ✅ Step 1.1: Configure Environment to Solana Mainnet
**Command:**
```bash
solana config set -u m
```

---

### ✅ Step 1.2: Get Wallet Address
**Command:**
```bash
solana address
```

**Result:**
- [x] Completed
- Wallet Address: `13V7ou4zHHwDVaAGWxqHSwU2sVzRR4m62XWqCFxhA5fD`

Fund your wallet with enough SOL if needed. You will likely need about 4-5 SOL.

---

### ✅ Step 1.3: Check SOL Balance
**Command:**
```bash
solana balance
```

**Expected:** At least 4-5 SOL

**Result:**
- [x] Completed
- Balance: `5` SOL
- Notes: `___________________`

---

### ✅ Step 1.4: Build the Program
**Command:**
```bash
anchor clean
anchor build
```

---

### ✅ Step 1.5: Verify Program Build
**Command:**
```bash
# Check that the program is built
ls -lh target/deploy/scaas_liquidity.so

# Verify program keypair matches expected ID (should match Anchor.toml)
solana address -k target/deploy/scaas_liquidity-keypair.json
```

**Expected:** `GadmXgM1J4NhkbqbpnAbEQxHssZAavWxG5uV6AHiLMHv`

**Result:**
- [x] Completed
- Program Size: `452K`
- Program ID Matches: `Yes`
- Notes: `___________________`

---

### ✅ Step 1.6: Verify Custom Token Details
**Commands:**
```bash
# Check your token mint address
spl-token accounts

# Get specific token balance and verify decimals
spl-token account-info <YOUR_TOKEN_MINT>

# If you have no token account for the token mint, you may create it with
spl-token create-account <YOUR_TOKEN_MINT>
```

**Result:**
- [ ] Completed
- Custom Token Mint: `9gJ94RYM3kUbFyKzzXAaGaRQ4n39XrDCLPZ1XnpZhnms`
- Custom Token Decimals: `6`
- Your Token Account: `A7vP6Ut36Tmc94ACNBPKWjfiPZPeSsadw8jYqSbKEdBk`
- Your Token Balance: `0`
- Notes: `___________________`

---

## PHASE 2: Program Deployment

### ✅ Step 2.1: Deploy Program to Mainnet
**Command:**
```bash
anchor deploy --provider.cluster mainnet
```

**Result:**
- [x] Completed
- Transaction Signature: `4hstLhbDQzxZ1d5WxZ1tn75tgG2GPhJ6q5jTy5qGkrZMBE3mXrjh14DB4EDegQvrxmDq8N1FEjHyTpq3HWMwrWYf`
- Program ID: `GadmXgM1J4NhkbqbpnAbEQxHssZAavWxG5uV6AHiLMHv`
- Deployment Cost: `3.226759396` SOL
- Timestamp: `Dec 19, 2025 at 22:17:38 Eastern Standard Time`
- Notes: `___________________`

---

### ✅ Step 2.2: Verify Deployment
**Command:**
```bash
solana program show GadmXgM1J4NhkbqbpnAbEQxHssZAavWxG5uV6AHiLMHv
```

**Result:**
- [x] Completed
- Program Exists: `Yes`
- **Program Id**: GadmXgM1J4NhkbqbpnAbEQxHssZAavWxG5uV6AHiLMHv
- **Owner**: BPFLoaderUpgradeab1e11111111111111111111111
- **ProgramData Address**: FVqHqZmj6WCBxhHC1k3P8J8YyoYW2weJ8yUw57a36zWz
- **Authority**: 13V7ou4zHHwDVaAGWxqHSwU2sVzRR4m62XWqCFxhA5fD
- **Last Deployed In Slot**: 387881099
- **Data Length**: 462928 (0x71050) bytes
- **Balance**: 3.22318296 SOL
- Notes: `___________________`

---

## PHASE 3: Initialize Pool

### ✅ Step 3.1: Install TypeScript Dependencies
**Command:**
```bash
yarn add -D ts-node typescript @types/node
```

**Result:**
- [x] Completed
- Notes: `Installed successfully`

---

### ✅ Step 3.2: Set Environment Variables (Optional)
**Command:**
```bash
# Export these in your shell (or add to ~/.bashrc or ~/.zshrc)
export ANCHOR_PROVIDER_URL="https://api.mainnet-beta.solana.com"
export ANCHOR_WALLET="$HOME/.config/solana/id.json"
```

**Note:** The scripts will use these defaults if not set, so this step is optional. But it's good practice to set them explicitly.

**Result:**
- [ ] Completed
- Notes: `___________________`

---

### ✅ Step 3.3: Create Initialization Script
**File:** `scripts/01-initialize-pool.ts`

Created at `scripts/01-initialize-pool.ts`.

**Usage:**
```bash
yarn ts-node scripts/01-initialize-pool.ts <FEE_RATE_BPS>
```

**Arguments:**
- `FEE_RATE_BPS`: Fee rate in basis points (0-1000)
  - 0 = 0% fee (1:1 swaps)
  - 10 = 0.1% fee
  - 100 = 1% fee
  - 1000 = 10% fee (maximum)

**Result:**
- [x] Completed
- Script Created: `Yes`
- Notes: `Script accepts fee rate as command-line argument`

---

### ✅ Step 3.4: Run Pool Initialization
**Command:**
```bash
# For 0% fee (1:1 swaps)
yarn ts-node scripts/01-initialize-pool.ts 0

# Or for 1% fee
yarn ts-node scripts/01-initialize-pool.ts 100
```

**Result:**
- [x] Completed
- Fee Rate Used: `0` bps (0%)
- Transaction Signature: `G9jf2bis2HzXBg1zZkdwpWUTgAe442NQgBnM4nc8kUSnBcz3iaa8Goz1zvWZZnomrAGrWFSqbaYm8RZz4xt7pMX`
- Explorer: https://solscan.io/tx/G9jf2bis2HzXBg1zZkdwpWUTgAe442NQgBnM4nc8kUSnBcz3iaa8Goz1zvWZZnomrAGrWFSqbaYm8RZz4xt7pMX
- Pool PDA: `5QoFtuiVkt5cXcBxmPUGp1waq3b9H5Q9RgKTpV3NcjEh`
- Whitelist PDA: `9bEDjK1LWyi9dxWcW2qNbYqc6MWTmwoMuX6qucEyJTmm`
- Timestamp: `2025-12-19`
- Notes: `Successfully initialized with 0% fee for 1:1 swaps`

```
============================================================
INITIALIZING LIQUIDITY POOL
============================================================

Configuration:
- Program ID: GadmXgM1J4NhkbqbpnAbEQxHssZAavWxG5uV6AHiLMHv
- Pool PDA: 5QoFtuiVkt5cXcBxmPUGp1waq3b9H5Q9RgKTpV3NcjEh
- Whitelist PDA: 9bEDjK1LWyi9dxWcW2qNbYqc6MWTmwoMuX6qucEyJTmm
- Deployer/Authority: 13V7ou4zHHwDVaAGWxqHSwU2sVzRR4m62XWqCFxhA5fD

✓ Pool not yet initialized, proceeding...

Initialization Parameters:
- Fee Rate: 0 basis points (0%)
- Operations Authority: 13V7ou4zHHwDVaAGWxqHSwU2sVzRR4m62XWqCFxhA5fD
- Pause Authority: 13V7ou4zHHwDVaAGWxqHSwU2sVzRR4m62XWqCFxhA5fD
- Fee Recipient: 13V7ou4zHHwDVaAGWxqHSwU2sVzRR4m62XWqCFxhA5fD

Sending transaction...
✅ Pool initialized successfully!

Transaction Details:
- Signature: G9jf2bis2HzXBg1zZkdwpWUTgAe442NQgBnM4nc8kUSnBcz3iaa8Goz1zvWZZnomrAGrWFSqbaYm8RZz4xt7pMX
- Explorer: https://solscan.io/tx/G9jf2bis2HzXBg1zZkdwpWUTgAe442NQgBnM4nc8kUSnBcz3iaa8Goz1zvWZZnomrAGrWFSqbaYm8RZz4xt7pMX

Pool State:
- Operations Authority: 13V7ou4zHHwDVaAGWxqHSwU2sVzRR4m62XWqCFxhA5fD
- Pause Authority: 13V7ou4zHHwDVaAGWxqHSwU2sVzRR4m62XWqCFxhA5fD
- Fee Recipient: 13V7ou4zHHwDVaAGWxqHSwU2sVzRR4m62XWqCFxhA5fD
- Fee Rate: 0 bps
- Swaps Paused: false
- Liquidity Paused: false
- Supported Tokens: 0

Whitelist State:
- Enabled: false
- Addresses: 0

============================================================
SAVE THESE ADDRESSES:
============================================================
Pool: 5QoFtuiVkt5cXcBxmPUGp1waq3b9H5Q9RgKTpV3NcjEh
Whitelist: 9bEDjK1LWyi9dxWcW2qNbYqc6MWTmwoMuX6qucEyJTmm
============================================================
✨  Done in 6.50s.
```

---

### ✅ Step 3.5: Verify Pool State
**Command:**
```bash
yarn ts-node scripts/verify-pool.ts
```

**Result:**
- [x] Completed
- Operations Authority: `13V7ou4zHHwDVaAGWxqHSwU2sVzRR4m62XWqCFxhA5fD`
- Pause Authority: `13V7ou4zHHwDVaAGWxqHSwU2sVzRR4m62XWqCFxhA5fD`
- Fee Recipient: `13V7ou4zHHwDVaAGWxqHSwU2sVzRR4m62XWqCFxhA5fD`
- Fee Rate: `0` bps (0%)
- Swaps Paused: `false`
- Liquidity Paused: `false`
- Supported Tokens Count: `0`
- Whitelist Enabled: `false`
- Notes: `Pool successfully initialized and verified`

```
============================================================
POOL STATE VERIFICATION
============================================================

Addresses:
- Program ID: GadmXgM1J4NhkbqbpnAbEQxHssZAavWxG5uV6AHiLMHv
- Pool PDA: 5QoFtuiVkt5cXcBxmPUGp1waq3b9H5Q9RgKTpV3NcjEh
- Whitelist PDA: 9bEDjK1LWyi9dxWcW2qNbYqc6MWTmwoMuX6qucEyJTmm

Pool Configuration:
- Operations Authority: 13V7ou4zHHwDVaAGWxqHSwU2sVzRR4m62XWqCFxhA5fD
- Pause Authority: 13V7ou4zHHwDVaAGWxqHSwU2sVzRR4m62XWqCFxhA5fD
- Fee Recipient: 13V7ou4zHHwDVaAGWxqHSwU2sVzRR4m62XWqCFxhA5fD
- Fee Rate: 0 bps (0%)
- Swaps Paused: false
- Liquidity Paused: false

Supported Tokens:
- Count: 0

Whitelist State:
- Enabled: false
- Addresses Count: 0

============================================================
✅ Pool verification complete!
============================================================
✨  Done in 1.25s.
```

---

## PHASE 4: Add Custom Token

### ✅ Step 4.1: Create Add Token Script
**File:** `scripts/02-add-token.ts`

Create this TypeScript script to add your custom token.

**Result:**
- [x] Completed
- Script Created: `Yes`
- Notes: `___________________`

---

### ✅ Step 4.2: Add Custom Token to Pool
**Command:**
```bash
yarn ts-node scripts/02-add-token.ts 9gJ94RYM3kUbFyKzzXAaGaRQ4n39XrDCLPZ1XnpZhnms
```

**Result:**
- [x] Completed
- Transaction Signature: `pCLMbQkPc7QeTqhfxE7Quztmh7LPvGw11hguM5AQGZa5jX32G7cbSPVGL1y7RBUz3JPgS65DgXDkCDLnknRk3Ad`
- Explorer: https://solscan.io/tx/pCLMbQkPc7QeTqhfxE7Quztmh7LPvGw11hguM5AQGZa5jX32G7cbSPVGL1y7RBUz3JPgS65DgXDkCDLnknRk3Ad
- Custom Token Vault PDA: `EPFgtsNL4VVqwbh6cPwFoWCoqjW1WQvgbRAcitV49HYH`
- Custom Token Vault Token Account: `3y6MPgBvQqCS5EJkWE8w6dYwVLT3sue4s6inP8AoAkJv`
- Fee Recipient Token Account: `A7vP6Ut36Tmc94ACNBPKWjfiPZPeSsadw8jYqSbKEdBk`
- Timestamp: `2025-12-19`
- Notes: `Successfully added custom token to pool`

```
============================================================
ADDING TOKEN TO POOL
============================================================

Configuration:
- Program ID: GadmXgM1J4NhkbqbpnAbEQxHssZAavWxG5uV6AHiLMHv
- Pool PDA: 5QoFtuiVkt5cXcBxmPUGp1waq3b9H5Q9RgKTpV3NcjEh
- Token Mint: 9gJ94RYM3kUbFyKzzXAaGaRQ4n39XrDCLPZ1XnpZhnms
- Vault PDA: EPFgtsNL4VVqwbh6cPwFoWCoqjW1WQvgbRAcitV49HYH
- Vault Token Account: 3y6MPgBvQqCS5EJkWE8w6dYwVLT3sue4s6inP8AoAkJv
- Fee Recipient Token Account: A7vP6Ut36Tmc94ACNBPKWjfiPZPeSsadw8jYqSbKEdBk
- Operations Authority: 13V7ou4zHHwDVaAGWxqHSwU2sVzRR4m62XWqCFxhA5fD

✓ Token not yet added, proceeding...

Sending transaction...
✅ Token added successfully!

Transaction Details:
- Signature: pCLMbQkPc7QeTqhfxE7Quztmh7LPvGw11hguM5AQGZa5jX32G7cbSPVGL1y7RBUz3JPgS65DgXDkCDLnknRk3Ad
- Explorer: https://solscan.io/tx/pCLMbQkPc7QeTqhfxE7Quztmh7LPvGw11hguM5AQGZa5jX32G7cbSPVGL1y7RBUz3JPgS65DgXDkCDLnknRk3Ad

Updated Pool State:
- Supported Tokens Count: 1
- Supported Tokens:
  1. 9gJ94RYM3kUbFyKzzXAaGaRQ4n39XrDCLPZ1XnpZhnms

============================================================
SAVE THESE ADDRESSES:
============================================================
Token Mint: 9gJ94RYM3kUbFyKzzXAaGaRQ4n39XrDCLPZ1XnpZhnms
Vault: EPFgtsNL4VVqwbh6cPwFoWCoqjW1WQvgbRAcitV49HYH
Vault Token Account: 3y6MPgBvQqCS5EJkWE8w6dYwVLT3sue4s6inP8AoAkJv
Fee Recipient Token Account: A7vP6Ut36Tmc94ACNBPKWjfiPZPeSsadw8jYqSbKEdBk
============================================================
✨  Done in 2.74s.
```

---

### ✅ Step 4.3: Verify Custom Token Added
**Result:**
- [x] Completed
- Token in Supported List: `Yes (1 of 1 tokens)`
- Vault Exists: `Yes - EPFgtsNL4VVqwbh6cPwFoWCoqjW1WQvgbRAcitV49HYH`
- Vault Token Account Exists: `Yes - 3y6MPgBvQqCS5EJkWE8w6dYwVLT3sue4s6inP8AoAkJv`
- Fee Recipient ATA Created: `Yes - A7vP6Ut36Tmc94ACNBPKWjfiPZPeSsadw8jYqSbKEdBk`
- Notes: `Token successfully added and verified`

---

## PHASE 5: Add USDC

### ✅ Step 5.1: Add USDC to Pool
**Note:** We use the same `02-add-token.ts` script for all tokens.

**Command:**
```bash
yarn ts-node scripts/02-add-token.ts EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v
```

**Result:**
- [x] Completed
- Transaction Signature: `67m6aUiSdbvskrKy55mz73VyFSwnuWxbd5CtRtetXGr4yi9Net2X9c5ehwqpMPz7jVXxoApF4ncXx8AdnyV3jRqU`
- Explorer: https://solscan.io/tx/67m6aUiSdbvskrKy55mz73VyFSwnuWxbd5CtRtetXGr4yi9Net2X9c5ehwqpMPz7jVXxoApF4ncXx8AdnyV3jRqU
- USDC Vault PDA: `GZHACYSwd3TWc4AVjWnHVwudVXrXWdh6qqKhgGcf1aFx`
- USDC Vault Token Account: `9XX1dwrvpxAqzZ8jEbE8NMmTA7nGK2eVApuoXJxPGrfS`
- Fee Recipient Token Account: `7vqUNuSd8jYFcbV3RXMyHFTV8kZx2uUVFVSCSQCoQQgw`
- Timestamp: `2025-12-19`
- Notes: `Successfully added USDC to pool`

```
============================================================
ADDING TOKEN TO POOL
============================================================

Configuration:
- Program ID: GadmXgM1J4NhkbqbpnAbEQxHssZAavWxG5uV6AHiLMHv
- Pool PDA: 5QoFtuiVkt5cXcBxmPUGp1waq3b9H5Q9RgKTpV3NcjEh
- Token Mint: EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v
- Vault PDA: GZHACYSwd3TWc4AVjWnHVwudVXrXWdh6qqKhgGcf1aFx
- Vault Token Account: 9XX1dwrvpxAqzZ8jEbE8NMmTA7nGK2eVApuoXJxPGrfS
- Fee Recipient Token Account: 7vqUNuSd8jYFcbV3RXMyHFTV8kZx2uUVFVSCSQCoQQgw
- Operations Authority: 13V7ou4zHHwDVaAGWxqHSwU2sVzRR4m62XWqCFxhA5fD

✓ Token not yet added, proceeding...

Sending transaction...
✅ Token added successfully!

Transaction Details:
- Signature: 67m6aUiSdbvskrKy55mz73VyFSwnuWxbd5CtRtetXGr4yi9Net2X9c5ehwqpMPz7jVXxoApF4ncXx8AdnyV3jRqU
- Explorer: https://solscan.io/tx/67m6aUiSdbvskrKy55mz73VyFSwnuWxbd5CtRtetXGr4yi9Net2X9c5ehwqpMPz7jVXxoApF4ncXx8AdnyV3jRqU

Updated Pool State:
- Supported Tokens Count: 2
- Supported Tokens:
  1. 9gJ94RYM3kUbFyKzzXAaGaRQ4n39XrDCLPZ1XnpZhnms
  2. EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v

============================================================
SAVE THESE ADDRESSES:
============================================================
Token Mint: EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v
Vault: GZHACYSwd3TWc4AVjWnHVwudVXrXWdh6qqKhgGcf1aFx
Vault Token Account: 9XX1dwrvpxAqzZ8jEbE8NMmTA7nGK2eVApuoXJxPGrfS
Fee Recipient Token Account: 7vqUNuSd8jYFcbV3RXMyHFTV8kZx2uUVFVSCSQCoQQgw
============================================================
✨  Done in 8.81s.
```

---

### ✅ Step 5.2: Verify USDC Added
**Result:**
- [x] Completed
- Token in Supported List: `Yes (2 of 2 tokens)`
- Vault Exists: `Yes - GZHACYSwd3TWc4AVjWnHVwudVXrXWdh6qqKhgGcf1aFx`
- Vault Token Account Exists: `Yes - 9XX1dwrvpxAqzZ8jEbE8NMmTA7nGK2eVApuoXJxPGrfS`
- Fee Recipient ATA Created: `Yes - 7vqUNuSd8jYFcbV3RXMyHFTV8kZx2uUVFVSCSQCoQQgw`
- Notes: `USDC successfully added. Pool now has 2 tokens.`

```
============================================================
POOL STATE VERIFICATION
============================================================

Addresses:
- Program ID: GadmXgM1J4NhkbqbpnAbEQxHssZAavWxG5uV6AHiLMHv
- Pool PDA: 5QoFtuiVkt5cXcBxmPUGp1waq3b9H5Q9RgKTpV3NcjEh
- Whitelist PDA: 9bEDjK1LWyi9dxWcW2qNbYqc6MWTmwoMuX6qucEyJTmm

Pool Configuration:
- Operations Authority: 13V7ou4zHHwDVaAGWxqHSwU2sVzRR4m62XWqCFxhA5fD
- Pause Authority: 13V7ou4zHHwDVaAGWxqHSwU2sVzRR4m62XWqCFxhA5fD
- Fee Recipient: 13V7ou4zHHwDVaAGWxqHSwU2sVzRR4m62XWqCFxhA5fD
- Fee Rate: 0 bps (0%)
- Swaps Paused: false
- Liquidity Paused: false

Supported Tokens:
- Count: 2
  1. 9gJ94RYM3kUbFyKzzXAaGaRQ4n39XrDCLPZ1XnpZhnms
  2. EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v

Whitelist State:
- Enabled: false
- Addresses Count: 0

============================================================
✅ Pool verification complete!
============================================================
✨  Done in 1.56s.
```

---

## PHASE 6: Deposit Liquidity

### ✅ Step 6.1: Check Token Balances
**Commands:**
```bash
# Check your custom token balance
spl-token balance 9gJ94RYM3kUbFyKzzXAaGaRQ4n39XrDCLPZ1XnpZhnms

# Check your USDC balance
spl-token balance EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v
```

Fund your wallet with your custom token and USDC, e.g. 10 of each.

**Result:**
- [x] Completed
- Custom Token Balance: `20`
- USDC Balance: `10`
- Notes: `___________________`

---

### ✅ Step 6.2: Deposit Custom Token Liquidity
**Planned Amount:** `5` tokens

**Note:** We use the universal `03-deposit-liquidity.ts` script for all tokens.

**Command:**
```bash
yarn ts-node scripts/03-deposit-liquidity.ts 9gJ94RYM3kUbFyKzzXAaGaRQ4n39XrDCLPZ1XnpZhnms 5
```

**Result:**
- [x] Completed
- Transaction Signature: `5f31q7pFpad95eZBwR6CP7KgNMH1TZKWCdt93A6gsergYnsYACj4fuYy7JJzY6uAHJU4sR6uzmXM9sCzpHdM2FMZ`
- Explorer: https://solscan.io/tx/5f31q7pFpad95eZBwR6CP7KgNMH1TZKWCdt93A6gsergYnsYACj4fuYy7JJzY6uAHJU4sR6uzmXM9sCzpHdM2FMZ
- Amount Deposited: `5` tokens
- Vault Balance After: `5` tokens
- Timestamp: `2025-12-19`
- Notes: `Successfully deposited 5 custom tokens`

```
============================================================
DEPOSITING LIQUIDITY
============================================================

Configuration:
- Program ID: GadmXgM1J4NhkbqbpnAbEQxHssZAavWxG5uV6AHiLMHv
- Pool PDA: 5QoFtuiVkt5cXcBxmPUGp1waq3b9H5Q9RgKTpV3NcjEh
- Token Mint: 9gJ94RYM3kUbFyKzzXAaGaRQ4n39XrDCLPZ1XnpZhnms
- Token Decimals: 6
- Vault PDA: EPFgtsNL4VVqwbh6cPwFoWCoqjW1WQvgbRAcitV49HYH
- Vault Token Account: 3y6MPgBvQqCS5EJkWE8w6dYwVLT3sue4s6inP8AoAkJv
- Operations Authority: 13V7ou4zHHwDVaAGWxqHSwU2sVzRR4m62XWqCFxhA5fD
- Operations Authority Token Account: A7vP6Ut36Tmc94ACNBPKWjfiPZPeSsadw8jYqSbKEdBk

Deposit Details:
- Amount (tokens): 5
- Amount (base units): 5000000

Your Balance: 20 tokens
Vault Balance Before: 0 tokens

Sending transaction...
✅ Liquidity deposited successfully!

Transaction Details:
- Signature: 5f31q7pFpad95eZBwR6CP7KgNMH1TZKWCdt93A6gsergYnsYACj4fuYy7JJzY6uAHJU4sR6uzmXM9sCzpHdM2FMZ
- Explorer: https://solscan.io/tx/5f31q7pFpad95eZBwR6CP7KgNMH1TZKWCdt93A6gsergYnsYACj4fuYy7JJzY6uAHJU4sR6uzmXM9sCzpHdM2FMZ

Vault Balance After: 5 tokens
Amount Deposited: 5 tokens

============================================================
✅ Deposit complete!
============================================================
✨  Done in 2.35s.
```

---

### ✅ Step 6.3: Deposit USDC Liquidity
**Planned Amount:** `5` USDC

**Command:**
```bash
yarn ts-node scripts/03-deposit-liquidity.ts EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v 5
```

**Result:**
- [x] Completed
- Transaction Signature: `5hmVPYTq8DxCtiMV3MeSJnTH7A6ctq2EqzucL592wTWq2nhs4Dk4rnVcjRtQwnDkkRK3dopfDhkA987eZhoLE1mY`
- Explorer: https://solscan.io/tx/5hmVPYTq8DxCtiMV3MeSJnTH7A6ctq2EqzucL592wTWq2nhs4Dk4rnVcjRtQwnDkkRK3dopfDhkA987eZhoLE1mY
- Amount Deposited: `5` USDC
- Vault Balance After: `5` USDC
- Timestamp: `2025-12-19`
- Notes: `Successfully deposited 5 USDC`

```
============================================================
DEPOSITING LIQUIDITY
============================================================

Configuration:
- Program ID: GadmXgM1J4NhkbqbpnAbEQxHssZAavWxG5uV6AHiLMHv
- Pool PDA: 5QoFtuiVkt5cXcBxmPUGp1waq3b9H5Q9RgKTpV3NcjEh
- Token Mint: EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v
- Token Decimals: 6
- Vault PDA: GZHACYSwd3TWc4AVjWnHVwudVXrXWdh6qqKhgGcf1aFx
- Vault Token Account: 9XX1dwrvpxAqzZ8jEbE8NMmTA7nGK2eVApuoXJxPGrfS
- Operations Authority: 13V7ou4zHHwDVaAGWxqHSwU2sVzRR4m62XWqCFxhA5fD
- Operations Authority Token Account: 7vqUNuSd8jYFcbV3RXMyHFTV8kZx2uUVFVSCSQCoQQgw

Deposit Details:
- Amount (tokens): 5
- Amount (base units): 5000000

Your Balance: 10 tokens
Vault Balance Before: 0 tokens

Sending transaction...
✅ Liquidity deposited successfully!

Transaction Details:
- Signature: 5hmVPYTq8DxCtiMV3MeSJnTH7A6ctq2EqzucL592wTWq2nhs4Dk4rnVcjRtQwnDkkRK3dopfDhkA987eZhoLE1mY
- Explorer: https://solscan.io/tx/5hmVPYTq8DxCtiMV3MeSJnTH7A6ctq2EqzucL592wTWq2nhs4Dk4rnVcjRtQwnDkkRK3dopfDhkA987eZhoLE1mY

Vault Balance After: 5 tokens
Amount Deposited: 5 tokens

============================================================
✅ Deposit complete!
============================================================
✨  Done in 5.74s.
```

---

## PHASE 7: Final Verification

### ✅ Step 7.1: Verify Complete Pool State
**Command:**
```bash
yarn ts-node scripts/verify-pool.ts
```

**Result:**
- [x] Completed
- Pool Initialized: `Yes`
- Supported Tokens: `2 (Custom Token + USDC)`
- Custom Token Vault Balance: `5 tokens`
- USDC Vault Balance: `5 USDC`
- Total Liquidity USD Value: `~$10 USD (assuming 1:1 with USDC)`
- Fee Rate: `0 bps (0%)`
- Swaps Paused: `false`
- Liquidity Paused: `false`
- Whitelist Enabled: `false`
- Notes: `Pool fully operational and ready for swaps`

---

### ✅ Step 7.2: Test Swap (Optional but Recommended)
**Test:** Small swap of 1 USDC -> Custom Token

**Command:**
```bash
yarn ts-node scripts/04-test-swap.ts EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v 9gJ94RYM3kUbFyKzzXAaGaRQ4n39XrDCLPZ1XnpZhnms 1
```

**Result:**
- [x] Completed
- Transaction Signature: `4p9YnvLZPa2iW6ZkyNmgrrg8QnE8SEv8KgRXP85fQDVtSWqCLjXr8DHUt4DBVmnysdRBH7Ef9mH8ZVJBJzUAGppx`
- Explorer: https://solscan.io/tx/4p9YnvLZPa2iW6ZkyNmgrrg8QnE8SEv8KgRXP85fQDVtSWqCLjXr8DHUt4DBVmnysdRBH7Ef9mH8ZVJBJzUAGppx
- Input: `1` USDC
- Output: `1` Custom Token
- Exchange Rate: `1:1 (0% fee)`
- Balance Before: 5 USDC, 15 Custom Token
- Balance After: 4 USDC, 16 Custom Token
- Timestamp: `2025-12-19`
- Notes: `Swap executed perfectly at 1:1 rate with 0% fee`

```
============================================================
TEST SWAP
============================================================

Configuration:
- Program ID: GadmXgM1J4NhkbqbpnAbEQxHssZAavWxG5uV6AHiLMHv
- Pool PDA: 5QoFtuiVkt5cXcBxmPUGp1waq3b9H5Q9RgKTpV3NcjEh
- User: 13V7ou4zHHwDVaAGWxqHSwU2sVzRR4m62XWqCFxhA5fD

Swap Details:
- From Token: EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v
- To Token: 9gJ94RYM3kUbFyKzzXAaGaRQ4n39XrDCLPZ1XnpZhnms
- Amount In: 1 tokens
- Amount In (base units): 1000000
- Min Amount Out (base units): 990000
- From Decimals: 6
- To Decimals: 6

Your Balance (From Token): 5 tokens
Your Balance (To Token): 15 tokens

Sending transaction...
✅ Swap successful!

Transaction Details:
- Signature: 4p9YnvLZPa2iW6ZkyNmgrrg8QnE8SEv8KgRXP85fQDVtSWqCLjXr8DHUt4DBVmnysdRBH7Ef9mH8ZVJBJzUAGppx
- Explorer: https://solscan.io/tx/4p9YnvLZPa2iW6ZkyNmgrrg8QnE8SEv8KgRXP85fQDVtSWqCLjXr8DHUt4DBVmnysdRBH7Ef9mH8ZVJBJzUAGppx

Your Balance After (From Token): 4 tokens
Your Balance After (To Token): 16 tokens

============================================================
✅ Swap complete!
============================================================
✨  Done in 3.28s.
```

---

### ✅ Step 7.3: Test Reverse Swap
**Test:** Reverse swap of 1 Custom Token -> USDC

**Command:**
```bash
yarn ts-node scripts/04-test-swap.ts 9gJ94RYM3kUbFyKzzXAaGaRQ4n39XrDCLPZ1XnpZhnms EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v 1
```

**Result:**
- [x] Completed
- Transaction Signature: `41ucd8CqGkNjPbFYkDhgYVzGZUCwVfjgSK218f96YRTkw5huQzMBjeNEh5ESHq7yF7Dx9pMLNftQx3AHVhCikf3Q`
- Explorer: https://solscan.io/tx/41ucd8CqGkNjPbFYkDhgYVzGZUCwVfjgSK218f96YRTkw5huQzMBjeNEh5ESHq7yF7Dx9pMLNftQx3AHVhCikf3Q
- Input: `1` Custom Token
- Output: `1` USDC
- Exchange Rate: `1:1 (0% fee)`
- Balance Before: 16 Custom Token, 4 USDC
- Balance After: 15 Custom Token, 5 USDC
- Timestamp: `2025-12-19`
- Notes: `Reverse swap successful! Round-trip complete - both directions work perfectly at 1:1`

```
============================================================
TEST SWAP
============================================================

Configuration:
- Program ID: GadmXgM1J4NhkbqbpnAbEQxHssZAavWxG5uV6AHiLMHv
- Pool PDA: 5QoFtuiVkt5cXcBxmPUGp1waq3b9H5Q9RgKTpV3NcjEh
- User: 13V7ou4zHHwDVaAGWxqHSwU2sVzRR4m62XWqCFxhA5fD

Swap Details:
- From Token: 9gJ94RYM3kUbFyKzzXAaGaRQ4n39XrDCLPZ1XnpZhnms
- To Token: EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v
- Amount In: 1 tokens
- Amount In (base units): 1000000
- Min Amount Out (base units): 990000
- From Decimals: 6
- To Decimals: 6

Your Balance (From Token): 16 tokens
Your Balance (To Token): 4 tokens

Sending transaction...
✅ Swap successful!

Transaction Details:
- Signature: 41ucd8CqGkNjPbFYkDhgYVzGZUCwVfjgSK218f96YRTkw5huQzMBjeNEh5ESHq7yF7Dx9pMLNftQx3AHVhCikf3Q
- Explorer: https://solscan.io/tx/41ucd8CqGkNjPbFYkDhgYVzGZUCwVfjgSK218f96YRTkw5huQzMBjeNEh5ESHq7yF7Dx9pMLNftQx3AHVhCikf3Q

Your Balance After (From Token): 15 tokens
Your Balance After (To Token): 5 tokens

============================================================
✅ Swap complete!
============================================================
✨  Done in 5.68s.
```

---

### ✅ Step 7.4: Test Delegation Swap (Optional)
**Test:** Swap tokens to a different recipient's account (delegation pattern)

**Command:**
```bash
yarn ts-node scripts/04-test-swap.ts EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v 9gJ94RYM3kUbFyKzzXAaGaRQ4n39XrDCLPZ1XnpZhnms 1 9TcjK2ToqoAtCr5jrLdDXNTNbZBbDQB1zy2BNGMr7nQE
```

**Result:**
- [x] Completed
- Transaction Signature: `4oJxzARyEWeMrUYin36eATPGpTSvQDr2xCG5CTytBguY9QDVNaWoDigYvCHUgAobmhrnDzqVq2xHf2GspuvLDmAe`
- Explorer: https://solscan.io/tx/4oJxzARyEWeMrUYin36eATPGpTSvQDr2xCG5CTytBguY9QDVNaWoDigYvCHUgAobmhrnDzqVq2xHf2GspuvLDmAe
- Signer: `13V7ou4zHHwDVaAGWxqHSwU2sVzRR4m62XWqCFxhA5fD`
- Recipient: `9TcjK2ToqoAtCr5jrLdDXNTNbZBbDQB1zy2BNGMr7nQE`
- Input: `1` USDC (from signer)
- Output: `1` Custom Token (to recipient)
- Exchange Rate: `1:1 (0% fee)`
- Signer Balance Before: 5 USDC
- Signer Balance After: 4 USDC
- Recipient Balance Before: 0 Custom Token (account didn't exist)
- Recipient Balance After: 1 Custom Token
- Auto-created recipient's ATA: Yes
- Timestamp: `2025-12-23`
- Notes: `Delegation swap successful! Tokens swapped directly into recipient's account. Recipient's ATA was auto-created in the same transaction.`

```
============================================================
TEST SWAP
============================================================

Configuration:
- Program ID: GadmXgM1J4NhkbqbpnAbEQxHssZAavWxG5uV6AHiLMHv
- Pool PDA: 5QoFtuiVkt5cXcBxmPUGp1waq3b9H5Q9RgKTpV3NcjEh
- User (Signer): 13V7ou4zHHwDVaAGWxqHSwU2sVzRR4m62XWqCFxhA5fD
- Recipient (Destination): 9TcjK2ToqoAtCr5jrLdDXNTNbZBbDQB1zy2BNGMr7nQE

Swap Details:
- From Token: EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v
- To Token: 9gJ94RYM3kUbFyKzzXAaGaRQ4n39XrDCLPZ1XnpZhnms
- Amount In: 1 tokens
- Amount In (base units): 1000000
- Min Amount Out (base units): 990000
- From Decimals: 6
- To Decimals: 6

Your Balance (From Token): 5 tokens
Recipient Balance (To Token): 0 tokens (account doesn't exist)

Sending transaction...
Creating destination token account for recipient...
✅ Swap successful!

Transaction Details:
- Signature: 4oJxzARyEWeMrUYin36eATPGpTSvQDr2xCG5CTytBguY9QDVNaWoDigYvCHUgAobmhrnDzqVq2xHf2GspuvLDmAe
- Explorer: https://solscan.io/tx/4oJxzARyEWeMrUYin36eATPGpTSvQDr2xCG5CTytBguY9QDVNaWoDigYvCHUgAobmhrnDzqVq2xHf2GspuvLDmAe

Your Balance After (From Token): 4 tokens
Recipient Balance After (To Token): 1 tokens

============================================================
✅ Swap complete!
============================================================
✨  Done in 6.41s.
```

---

## PHASE 8: Whitelist Testing

### ✅ Step 8.1: Enable Whitelist

**Command:**
```bash
yarn ts-node scripts/whitelist-toggle.ts true
```

**Result:**
- [x] Completed
- Transaction Signature: `5g5b4anEQLuHxjpPRQGfz9dg9CuLDjzWiQmCtZZt61UA7yurQhFUF4pC95eXTdWErEdoreimd7szZU2QHPgwbzsZ`
- Explorer: https://solscan.io/tx/5g5b4anEQLuHxjpPRQGfz9dg9CuLDjzWiQmCtZZt61UA7yurQhFUF4pC95eXTdWErEdoreimd7szZU2QHPgwbzsZ
- Previous State: Whitelist Enabled = false, 0 addresses
- New State: Whitelist Enabled = true, 0 addresses
- Timestamp: `2025-12-23`
- Notes: `Whitelist enabled successfully`

```
============================================================
TOGGLE WHITELIST
============================================================

Configuration:
- Program ID: GadmXgM1J4NhkbqbpnAbEQxHssZAavWxG5uV6AHiLMHv
- Pool PDA: 5QoFtuiVkt5cXcBxmPUGp1waq3b9H5Q9RgKTpV3NcjEh
- Whitelist PDA: 9bEDjK1LWyi9dxWcW2qNbYqc6MWTmwoMuX6qucEyJTmm
- Pause Authority: 13V7ou4zHHwDVaAGWxqHSwU2sVzRR4m62XWqCFxhA5fD
- Your Wallet: 13V7ou4zHHwDVaAGWxqHSwU2sVzRR4m62XWqCFxhA5fD

Current State:
- Whitelist Enabled: false
- Addresses in Whitelist: 0

Setting whitelist to: ENABLED
Sending transaction...

✅ Whitelist toggled successfully!

Transaction Details:
- Signature: 5g5b4anEQLuHxjpPRQGfz9dg9CuLDjzWiQmCtZZt61UA7yurQhFUF4pC95eXTdWErEdoreimd7szZU2QHPgwbzsZ
- Explorer: https://solscan.io/tx/5g5b4anEQLuHxjpPRQGfz9dg9CuLDjzWiQmCtZZt61UA7yurQhFUF4pC95eXTdWErEdoreimd7szZU2QHPgwbzsZ

New State:
- Whitelist Enabled: true

============================================================
✅ Complete!
============================================================
✨  Done in 2.09s.
```

---

### ✅ Step 8.2: Test Swap (Not Whitelisted - Should Fail)

**Command:**
```bash
yarn ts-node scripts/04-test-swap.ts EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v 9gJ94RYM3kUbFyKzzXAaGaRQ4n39XrDCLPZ1XnpZhnms 1 9TcjK2ToqoAtCr5jrLdDXNTNbZBbDQB1zy2BNGMr7nQE
```

**Result:**
- [x] Completed
- Transaction: Failed (as expected)
- Error Code: `NotWhitelisted (0x177f)`
- Error Message: `User address is not whitelisted`
- Error Location: `programs/scaas-liquidity/src/lib.rs:181`
- Compute Units Used: 32,185
- Notes: `✅ Whitelist enforcement working correctly - swap blocked for non-whitelisted user`

```
❌ Error performing swap:
SendTransactionError: Simulation failed.
Message: Transaction simulation failed: Error processing Instruction 0: custom program error: 0x177f.
Logs:
[
  "Program GadmXgM1J4NhkbqbpnAbEQxHssZAavWxG5uV6AHiLMHv invoke [1]",
  "Program log: Instruction: Swap",
  "Program log: AnchorError thrown in programs/scaas-liquidity/src/lib.rs:181. Error Code: NotWhitelisted. Error Number: 6015. Error Message: User address is not whitelisted.",
  "Program GadmXgM1J4NhkbqbpnAbEQxHssZAavWxG5uV6AHiLMHv consumed 32185 of 200000 compute units",
  "Program GadmXgM1J4NhkbqbpnAbEQxHssZAavWxG5uV6AHiLMHv failed: custom program error: 0x177f"
]
```

---

### ✅ Step 8.3: Add Address to Whitelist

**Command:**
```bash
yarn ts-node scripts/whitelist-add.ts 13V7ou4zHHwDVaAGWxqHSwU2sVzRR4m62XWqCFxhA5fD
```

**Result:**
- [x] Completed
- Transaction Signature: `33bbtPQoj1Jx8yD48JJVEiTYENL7Ydah3ykSUvQSqUPqytWNiuK449YbJvw9kFx87YTTsxL3rjNC8RPs4BRYC5DK`
- Explorer: https://solscan.io/tx/33bbtPQoj1Jx8yD48JJVEiTYENL7Ydah3ykSUvQSqUPqytWNiuK449YbJvw9kFx87YTTsxL3rjNC8RPs4BRYC5DK
- Address Added: `13V7ou4zHHwDVaAGWxqHSwU2sVzRR4m62XWqCFxhA5fD`
- Whitelist Count: 1 address
- Notes: `Address added successfully to whitelist`

```
============================================================
ADD TO WHITELIST
============================================================

Configuration:
- Program ID: GadmXgM1J4NhkbqbpnAbEQxHssZAavWxG5uV6AHiLMHv
- Pool PDA: 5QoFtuiVkt5cXcBxmPUGp1waq3b9H5Q9RgKTpV3NcjEh
- Whitelist PDA: 9bEDjK1LWyi9dxWcW2qNbYqc6MWTmwoMuX6qucEyJTmm
- Pause Authority: 13V7ou4zHHwDVaAGWxqHSwU2sVzRR4m62XWqCFxhA5fD
- Your Wallet: 13V7ou4zHHwDVaAGWxqHSwU2sVzRR4m62XWqCFxhA5fD

Current Whitelist State:
- Enabled: true
- Current Addresses: 0

Adding 1 address(es) to whitelist:
  1. 13V7ou4zHHwDVaAGWxqHSwU2sVzRR4m62XWqCFxhA5fD

Adding 13V7ou4zHHwDVaAGWxqHSwU2sVzRR4m62XWqCFxhA5fD...
✅ Added successfully! Tx: 33bbtPQoj1Jx8yD48JJVEiTYENL7Ydah3ykSUvQSqUPqytWNiuK449YbJvw9kFx87YTTsxL3rjNC8RPs4BRYC5DK

============================================================
Summary:
- Successfully added: 1
- Already whitelisted: 0
- Failed: 0
============================================================

Updated Whitelist:
- Total Addresses: 1
  1. 13V7ou4zHHwDVaAGWxqHSwU2sVzRR4m62XWqCFxhA5fD
✨  Done in 1.82s.
```

---

### ✅ Step 8.4: Test Swap to Different Recipient (Whitelisted - Should Succeed)

**Command:**
```bash
yarn ts-node scripts/04-test-swap.ts EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v 9gJ94RYM3kUbFyKzzXAaGaRQ4n39XrDCLPZ1XnpZhnms 1 9TcjK2ToqoAtCr5jrLdDXNTNbZBbDQB1zy2BNGMr7nQE
```

**Result:**
- [x] Completed
- Transaction Signature: `5VXKcrkDs4sV2vixN6pXJy2sQyTPTAjj2n9gc3scUEcFwL5PBKGysEypLT6XM6NipLeJk7wv8ESiQKd2xBU74eco`
- Explorer: https://solscan.io/tx/5VXKcrkDs4sV2vixN6pXJy2sQyTPTAjj2n9gc3scUEcFwL5PBKGysEypLT6XM6NipLeJk7wv8ESiQKd2xBU74eco
- Signer: `13V7ou4zHHwDVaAGWxqHSwU2sVzRR4m62XWqCFxhA5fD` (whitelisted)
- Recipient: `9TcjK2ToqoAtCr5jrLdDXNTNbZBbDQB1zy2BNGMr7nQE`
- Input: 1 USDC
- Output: 1 Custom Token (to recipient)
- Notes: `Transaction timed out but succeeded. ✅ Whitelist allows whitelisted signer to swap to any recipient`

---

### ✅ Step 8.5: Test Swap to Own Account (Whitelisted - Should Succeed)

**Command:**
```bash
yarn ts-node scripts/04-test-swap.ts EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v 9gJ94RYM3kUbFyKzzXAaGaRQ4n39XrDCLPZ1XnpZhnms 1
```

**Result:**
- [x] Completed
- Transaction Signature: `4CyDgxvhsU9YstgiVzpiF8tNjEmhhuY2Bh8vvDXanr9HzbsrqyLfPARZRyQfXRGkD1nWZYc3cG4WADLu7MrQA3BB`
- Explorer: https://solscan.io/tx/4CyDgxvhsU9YstgiVzpiF8tNjEmhhuY2Bh8vvDXanr9HzbsrqyLfPARZRyQfXRGkD1nWZYc3cG4WADLu7MrQA3BB
- Input: 1 USDC
- Output: 1 Custom Token
- Balance Before: 3 USDC, 15 Custom Token
- Balance After: 2 USDC, 16 Custom Token
- Exchange Rate: 1:1 (0% fee)
- Notes: `✅ Swap successful with whitelisted address`

```
yarn ts-node scripts/04-test-swap.ts EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v 9gJ94RYM3kUbFyKzzXAaGaRQ4n39XrDCLPZ1XnpZhnms 1
yarn run v1.22.22
$ /Users/salioudiallo/base/stablecoin-liquidity-audit/node_modules/.bin/ts-node scripts/04-test-swap.ts EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v 9gJ94RYM3kUbFyKzzXAaGaRQ4n39XrDCLPZ1XnpZhnms 1
============================================================
TEST SWAP
============================================================

Configuration:
- Program ID: GadmXgM1J4NhkbqbpnAbEQxHssZAavWxG5uV6AHiLMHv
- Pool PDA: 5QoFtuiVkt5cXcBxmPUGp1waq3b9H5Q9RgKTpV3NcjEh
- User: 13V7ou4zHHwDVaAGWxqHSwU2sVzRR4m62XWqCFxhA5fD

Swap Details:
- From Token: EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v
- To Token: 9gJ94RYM3kUbFyKzzXAaGaRQ4n39XrDCLPZ1XnpZhnms
- Amount In: 1 tokens
- Amount In (base units): 1000000
- Min Amount Out (base units): 990000
- From Decimals: 6
- To Decimals: 6

Your Balance (From Token): 3 tokens
Your Balance (To Token): 15 tokens

Sending transaction...
✅ Swap successful!

Transaction Details:
- Signature: 4CyDgxvhsU9YstgiVzpiF8tNjEmhhuY2Bh8vvDXanr9HzbsrqyLfPARZRyQfXRGkD1nWZYc3cG4WADLu7MrQA3BB
- Explorer: https://solscan.io/tx/4CyDgxvhsU9YstgiVzpiF8tNjEmhhuY2Bh8vvDXanr9HzbsrqyLfPARZRyQfXRGkD1nWZYc3cG4WADLu7MrQA3BB

Your Balance After (From Token): 2 tokens
Your Balance After (To Token): 16 tokens

============================================================
✅ Swap complete!
============================================================
✨  Done in 3.38s.
```

---

### ✅ Step 8.6: Remove Address from Whitelist

**Command:**
```bash
yarn ts-node scripts/whitelist-remove.ts 13V7ou4zHHwDVaAGWxqHSwU2sVzRR4m62XWqCFxhA5fD
```

**Result:**
- [x] Completed
- Transaction Signature: `5Vz6ATKEVobHYjiS2vDe6P8HMu53Xf77F52SYErSRL73cEX4C4mvnBz67rZaFtisb62qWny4DmcmhTj4iz1yRMYo`
- Explorer: https://solscan.io/tx/5Vz6ATKEVobHYjiS2vDe6P8HMu53Xf77F52SYErSRL73cEX4C4mvnBz67rZaFtisb62qWny4DmcmhTj4iz1yRMYo
- Address Removed: `13V7ou4zHHwDVaAGWxqHSwU2sVzRR4m62XWqCFxhA5fD`
- Whitelist Count: 0 addresses
- Notes: `Transaction timed out but succeeded. Address removed from whitelist`

---

### ✅ Step 8.7: Verify Pool State (Whitelist Enabled, Empty)

**Command:**
```bash
yarn ts-node scripts/verify-pool.ts
```

**Result:**
- [x] Completed
- Whitelist Enabled: true
- Whitelist Addresses: 0 (empty)
- Custom Token Liquidity: 0 tokens
- USDC Liquidity: 10 tokens
- Notes: `Whitelist is enabled but empty - no addresses allowed to swap`

---

### ✅ Step 8.8: Test Swap (Removed from Whitelist - Should Fail)

**Command:**
```bash
yarn ts-node scripts/04-test-swap.ts EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v 9gJ94RYM3kUbFyKzzXAaGaRQ4n39XrDCLPZ1XnpZhnms 1
```

**Result:**
- [x] Completed
- Transaction: Failed (as expected)
- Error Code: `NotWhitelisted (0x177f)`
- Error Message: `User address is not whitelisted`
- Error Location: `programs/scaas-liquidity/src/lib.rs:181`
- Compute Units Used: 32,185
- Notes: `✅ Whitelist enforcement working correctly - swap blocked after address removed`

---

### ✅ Step 8.9: Disable Whitelist

**Command:**
```bash
yarn ts-node scripts/whitelist-toggle.ts false
```

**Result:**
- [x] Completed
- Transaction Signature: `BbK3E4CF5m3NDCkz5VP7r2iyubaNM9hvH14vjRXBfC5ZCjgt3kK2mSMHmw4xiwkPSCTFGXtVDm2K9DgCeYgPvW6`
- Explorer: https://solscan.io/tx/BbK3E4CF5m3NDCkz5VP7r2iyubaNM9hvH14vjRXBfC5ZCjgt3kK2mSMHmw4xiwkPSCTFGXtVDm2K9DgCeYgPvW6
- Previous State: Whitelist Enabled = true
- New State: Whitelist Enabled = false
- Notes: `Transaction timed out but succeeded. Whitelist disabled - permissionless swaps restored`

---

### ✅ Step 8.10: Verify Pool State (Whitelist Disabled)

**Command:**
```bash
yarn ts-node scripts/verify-pool.ts
```

**Result:**
- [x] Completed
- Whitelist Enabled: false
- Whitelist Addresses: 0
- Custom Token Liquidity: 0 tokens
- USDC Liquidity: 10 tokens
- Notes: `Whitelist disabled - anyone can swap`

---

### ✅ Step 8.11: Test Swap (Whitelist Disabled - Should Succeed)

**Command:**
```bash
yarn ts-node scripts/04-test-swap.ts 9gJ94RYM3kUbFyKzzXAaGaRQ4n39XrDCLPZ1XnpZhnms EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v 1
```

**Result:**
- [x] Completed
- Transaction Signature: `fpexdNQ3vz8eNRHpbBvxY8fx7pgjRkk9m5XqJmtYLnbUfwGQtrz9aT1QRaHsrUFnc7A2kD3eTbWQhEWvuNFJygg`
- Explorer: https://solscan.io/tx/fpexdNQ3vz8eNRHpbBvxY8fx7pgjRkk9m5XqJmtYLnbUfwGQtrz9aT1QRaHsrUFnc7A2kD3eTbWQhEWvuNFJygg
- Input: 1 Custom Token
- Output: 1 USDC
- Balance Before: 16 Custom Token, 2 USDC
- Balance After: 15 Custom Token, 3 USDC
- Exchange Rate: 1:1 (0% fee)
- Notes: `✅ Swap successful with whitelist disabled - permissionless mode restored. Note: Swapped in reverse direction due to insufficient custom token liquidity`

```
yarn ts-node scripts/04-test-swap.ts 9gJ94RYM3kUbFyKzzXAaGaRQ4n39XrDCLPZ1XnpZhnms EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v 1
yarn run v1.22.22
$ /Users/salioudiallo/base/stablecoin-liquidity-audit/node_modules/.bin/ts-node scripts/04-test-swap.ts 9gJ94RYM3kUbFyKzzXAaGaRQ4n39XrDCLPZ1XnpZhnms EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v 1
============================================================
TEST SWAP
============================================================

Configuration:
- Program ID: GadmXgM1J4NhkbqbpnAbEQxHssZAavWxG5uV6AHiLMHv
- Pool PDA: 5QoFtuiVkt5cXcBxmPUGp1waq3b9H5Q9RgKTpV3NcjEh
- User: 13V7ou4zHHwDVaAGWxqHSwU2sVzRR4m62XWqCFxhA5fD

Swap Details:
- From Token: 9gJ94RYM3kUbFyKzzXAaGaRQ4n39XrDCLPZ1XnpZhnms
- To Token: EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v
- Amount In: 1 tokens
- Amount In (base units): 1000000
- Min Amount Out (base units): 990000
- From Decimals: 6
- To Decimals: 6

Your Balance (From Token): 16 tokens
Your Balance (To Token): 2 tokens

Sending transaction...
✅ Swap successful!

Transaction Details:
- Signature: fpexdNQ3vz8eNRHpbBvxY8fx7pgjRkk9m5XqJmtYLnbUfwGQtrz9aT1QRaHsrUFnc7A2kD3eTbWQhEWvuNFJygg
- Explorer: https://solscan.io/tx/fpexdNQ3vz8eNRHpbBvxY8fx7pgjRkk9m5XqJmtYLnbUfwGQtrz9aT1QRaHsrUFnc7A2kD3eTbWQhEWvuNFJygg

Your Balance After (From Token): 15 tokens
Your Balance After (To Token): 3 tokens

============================================================
✅ Swap complete!
============================================================
✨  Done in 5.13s.
```

---

### Whitelist Testing Summary

**All Tests Passed:** ✅

| Test | Expected | Actual | Result |
|------|----------|--------|--------|
| Enable whitelist | Enabled | Enabled | ✅ Pass |
| Swap (not whitelisted) | Fail | Failed (NotWhitelisted) | ✅ Pass |
| Add to whitelist | Added | Added (1 address) | ✅ Pass |
| Swap to different recipient (whitelisted) | Success | Success | ✅ Pass |
| Swap to own account (whitelisted) | Success | Success | ✅ Pass |
| Remove from whitelist | Removed | Removed (0 addresses) | ✅ Pass |
| Swap (removed from whitelist) | Fail | Failed (NotWhitelisted) | ✅ Pass |
| Disable whitelist | Disabled | Disabled | ✅ Pass |
| Swap (whitelist disabled) | Success | Success | ✅ Pass |

**Key Findings:**
1. ✅ Whitelist enforcement works correctly - blocks non-whitelisted signers
2. ✅ Whitelist validates transaction SIGNER, not token owner - enables delegation
3. ✅ Whitelisted signer can swap to any recipient address
4. ✅ Toggle functionality works bidirectionally (enable/disable)
5. ✅ Add/remove address functionality works correctly
6. ⚠️ Some transactions experienced timeout but succeeded (mainnet congestion)

**Whitelist Transactions:**
- Enable: `5g5b4anEQLuHxjpPRQGfz9dg9CuLDjzWiQmCtZZt61UA7yurQhFUF4pC95eXTdWErEdoreimd7szZU2QHPgwbzsZ`
- Add address: `33bbtPQoj1Jx8yD48JJVEiTYENL7Ydah3ykSUvQSqUPqytWNiuK449YbJvw9kFx87YTTsxL3rjNC8RPs4BRYC5DK`
- Swap (whitelisted, delegation): `5VXKcrkDs4sV2vixN6pXJy2sQyTPTAjj2n9gc3scUEcFwL5PBKGysEypLT6XM6NipLeJk7wv8ESiQKd2xBU74eco`
- Swap (whitelisted, own account): `4CyDgxvhsU9YstgiVzpiF8tNjEmhhuY2Bh8vvDXanr9HzbsrqyLfPARZRyQfXRGkD1nWZYc3cG4WADLu7MrQA3BB`
- Remove address: `5Vz6ATKEVobHYjiS2vDe6P8HMu53Xf77F52SYErSRL73cEX4C4mvnBz67rZaFtisb62qWny4DmcmhTj4iz1yRMYo`
- Disable: `BbK3E4CF5m3NDCkz5VP7r2iyubaNM9hvH14vjRXBfC5ZCjgt3kK2mSMHmw4xiwkPSCTFGXtVDm2K9DgCeYgPvW6`
- Swap (disabled): `fpexdNQ3vz8eNRHpbBvxY8fx7pgjRkk9m5XqJmtYLnbUfwGQtrz9aT1QRaHsrUFnc7A2kD3eTbWQhEWvuNFJygg`

---

## PHASE 9: Emergency Pause Testing

### ✅ Step 9.1: Pause Swaps

**Command:**
```bash
yarn ts-node scripts/emergency-pause-swaps.ts
```

**Result:**
- [x] Completed
- Transaction Signature: `3sXpiSANtWA7XBDVbBCqJeaMSLGJm79YNWctVzaotzcGbqnwf6oQuhvPNjQZM1sYwUGRna58hf38BDsqqK7XqgTA`
- Explorer: https://solscan.io/tx/3sXpiSANtWA7XBDVbBCqJeaMSLGJm79YNWctVzaotzcGbqnwf6oQuhvPNjQZM1sYwUGRna58hf38BDsqqK7XqgTA
- Previous State: Swaps Paused = false
- New State: Swaps Paused = true
- Timestamp: `2025-12-23`
- Notes: `Emergency pause activated successfully`

```
============================================================
EMERGENCY PAUSE SWAPS
============================================================

Configuration:
- Program ID: GadmXgM1J4NhkbqbpnAbEQxHssZAavWxG5uV6AHiLMHv
- Pool PDA: 5QoFtuiVkt5cXcBxmPUGp1waq3b9H5Q9RgKTpV3NcjEh
- Pause Authority: 13V7ou4zHHwDVaAGWxqHSwU2sVzRR4m62XWqCFxhA5fD
- Your Wallet: 13V7ou4zHHwDVaAGWxqHSwU2sVzRR4m62XWqCFxhA5fD

Current State:
- Swaps Paused: false
- Liquidity Paused: false

⚠️  PAUSING SWAPS
Sending transaction...

🛑 Swaps paused successfully!

Transaction Details:
- Signature: 3sXpiSANtWA7XBDVbBCqJeaMSLGJm79YNWctVzaotzcGbqnwf6oQuhvPNjQZM1sYwUGRna58hf38BDsqqK7XqgTA
- Explorer: https://solscan.io/tx/3sXpiSANtWA7XBDVbBCqJeaMSLGJm79YNWctVzaotzcGbqnwf6oQuhvPNjQZM1sYwUGRna58hf38BDsqqK7XqgTA

New State:
- Swaps Paused: true

============================================================
🛑 SWAPS PAUSED
============================================================
✨  Done in 1.49s.
```

---

### ✅ Step 9.2: Test Swap (Paused - Should Fail)

**Command:**
```bash
yarn ts-node scripts/04-test-swap.ts 9gJ94RYM3kUbFyKzzXAaGaRQ4n39XrDCLPZ1XnpZhnms EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v 1
```

**Result:**
- [x] Completed
- Transaction: Failed (as expected)
- Error Code: `SwapsPaused (0x1770)`
- Error Message: `Swaps are paused`
- Error Location: `programs/scaas-liquidity/src/lib.rs:167`
- Compute Units Used: 33,431
- Notes: `✅ Emergency pause working correctly - swap blocked when paused`

```
❌ Error performing swap:
SendTransactionError: Simulation failed.
Message: Transaction simulation failed: Error processing Instruction 0: custom program error: 0x1770.
Logs:
[
  "Program GadmXgM1J4NhkbqbpnAbEQxHssZAavWxG5uV6AHiLMHv invoke [1]",
  "Program log: Instruction: Swap",
  "Program log: AnchorError thrown in programs/scaas-liquidity/src/lib.rs:167. Error Code: SwapsPaused. Error Number: 6000. Error Message: Swaps are paused.",
  "Program GadmXgM1J4NhkbqbpnAbEQxHssZAavWxG5uV6AHiLMHv consumed 33431 of 200000 compute units",
  "Program GadmXgM1J4NhkbqbpnAbEQxHssZAavWxG5uV6AHiLMHv failed: custom program error: 0x1770"
]
```

---

### ✅ Step 9.3: Unpause Swaps

**Command:**
```bash
yarn ts-node scripts/emergency-pause-swaps.ts false
```

**Result:**
- [x] Completed
- Transaction Signature: `2bBjZSWDdPfmpobeMzNH1MWnbAahyrztYMproE4FEmbYvtEkqXr7XeD1Uz5xiAhUqnZRe3v5tNeoFJ4tPquEUhkW`
- Explorer: https://solscan.io/tx/2bBjZSWDdPfmpobeMzNH1MWnbAahyrztYMproE4FEmbYvtEkqXr7XeD1Uz5xiAhUqnZRe3v5tNeoFJ4tPquEUhkW
- Previous State: Swaps Paused = true
- New State: Swaps Paused = false
- Timestamp: `2025-12-23`
- Notes: `Emergency pause lifted - normal operations restored`

```
============================================================
EMERGENCY PAUSE SWAPS
============================================================

Configuration:
- Program ID: GadmXgM1J4NhkbqbpnAbEQxHssZAavWxG5uV6AHiLMHv
- Pool PDA: 5QoFtuiVkt5cXcBxmPUGp1waq3b9H5Q9RgKTpV3NcjEh
- Pause Authority: 13V7ou4zHHwDVaAGWxqHSwU2sVzRR4m62XWqCFxhA5fD
- Your Wallet: 13V7ou4zHHwDVaAGWxqHSwU2sVzRR4m62XWqCFxhA5fD

Current State:
- Swaps Paused: true
- Liquidity Paused: false

✅ UNPAUSING SWAPS
Sending transaction...

✅ Swaps unpaused successfully!

Transaction Details:
- Signature: 2bBjZSWDdPfmpobeMzNH1MWnbAahyrztYMproE4FEmbYvtEkqXr7XeD1Uz5xiAhUqnZRe3v5tNeoFJ4tPquEUhkW
- Explorer: https://solscan.io/tx/2bBjZSWDdPfmpobeMzNH1MWnbAahyrztYMproE4FEmbYvtEkqXr7XeD1Uz5xiAhUqnZRe3v5tNeoFJ4tPquEUhkW

New State:
- Swaps Paused: false

============================================================
✅ SWAPS RESTORED
============================================================
✨  Done in 2.21s.
```

---

### ✅ Step 9.4: Test Swap (Unpaused - Should Succeed)

**Command:**
```bash
yarn ts-node scripts/04-test-swap.ts 9gJ94RYM3kUbFyKzzXAaGaRQ4n39XrDCLPZ1XnpZhnms EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v 1
```

**Result:**
- [x] Completed
- Transaction Signature: `2SKpcXUSRydoHJiGvW5QsmM1wReFosHE7iLikqLyYeq6h2RCQk9cB2kso6f7rRZ1Dgaiky8a4ivghqimFmhNhLSg`
- Explorer: https://solscan.io/tx/2SKpcXUSRydoHJiGvW5QsmM1wReFosHE7iLikqLyYeq6h2RCQk9cB2kso6f7rRZ1Dgaiky8a4ivghqimFmhNhLSg
- Input: 1 Custom Token
- Output: 1 USDC
- Balance Before: 10 Custom Token, 8 USDC
- Balance After: 9 Custom Token, 9 USDC
- Exchange Rate: 1:1 (0% fee)
- Notes: `✅ Swap successful after unpausing - emergency procedures verified`

```
============================================================
TEST SWAP
============================================================

Configuration:
- Program ID: GadmXgM1J4NhkbqbpnAbEQxHssZAavWxG5uV6AHiLMHv
- Pool PDA: 5QoFtuiVkt5cXcBxmPUGp1waq3b9H5Q9RgKTpV3NcjEh
- User (Signer): 13V7ou4zHHwDVaAGWxqHSwU2sVzRR4m62XWqCFxhA5fD

Swap Details:
- From Token: 9gJ94RYM3kUbFyKzzXAaGaRQ4n39XrDCLPZ1XnpZhnms
- To Token: EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v
- Amount In: 1 tokens
- Amount In (base units): 1000000
- Min Amount Out (base units): 990000
- From Decimals: 6
- To Decimals: 6

Your Balance (From Token): 10 tokens
Your Balance (To Token): 8 tokens

Sending transaction...
✅ Swap successful!

Transaction Details:
- Signature: 2SKpcXUSRydoHJiGvW5QsmM1wReFosHE7iLikqLyYeq6h2RCQk9cB2kso6f7rRZ1Dgaiky8a4ivghqimFmhNhLSg
- Explorer: https://solscan.io/tx/2SKpcXUSRydoHJiGvW5QsmM1wReFosHE7iLikqLyYeq6h2RCQk9cB2kso6f7rRZ1Dgaiky8a4ivghqimFmhNhLSg

Your Balance After (From Token): 9 tokens
Your Balance After (To Token): 9 tokens

============================================================
✅ Swap complete!
============================================================
✨  Done in 5.86s.
```

---

### Emergency Pause Testing Summary

**All Tests Passed:** ✅

| Test | Expected | Actual | Result |
|------|----------|--------|--------|
| Pause swaps | Paused | Paused | ✅ Pass |
| Swap (paused) | Fail | Failed (SwapsPaused) | ✅ Pass |
| Unpause swaps | Unpaused | Unpaused | ✅ Pass |
| Swap (unpaused) | Success | Success | ✅ Pass |

**Key Findings:**
1. ✅ Emergency pause mechanism works correctly
2. ✅ Swaps are blocked when paused (error 0x1770)
3. ✅ Pause can be toggled bidirectionally (pause/unpause)
4. ✅ Normal operations resume after unpausing
5. ✅ Only pause_authority can execute pause operations

**Emergency Pause Transactions:**
- Pause swaps: `3sXpiSANtWA7XBDVbBCqJeaMSLGJm79YNWctVzaotzcGbqnwf6oQuhvPNjQZM1sYwUGRna58hf38BDsqqK7XqgTA`
- Unpause swaps: `2bBjZSWDdPfmpobeMzNH1MWnbAahyrztYMproE4FEmbYvtEkqXr7XeD1Uz5xiAhUqnZRe3v5tNeoFJ4tPquEUhkW`
- Swap (after unpause): `2SKpcXUSRydoHJiGvW5QsmM1wReFosHE7iLikqLyYeq6h2RCQk9cB2kso6f7rRZ1Dgaiky8a4ivghqimFmhNhLSg`

---

## PHASE 10: Liquidity Pause Testing

### ✅ Step 10.1: Pause Liquidity Operations

**Command:**
```bash
yarn ts-node scripts/emergency-pause-liquidity.ts
```

**Result:**
- [x] Completed
- Transaction Signature: `4XeTPiKxmvuXNd1YZi9TFYQCxXAN1Eo7SdVq18ErsJQpX9Li3Lc9HirbG3AQL53yEURRhCf7vppvw3FRfX7miwTe`
- Explorer: https://solscan.io/tx/4XeTPiKxmvuXNd1YZi9TFYQCxXAN1Eo7SdVq18ErsJQpX9Li3Lc9HirbG3AQL53yEURRhCf7vppvw3FRfX7miwTe
- Previous State: Liquidity Paused = false
- New State: Liquidity Paused = true
- Timestamp: `2025-12-23`
- Notes: `Liquidity operations paused successfully`

```
============================================================
EMERGENCY PAUSE LIQUIDITY
============================================================

Configuration:
- Program ID: GadmXgM1J4NhkbqbpnAbEQxHssZAavWxG5uV6AHiLMHv
- Pool PDA: 5QoFtuiVkt5cXcBxmPUGp1waq3b9H5Q9RgKTpV3NcjEh
- Pause Authority: 13V7ou4zHHwDVaAGWxqHSwU2sVzRR4m62XWqCFxhA5fD
- Your Wallet: 13V7ou4zHHwDVaAGWxqHSwU2sVzRR4m62XWqCFxhA5fD

Current State:
- Swaps Paused: false
- Liquidity Paused: false

⚠️  PAUSING LIQUIDITY OPERATIONS
Sending transaction...

🛑 Liquidity operations paused successfully!

Transaction Details:
- Signature: 4XeTPiKxmvuXNd1YZi9TFYQCxXAN1Eo7SdVq18ErsJQpX9Li3Lc9HirbG3AQL53yEURRhCf7vppvw3FRfX7miwTe
- Explorer: https://solscan.io/tx/4XeTPiKxmvuXNd1YZi9TFYQCxXAN1Eo7SdVq18ErsJQpX9Li3Lc9HirbG3AQL53yEURRhCf7vppvw3FRfX7miwTe

New State:
- Liquidity Paused: true

============================================================
🛑 LIQUIDITY PAUSED
============================================================
✨  Done in 2.79s.
```

---

### ✅ Step 10.2: Test Deposit (Paused - Should Fail)

**Command:**
```bash
yarn ts-node scripts/03-deposit-liquidity.ts 9gJ94RYM3kUbFyKzzXAaGaRQ4n39XrDCLPZ1XnpZhnms 1
```

**Result:**
- [x] Completed
- Transaction: Failed (as expected)
- Error Code: `LiquidityPaused (0x1771)`
- Error Message: `Liquidity management is paused`
- Error Location: `programs/scaas-liquidity/src/lib.rs:143`
- Compute Units Used: 17,162
- Notes: `✅ Liquidity pause working correctly - deposit blocked when paused`

```
❌ Error depositing liquidity:
AnchorError: AnchorError thrown in programs/scaas-liquidity/src/lib.rs:143. Error Code: LiquidityPaused. Error Number: 6001. Error Message: Liquidity management is paused.

Program Logs:
Program GadmXgM1J4NhkbqbpnAbEQxHssZAavWxG5uV6AHiLMHv invoke [1]
Program log: Instruction: DepositLiquidity
Program log: AnchorError thrown in programs/scaas-liquidity/src/lib.rs:143. Error Code: LiquidityPaused. Error Number: 6001. Error Message: Liquidity management is paused.
Program GadmXgM1J4NhkbqbpnAbEQxHssZAavWxG5uV6AHiLMHv consumed 17162 of 200000 compute units
Program GadmXgM1J4NhkbqbpnAbEQxHssZAavWxG5uV6AHiLMHv failed: custom program error: 0x1771
```

---

### ✅ Step 10.3: Unpause Liquidity Operations

**Command:**
```bash
yarn ts-node scripts/emergency-pause-liquidity.ts false
```

**Result:**
- [x] Completed
- Transaction Signature: `2xgDjKSuN7EHaA1WrhwTLqpVH2S7drkRqsdeUfxoktsiE9Qz78RWk8vAcrpEjJm1Y7SbBoPw49gnrWVkS6fybYV8`
- Explorer: https://solscan.io/tx/2xgDjKSuN7EHaA1WrhwTLqpVH2S7drkRqsdeUfxoktsiE9Qz78RWk8vAcrpEjJm1Y7SbBoPw49gnrWVkS6fybYV8
- Previous State: Liquidity Paused = true
- New State: Liquidity Paused = false
- Timestamp: `2025-12-23`
- Notes: `Liquidity operations restored successfully`

```
============================================================
EMERGENCY PAUSE LIQUIDITY
============================================================

Configuration:
- Program ID: GadmXgM1J4NhkbqbpnAbEQxHssZAavWxG5uV6AHiLMHv
- Pool PDA: 5QoFtuiVkt5cXcBxmPUGp1waq3b9H5Q9RgKTpV3NcjEh
- Pause Authority: 13V7ou4zHHwDVaAGWxqHSwU2sVzRR4m62XWqCFxhA5fD
- Your Wallet: 13V7ou4zHHwDVaAGWxqHSwU2sVzRR4m62XWqCFxhA5fD

Current State:
- Swaps Paused: false
- Liquidity Paused: true

✅ UNPAUSING LIQUIDITY OPERATIONS
Sending transaction...

✅ Liquidity operations unpaused successfully!

Transaction Details:
- Signature: 2xgDjKSuN7EHaA1WrhwTLqpVH2S7drkRqsdeUfxoktsiE9Qz78RWk8vAcrpEjJm1Y7SbBoPw49gnrWVkS6fybYV8
- Explorer: https://solscan.io/tx/2xgDjKSuN7EHaA1WrhwTLqpVH2S7drkRqsdeUfxoktsiE9Qz78RWk8vAcrpEjJm1Y7SbBoPw49gnrWVkS6fybYV8

New State:
- Liquidity Paused: false

============================================================
✅ LIQUIDITY RESTORED
============================================================
✨  Done in 3.27s.
```

---

### ✅ Step 10.4: Test Deposit (Unpaused - Should Succeed)

**Command:**
```bash
yarn ts-node scripts/03-deposit-liquidity.ts 9gJ94RYM3kUbFyKzzXAaGaRQ4n39XrDCLPZ1XnpZhnms 1
```

**Result:**
- [x] Completed
- Transaction Signature: `KMGuXJeVRQCXYcygXcUnMeSUGmRULi1VBfZt1JxcAX7TG1CkgMeiWQRimxCRxbCnt22YizCmKjJAEMdBiV4Lv8M`
- Explorer: https://solscan.io/tx/KMGuXJeVRQCXYcygXcUnMeSUGmRULi1VBfZt1JxcAX7TG1CkgMeiWQRimxCRxbCnt22YizCmKjJAEMdBiV4Lv8M
- Amount Deposited: 1 Custom Token
- Vault Balance Before: 7 tokens
- Vault Balance After: 8 tokens
- Notes: `✅ Deposit successful after unpausing - liquidity pause verified`

```
============================================================
DEPOSITING LIQUIDITY
============================================================

Configuration:
- Program ID: GadmXgM1J4NhkbqbpnAbEQxHssZAavWxG5uV6AHiLMHv
- Pool PDA: 5QoFtuiVkt5cXcBxmPUGp1waq3b9H5Q9RgKTpV3NcjEh
- Token Mint: 9gJ94RYM3kUbFyKzzXAaGaRQ4n39XrDCLPZ1XnpZhnms
- Token Decimals: 6
- Vault PDA: EPFgtsNL4VVqwbh6cPwFoWCoqjW1WQvgbRAcitV49HYH
- Vault Token Account: 3y6MPgBvQqCS5EJkWE8w6dYwVLT3sue4s6inP8AoAkJv
- Operations Authority: 13V7ou4zHHwDVaAGWxqHSwU2sVzRR4m62XWqCFxhA5fD
- Operations Authority Token Account: A7vP6Ut36Tmc94ACNBPKWjfiPZPeSsadw8jYqSbKEdBk

Deposit Details:
- Amount (tokens): 1
- Amount (base units): 1000000

Your Balance: 9 tokens
Vault Balance Before: 7 tokens

Sending transaction...
✅ Liquidity deposited successfully!

Transaction Details:
- Signature: KMGuXJeVRQCXYcygXcUnMeSUGmRULi1VBfZt1JxcAX7TG1CkgMeiWQRimxCRxbCnt22YizCmKjJAEMdBiV4Lv8M
- Explorer: https://solscan.io/tx/KMGuXJeVRQCXYcygXcUnMeSUGmRULi1VBfZt1JxcAX7TG1CkgMeiWQRimxCRxbCnt22YizCmKjJAEMdBiV4Lv8M

Vault Balance After: 8 tokens
Amount Deposited: 1 tokens

============================================================
✅ Deposit complete!
============================================================
✨  Done in 3.76s.
```

---

### ✅ Step 10.5: Pause Liquidity Again (For Withdrawal Test)

**Command:**
```bash
yarn ts-node scripts/emergency-pause-liquidity.ts
```

**Result:**
- [x] Completed
- Transaction Signature: `5PAbgCCSpvqyTHFCFVUKD7v8pV8WVjfW2ccThTfsrUU5UPNajq95dEYtdKAQSCyVgazfW9zJuF4anPmtKCWhUzBi`
- Explorer: https://solscan.io/tx/5PAbgCCSpvqyTHFCFVUKD7v8pV8WVjfW2ccThTfsrUU5UPNajq95dEYtdKAQSCyVgazfW9zJuF4anPmtKCWhUzBi
- Previous State: Liquidity Paused = false
- New State: Liquidity Paused = true
- Timestamp: `2025-12-23`
- Notes: `Liquidity paused for withdrawal testing`

---

### ✅ Step 10.6: Test Withdraw (Paused - Should Fail)

**Command:**
```bash
yarn ts-node scripts/emergency-withdraw.ts 9gJ94RYM3kUbFyKzzXAaGaRQ4n39XrDCLPZ1XnpZhnms 1
```

**Result:**
- [x] Completed
- Transaction: Failed (as expected)
- Error Code: `LiquidityPaused (0x1771)`
- Error Message: `Liquidity management is paused`
- Error Location: `programs/scaas-liquidity/src/lib.rs:317`
- Compute Units Used: 17,167
- Notes: `✅ Liquidity pause correctly blocks withdrawals`

```
❌ Error withdrawing liquidity:
AnchorError: AnchorError thrown in programs/scaas-liquidity/src/lib.rs:317. Error Code: LiquidityPaused. Error Number: 6001. Error Message: Liquidity management is paused.

Program Logs:
Program GadmXgM1J4NhkbqbpnAbEQxHssZAavWxG5uV6AHiLMHv invoke [1]
Program log: Instruction: WithdrawLiquidity
Program log: AnchorError thrown in programs/scaas-liquidity/src/lib.rs:317. Error Code: LiquidityPaused. Error Number: 6001. Error Message: Liquidity management is paused.
Program GadmXgM1J4NhkbqbpnAbEQxHssZAavWxG5uV6AHiLMHv consumed 17167 of 200000 compute units
Program GadmXgM1J4NhkbqbpnAbEQxHssZAavWxG5uV6AHiLMHv failed: custom program error: 0x1771
```

---

### ✅ Step 10.7: Unpause and Withdraw Successfully

**Unpause Command:**
```bash
yarn ts-node scripts/emergency-pause-liquidity.ts false
```

**Unpause Result:**
- [x] Completed
- Transaction Signature: `55oijzSiuUVy4qjDuqWrAG8dfWURgW2L1YNSz2C5wGzsEK248pzG2DyHNH93AGNakGVkNu8GsXbn9rmXuq6ACGiy`
- Explorer: https://solscan.io/tx/55oijzSiuUVy4qjDuqWrAG8dfWURgW2L1YNSz2C5wGzsEK248pzG2DyHNH93AGNakGVkNu8GsXbn9rmXuq6ACGiy
- New State: Liquidity Paused = false

**Withdraw Command:**
```bash
yarn ts-node scripts/emergency-withdraw.ts 9gJ94RYM3kUbFyKzzXAaGaRQ4n39XrDCLPZ1XnpZhnms 1
```

**Withdraw Result:**
- [x] Completed
- Transaction Signature: `4VcUdmRMS4xJLonfF173tRdUWSHjBWeyNgNQm4fEVSfSBjY1ALioDfK5ScQn3m2kY7Gj4c9CQYLizfFJouAZkQeS`
- Explorer: https://solscan.io/tx/4VcUdmRMS4xJLonfF173tRdUWSHjBWeyNgNQm4fEVSfSBjY1ALioDfK5ScQn3m2kY7Gj4c9CQYLizfFJouAZkQeS
- Amount Withdrawn: 1 Custom Token
- Vault Balance Before: 8 tokens
- Vault Balance After: 7 tokens (verified via verify-pool.ts)
- Notes: `Transaction timed out but succeeded. ✅ Withdrawal successful after unpausing`

---

### Liquidity Pause Testing Summary

**All Tests Passed:** ✅

| Test | Expected | Actual | Result |
|------|----------|--------|--------|
| Pause liquidity | Paused | Paused | ✅ Pass |
| Deposit (paused) | Fail | Failed (LiquidityPaused) | ✅ Pass |
| Unpause liquidity | Unpaused | Unpaused | ✅ Pass |
| Deposit (unpaused) | Success | Success | ✅ Pass |
| Pause liquidity (again) | Paused | Paused | ✅ Pass |
| Withdraw (paused) | Fail | Failed (LiquidityPaused) | ✅ Pass |
| Unpause liquidity | Unpaused | Unpaused | ✅ Pass |
| Withdraw (unpaused) | Success | Success | ✅ Pass |

**Key Findings:**
1. ✅ Liquidity pause mechanism works correctly
2. ✅ Deposits are blocked when paused (error 0x1771 at lib.rs:143)
3. ✅ Withdrawals are blocked when paused (error 0x1771 at lib.rs:317)
4. ✅ Pause can be toggled bidirectionally (pause/unpause)
5. ✅ Normal operations resume after unpausing
6. ✅ Only pause_authority can execute pause operations
7. ✅ Both deposit and withdraw respect the same pause flag

**Liquidity Pause Transactions:**
- Pause liquidity (1st): `4XeTPiKxmvuXNd1YZi9TFYQCxXAN1Eo7SdVq18ErsJQpX9Li3Lc9HirbG3AQL53yEURRhCf7vppvw3FRfX7miwTe`
- Unpause liquidity (1st): `2xgDjKSuN7EHaA1WrhwTLqpVH2S7drkRqsdeUfxoktsiE9Qz78RWk8vAcrpEjJm1Y7SbBoPw49gnrWVkS6fybYV8`
- Deposit (after unpause): `KMGuXJeVRQCXYcygXcUnMeSUGmRULi1VBfZt1JxcAX7TG1CkgMeiWQRimxCRxbCnt22YizCmKjJAEMdBiV4Lv8M`
- Pause liquidity (2nd): `5PAbgCCSpvqyTHFCFVUKD7v8pV8WVjfW2ccThTfsrUU5UPNajq95dEYtdKAQSCyVgazfW9zJuF4anPmtKCWhUzBi`
- Unpause liquidity (2nd): `55oijzSiuUVy4qjDuqWrAG8dfWURgW2L1YNSz2C5wGzsEK248pzG2DyHNH93AGNakGVkNu8GsXbn9rmXuq6ACGiy`
- Withdraw (after unpause): `4VcUdmRMS4xJLonfF173tRdUWSHjBWeyNgNQm4fEVSfSBjY1ALioDfK5ScQn3m2kY7Gj4c9CQYLizfFJouAZkQeS`

---

## PHASE 11: Token Disable Testing

### ✅ Step 11.1: Disable Custom Token

**Command:**
```bash
yarn ts-node scripts/update-token-status.ts 9gJ94RYM3kUbFyKzzXAaGaRQ4n39XrDCLPZ1XnpZhnms true
```

**Result:**
- [x] Completed
- Transaction Signature: `2tPVNX1CaVUzuYvbRnAPksmechRFymdd9hnuRkx7fdDsvUvrvU3YsD8cZpsBoVghz6ZtFBdW3AB5p7cqHPfT8PNq`
- Explorer: https://solscan.io/tx/2tPVNX1CaVUzuYvbRnAPksmechRFymdd9hnuRkx7fdDsvUvrvU3YsD8cZpsBoVghz6ZtFBdW3AB5p7cqHPfT8PNq
- Previous State: Token Disabled = false
- New State: Token Disabled = true
- Timestamp: `2025-12-23`
- Notes: `Custom token disabled successfully`

```
============================================================
UPDATE TOKEN STATUS
============================================================

Configuration:
- Program ID: GadmXgM1J4NhkbqbpnAbEQxHssZAavWxG5uV6AHiLMHv
- Pool PDA: 5QoFtuiVkt5cXcBxmPUGp1waq3b9H5Q9RgKTpV3NcjEh
- Token Mint: 9gJ94RYM3kUbFyKzzXAaGaRQ4n39XrDCLPZ1XnpZhnms
- Vault PDA: EPFgtsNL4VVqwbh6cPwFoWCoqjW1WQvgbRAcitV49HYH
- Pause Authority: 13V7ou4zHHwDVaAGWxqHSwU2sVzRR4m62XWqCFxhA5fD
- Your Wallet: 13V7ou4zHHwDVaAGWxqHSwU2sVzRR4m62XWqCFxhA5fD

Current State:
- Token Disabled: false

Setting token to: DISABLED
Sending transaction...

🛑 Token status updated successfully!

Transaction Details:
- Signature: 2tPVNX1CaVUzuYvbRnAPksmechRFymdd9hnuRkx7fdDsvUvrvU3YsD8cZpsBoVghz6ZtFBdW3AB5p7cqHPfT8PNq
- Explorer: https://solscan.io/tx/2tPVNX1CaVUzuYvbRnAPksmechRFymdd9hnuRkx7fdDsvUvrvU3YsD8cZpsBoVghz6ZtFBdW3AB5p7cqHPfT8PNq

New State:
- Token Disabled: true

============================================================
🛑 TOKEN DISABLED
============================================================

Note: Disabled tokens cannot be used in swaps.
This is useful for emergency situations or token migrations.
✨  Done in 2.37s.
```

---

### ✅ Step 11.2: Test Swap (Disabled Token - Should Fail)

**Command:**
```bash
yarn ts-node scripts/04-test-swap.ts 9gJ94RYM3kUbFyKzzXAaGaRQ4n39XrDCLPZ1XnpZhnms EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v 1
```

**Result:**
- [x] Completed
- Transaction: Failed (as expected)
- Error Code: `TokenDisabled (0x177e)`
- Error Message: `Token is disabled and cannot be used in swaps`
- Error Location: `programs/scaas-liquidity/src/lib.rs:188`
- Compute Units Used: 33,682
- Notes: `✅ Token disable working correctly - swap blocked for disabled token`

```
❌ Error performing swap:
SendTransactionError: Simulation failed.
Message: Transaction simulation failed: Error processing Instruction 0: custom program error: 0x177e.
Logs:
[
  "Program GadmXgM1J4NhkbqbpnAbEQxHssZAavWxG5uV6AHiLMHv invoke [1]",
  "Program log: Instruction: Swap",
  "Program log: AnchorError thrown in programs/scaas-liquidity/src/lib.rs:188. Error Code: TokenDisabled. Error Number: 6014. Error Message: Token is disabled and cannot be used in swaps.",
  "Program GadmXgM1J4NhkbqbpnAbEQxHssZAavWxG5uV6AHiLMHv consumed 33682 of 200000 compute units",
  "Program GadmXgM1J4NhkbqbpnAbEQxHssZAavWxG5uV6AHiLMHv failed: custom program error: 0x177e"
]
```

---

### ✅ Step 11.3: Enable Custom Token

**Command:**
```bash
yarn ts-node scripts/update-token-status.ts 9gJ94RYM3kUbFyKzzXAaGaRQ4n39XrDCLPZ1XnpZhnms false
```

**Result:**
- [x] Completed
- Transaction Signature: `298gU2MmJqJNi3mhKs48dipvQz9LBDMxo3ExbNVPxWUJP2dZCpuqaRu3Pi3K9Gkc2Uoua9ADJqxruzZucz7tXtoG`
- Explorer: https://solscan.io/tx/298gU2MmJqJNi3mhKs48dipvQz9LBDMxo3ExbNVPxWUJP2dZCpuqaRu3Pi3K9Gkc2Uoua9ADJqxruzZucz7tXtoG
- Previous State: Token Disabled = true
- New State: Token Disabled = false
- Timestamp: `2025-12-23`
- Notes: `Token re-enabled successfully`

```
============================================================
UPDATE TOKEN STATUS
============================================================

Configuration:
- Program ID: GadmXgM1J4NhkbqbpnAbEQxHssZAavWxG5uV6AHiLMHv
- Pool PDA: 5QoFtuiVkt5cXcBxmPUGp1waq3b9H5Q9RgKTpV3NcjEh
- Token Mint: 9gJ94RYM3kUbFyKzzXAaGaRQ4n39XrDCLPZ1XnpZhnms
- Vault PDA: EPFgtsNL4VVqwbh6cPwFoWCoqjW1WQvgbRAcitV49HYH
- Pause Authority: 13V7ou4zHHwDVaAGWxqHSwU2sVzRR4m62XWqCFxhA5fD
- Your Wallet: 13V7ou4zHHwDVaAGWxqHSwU2sVzRR4m62XWqCFxhA5fD

Current State:
- Token Disabled: true

Setting token to: ENABLED
Sending transaction...

✅ Token status updated successfully!

Transaction Details:
- Signature: 298gU2MmJqJNi3mhKs48dipvQz9LBDMxo3ExbNVPxWUJP2dZCpuqaRu3Pi3K9Gkc2Uoua9ADJqxruzZucz7tXtoG
- Explorer: https://solscan.io/tx/298gU2MmJqJNi3mhKs48dipvQz9LBDMxo3ExbNVPxWUJP2dZCpuqaRu3Pi3K9Gkc2Uoua9ADJqxruzZucz7tXtoG

New State:
- Token Disabled: false

============================================================
✅ TOKEN ENABLED
============================================================
✨  Done in 4.07s.
```

---

### ✅ Step 11.4: Test Swap (Enabled Token - Should Succeed)

**Command:**
```bash
yarn ts-node scripts/04-test-swap.ts 9gJ94RYM3kUbFyKzzXAaGaRQ4n39XrDCLPZ1XnpZhnms EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v 1
```

**Result:**
- [x] Completed
- Transaction Signature: `yLMk1oQDkWsF8n2vVYjPsitw8eMdP8DEei1X7oaVdJ8FzBdAVGSnb7fcqnkEWM7VAohiF9Jyz55vQZyv8nrPfHp`
- Explorer: https://solscan.io/tx/yLMk1oQDkWsF8n2vVYjPsitw8eMdP8DEei1X7oaVdJ8FzBdAVGSnb7fcqnkEWM7VAohiF9Jyz55vQZyv8nrPfHp
- Input: 1 Custom Token
- Output: 1 USDC
- Balance Before: 9 Custom Token, 9 USDC
- Balance After: 8 Custom Token, 10 USDC
- Exchange Rate: 1:1 (0% fee)
- Notes: `✅ Swap successful after re-enabling token`

```
============================================================
TEST SWAP
============================================================

Configuration:
- Program ID: GadmXgM1J4NhkbqbpnAbEQxHssZAavWxG5uV6AHiLMHv
- Pool PDA: 5QoFtuiVkt5cXcBxmPUGp1waq3b9H5Q9RgKTpV3NcjEh
- User (Signer): 13V7ou4zHHwDVaAGWxqHSwU2sVzRR4m62XWqCFxhA5fD

Swap Details:
- From Token: 9gJ94RYM3kUbFyKzzXAaGaRQ4n39XrDCLPZ1XnpZhnms
- To Token: EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v
- Amount In: 1 tokens
- Amount In (base units): 1000000
- Min Amount Out (base units): 990000
- From Decimals: 6
- To Decimals: 6

Your Balance (From Token): 9 tokens
Your Balance (To Token): 9 tokens

Sending transaction...
✅ Swap successful!

Transaction Details:
- Signature: yLMk1oQDkWsF8n2vVYjPsitw8eMdP8DEei1X7oaVdJ8FzBdAVGSnb7fcqnkEWM7VAohiF9Jyz55vQZyv8nrPfHp
- Explorer: https://solscan.io/tx/yLMk1oQDkWsF8n2vVYjPsitw8eMdP8DEei1X7oaVdJ8FzBdAVGSnb7fcqnkEWM7VAohiF9Jyz55vQZyv8nrPfHp

Your Balance After (From Token): 8 tokens
Your Balance After (To Token): 10 tokens

============================================================
✅ Swap complete!
============================================================
✨  Done in 2.18s.
```

---

### Token Disable Testing Summary

**All Tests Passed:** ✅

| Test | Expected | Actual | Result |
|------|----------|--------|--------|
| Disable token | Disabled | Disabled | ✅ Pass |
| Swap (disabled token) | Fail | Failed (TokenDisabled) | ✅ Pass |
| Enable token | Enabled | Enabled | ✅ Pass |
| Swap (enabled token) | Success | Success | ✅ Pass |

**Key Findings:**
1. ✅ Token disable mechanism works correctly
2. ✅ Swaps are blocked when token is disabled (error 0x177e at lib.rs:188)
3. ✅ Token status can be toggled bidirectionally (disable/enable)
4. ✅ Swaps resume after re-enabling token
5. ✅ Only pause_authority can update token status
6. ✅ Useful for emergency situations or token migrations

**Token Disable Transactions:**
- Disable token: `2tPVNX1CaVUzuYvbRnAPksmechRFymdd9hnuRkx7fdDsvUvrvU3YsD8cZpsBoVghz6ZtFBdW3AB5p7cqHPfT8PNq`
- Enable token: `298gU2MmJqJNi3mhKs48dipvQz9LBDMxo3ExbNVPxWUJP2dZCpuqaRu3Pi3K9Gkc2Uoua9ADJqxruzZucz7tXtoG`
- Swap (after enable): `yLMk1oQDkWsF8n2vVYjPsitw8eMdP8DEei1X7oaVdJ8FzBdAVGSnb7fcqnkEWM7VAohiF9Jyz55vQZyv8nrPfHp`

---

## Phase 12: Pause Authority Transfer Testing

**Purpose:** Verify that pause authority can be safely transferred to another wallet and restored

**Timestamp:** 2025-01-06

### Test Setup

**Original Wallet:**
```
Address: 13V7ou4zHHwDVaAGWxqHSwU2sVzRR4m62XWqCFxhA5fD
Path: ~/.config/solana/id.json
```

**Second Wallet (Created for Testing):**
```
Address: Fj33DQzvJf3GkLa11ejpvNhDvhCFrSdpk5rJQ7KHJhor
Path: ~/.config/solana/id2.json
```

### Step 1: Transfer Pause Authority to New Wallet

```bash
yarn ts-node scripts/update-pause-authority.ts Fj33DQzvJf3GkLa11ejpvNhDvhCFrSdpk5rJQ7KHJhor
```

**Output:**
```
============================================================
UPDATE PAUSE AUTHORITY
============================================================

Configuration:
- Program ID: GadmXgM1J4NhkbqbpnAbEQxHssZAavWxG5uV6AHiLMHv
- Pool PDA: 5QoFtuiVkt5cXcBxmPUGp1waq3b9H5Q9RgKTpV3NcjEh
- Current Pause Authority: 13V7ou4zHHwDVaAGWxqHSwU2sVzRR4m62XWqCFxhA5fD
- Your Wallet: 13V7ou4zHHwDVaAGWxqHSwU2sVzRR4m62XWqCFxhA5fD
- New Pause Authority: Fj33DQzvJf3GkLa11ejpvNhDvhCFrSdpk5rJQ7KHJhor

⚠️  WARNING: This will transfer pause authority control!
   The new pause authority will be able to:
   - Pause/unpause swaps and liquidity operations
   - Enable/disable tokens
   - Manage the whitelist
   - Transfer pause authority to another address

Sending transaction...

✅ Pause authority updated successfully!

Transaction Details:
- Signature: 3xRZv2XfUN3UrP1Lbj7CVDbDyv7137ZhDFtdtErkdLNzTg2tywWhMRH9ie4PrcLmNA3fRGfgDLiUkH58U4zknV3F
- Explorer: https://solscan.io/tx/3xRZv2XfUN3UrP1Lbj7CVDbDyv7137ZhDFtdtErkdLNzTg2tywWhMRH9ie4PrcLmNA3fRGfgDLiUkH58U4zknV3F

Authority Transfer:
- Old Pause Authority: 13V7ou4zHHwDVaAGWxqHSwU2sVzRR4m62XWqCFxhA5fD
- New Pause Authority: Fj33DQzvJf3GkLa11ejpvNhDvhCFrSdpk5rJQ7KHJhor

============================================================
✅ Authority transfer complete!
============================================================
```

**Transaction:** `3xRZv2XfUN3UrP1Lbj7CVDbDyv7137ZhDFtdtErkdLNzTg2tywWhMRH9ie4PrcLmNA3fRGfgDLiUkH58U4zknV3F`

**Result:** Pause authority successfully transferred to new wallet ✅

### Step 2: Verify Old Wallet Cannot Pause (Authority Rejected)

```bash
export ANCHOR_WALLET=~/.config/solana/id.json
yarn ts-node scripts/emergency-pause-swaps.ts
```

**Output:**
```
❌ Error: You are not the pause authority
   Pause authority is: Fj33DQzvJf3GkLa11ejpvNhDvhCFrSdpk5rJQ7KHJhor
   Your wallet is: 13V7ou4zHHwDVaAGWxqHSwU2sVzRR4m62XWqCFxhA5fD
```

**Result:** Old wallet correctly rejected ✅

### Step 3: Verify New Wallet Can Pause Swaps

```bash
export ANCHOR_WALLET=~/.config/solana/id2.json
yarn ts-node scripts/emergency-pause-swaps.ts
```

**Output:**
```
⚠️  WARNING: This will PAUSE all swap operations!
   Users will NOT be able to swap tokens until unpaused.

Are you sure you want to pause swaps? Type 'PAUSE' to confirm: PAUSE

Sending transaction...

⛔️ Swaps paused successfully!

Transaction Details:
- Signature: EBNWFTFcU4A84dev5HcYEN7csg8F89Ke9LMGqGkjxXY4nAjfaej8op7RZFiCsdVCJSXhCnGjeXUBSTWWtmZHTr4
- Explorer: https://solscan.io/tx/EBNWFTFcU4A84dev5HcYEN7csg8F89Ke9LMGqGkjxXY4nAjfaej8op7RZFiCsdVCJSXhCnGjeXUBSTWWtmZHTr4
```

**Transaction:** `EBNWFTFcU4A84dev5HcYEN7csg8F89Ke9LMGqGkjxXY4nAjfaej8op7RZFiCsdVCJSXhCnGjeXUBSTWWtmZHTr4`

**Result:** New wallet successfully paused swaps ✅

### Step 4: Transfer Pause Authority Back to Original Wallet

```bash
export ANCHOR_WALLET=~/.config/solana/id2.json
yarn ts-node scripts/update-pause-authority.ts 13V7ou4zHHwDVaAGWxqHSwU2sVzRR4m62XWqCFxhA5fD
```

**Output:**
```
✅ Pause authority updated successfully!

Transaction Details:
- Signature: 2HJfbLeqByseSa1pQu2eN8RbgWKApEAjXaccG7YZ6JwwTWFy5kkDDtU1dxc9mGkCuAV8AP4aWRo9QwsFX3tAxfKR
- Explorer: https://solscan.io/tx/2HJfbLeqByseSa1pQu2eN8RbgWKApEAjXaccG7YZ6JwwTWFy5kkDDtU1dxc9mGkCuAV8AP4aWRo9QwsFX3tAxfKR

Authority Transfer:
- Old Pause Authority: Fj33DQzvJf3GkLa11ejpvNhDvhCFrSdpk5rJQ7KHJhor
- New Pause Authority: 13V7ou4zHHwDVaAGWxqHSwU2sVzRR4m62XWqCFxhA5fD
```

**Transaction:** `2HJfbLeqByseSa1pQu2eN8RbgWKApEAjXaccG7YZ6JwwTWFy5kkDDtU1dxc9mGkCuAV8AP4aWRo9QwsFX3tAxfKR`

**Result:** Authority transferred back successfully ✅

### Step 5: Verify Original Wallet Can Unpause Swaps

```bash
export ANCHOR_WALLET=~/.config/solana/id.json
yarn ts-node scripts/emergency-unpause-swaps.ts
```

**Output:**
```
⚠️  WARNING: This will UNPAUSE swap operations!
   Users will be able to swap tokens after this.

Are you sure you want to unpause swaps? Type 'UNPAUSE' to confirm: UNPAUSE

Sending transaction...

✅ Swaps unpaused successfully!

Transaction Details:
- Signature: 5pzZfPyJJPKxz9fk4Woim6V9NbXj7KvsSfR52AXVxvk3FTk8wCWFtuCLqX7cmZiMCP99Qjbj3WwJEfkPJV3xwwyb
- Explorer: https://solscan.io/tx/5pzZfPyJJPKxz9fk4Woim6V9NbXj7KvsSfR52AXVxvk3FTk8wCWFtuCLqX7cmZiMCP99Qjbj3WwJEfkPJV3xwwyb
```

**Transaction:** `5pzZfPyJJPKxz9fk4Woim6V9NbXj7KvsSfR52AXVxvk3FTk8wCWFtuCLqX7cmZiMCP99Qjbj3WwJEfkPJV3xwwyb`

**Result:** Original wallet successfully unpaused swaps ✅

---

### Pause Authority Transfer Testing Summary

**All Tests Passed:** ✅

| Test | Expected | Actual | Result |
|------|----------|--------|--------|
| Transfer to new wallet | Success | Success | ✅ Pass |
| Old wallet rejected | Error | Error (Not pause authority) | ✅ Pass |
| New wallet can pause | Success | Success | ✅ Pass |
| Transfer back to original | Success | Success | ✅ Pass |
| Original wallet can unpause | Success | Success | ✅ Pass |

**Key Findings:**
1. ✅ Pause authority can be transferred to another wallet
2. ✅ Old authority is immediately revoked after transfer
3. ✅ New authority can exercise pause/unpause functions
4. ✅ Authority can be transferred back (round-trip works)
5. ✅ Access control enforcement is immediate and correct
6. ✅ Useful for multi-signature setups or authority rotation

**Pause Authority Transfer Transactions:**
- Transfer to new wallet: `3xRZv2XfUN3UrP1Lbj7CVDbDyv7137ZhDFtdtErkdLNzTg2tywWhMRH9ie4PrcLmNA3fRGfgDLiUkH58U4zknV3F`
- New wallet pause swaps: `EBNWFTFcU4A84dev5HcYEN7csg8F89Ke9LMGqGkjxXY4nAjfaej8op7RZFiCsdVCJSXhCnGjeXUBSTWWtmZHTr4`
- Transfer back to original: `2HJfbLeqByseSa1pQu2eN8RbgWKApEAjXaccG7YZ6JwwTWFy5kkDDtU1dxc9mGkCuAV8AP4aWRo9QwsFX3tAxfKR`
- Original wallet unpause: `5pzZfPyJJPKxz9fk4Woim6V9NbXj7KvsSfR52AXVxvk3FTk8wCWFtuCLqX7cmZiMCP99Qjbj3WwJEfkPJV3xwwyb`

---

## Phase 13: Operations Authority Transfer Testing

**Purpose:** Verify that operations authority can be safely transferred to another wallet and restored

**Timestamp:** 2025-01-06

### Test Setup

Same wallets as Phase 12:
- **Original Wallet:** `13V7ou4zHHwDVaAGWxqHSwU2sVzRR4m62XWqCFxhA5fD` (~/.config/solana/id.json)
- **Second Wallet:** `Fj33DQzvJf3GkLa11ejpvNhDvhCFrSdpk5rJQ7KHJhor` (~/.config/solana/id2.json)

### Step 1: Transfer Operations Authority to New Wallet

```bash
export ANCHOR_WALLET=~/.config/solana/id.json
yarn ts-node scripts/update-operations-authority.ts Fj33DQzvJf3GkLa11ejpvNhDvhCFrSdpk5rJQ7KHJhor
```

**Output:**
```
============================================================
UPDATE OPERATIONS AUTHORITY
============================================================

Configuration:
- Program ID: GadmXgM1J4NhkbqbpnAbEQxHssZAavWxG5uV6AHiLMHv
- Pool PDA: 5QoFtuiVkt5cXcBxmPUGp1waq3b9H5Q9RgKTpV3NcjEh
- Current Operations Authority: 13V7ou4zHHwDVaAGWxqHSwU2sVzRR4m62XWqCFxhA5fD
- Your Wallet: 13V7ou4zHHwDVaAGWxqHSwU2sVzRR4m62XWqCFxhA5fD
- New Operations Authority: Fj33DQzvJf3GkLa11ejpvNhDvhCFrSdpk5rJQ7KHJhor

⚠️  WARNING: This will transfer operations authority control!
   The new operations authority will be able to:
   - Add and remove tokens
   - Deposit and withdraw liquidity
   - Update reserved amounts
   - Transfer operations authority to another address

Sending transaction...

✅ Operations authority updated successfully!

Transaction Details:
- Signature: W6bEKXiUs2y3W1LKn1s84MqEhCjyZgfQu64VsoaPBMTH8bijedV5oxAVWpYV7LQRkbutMPuxtGUSNaNbDUiZvKD
- Explorer: https://solscan.io/tx/W6bEKXiUs2y3W1LKn1s84MqEhCjyZgfQu64VsoaPBMTH8bijedV5oxAVWpYV7LQRkbutMPuxtGUSNaNbDUiZvKD

Authority Transfer:
- Old Operations Authority: 13V7ou4zHHwDVaAGWxqHSwU2sVzRR4m62XWqCFxhA5fD
- New Operations Authority: Fj33DQzvJf3GkLa11ejpvNhDvhCFrSdpk5rJQ7KHJhor

============================================================
✅ Authority transfer complete!
============================================================
```

**Transaction:** `W6bEKXiUs2y3W1LKn1s84MqEhCjyZgfQu64VsoaPBMTH8bijedV5oxAVWpYV7LQRkbutMPuxtGUSNaNbDUiZvKD`

**Result:** Operations authority successfully transferred to new wallet ✅

### Step 2: Verify Old Wallet Cannot Withdraw (Operations Authority Rejected)

```bash
export ANCHOR_WALLET=~/.config/solana/id.json
yarn ts-node scripts/emergency-withdraw.ts EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v 0.01
```

**Output:**
```
============================================================
EMERGENCY WITHDRAW LIQUIDITY
============================================================

Configuration:
- Program ID: GadmXgM1J4NhkbqbpnAbEQxHssZAavWxG5uV6AHiLMHv
- Pool PDA: 5QoFtuiVkt5cXcBxmPUGp1waq3b9H5Q9RgKTpV3NcjEh
- Token Mint: EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v
- Operations Authority: Fj33DQzvJf3GkLa11ejpvNhDvhCFrSdpk5rJQ7KHJhor
- Your Wallet: 13V7ou4zHHwDVaAGWxqHSwU2sVzRR4m62XWqCFxhA5fD

❌ Error: You are not the operations authority
   Operations authority is: Fj33DQzvJf3GkLa11ejpvNhDvhCFrSdpk5rJQ7KHJhor
   Your wallet is: 13V7ou4zHHwDVaAGWxqHSwU2sVzRR4m62XWqCFxhA5fD
```

**Result:** Old wallet correctly rejected ✅

### Step 3: Create Token Account and Withdraw with New Wallet

**Create USDC token account for second wallet:**
```bash
solana config set -k /Users/salioudiallo/.config/solana/id2.json
spl-token create-account EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v --owner Fj33DQzvJf3GkLa11ejpvNhDvhCFrSdpk5rJQ7KHJhor --fee-payer ~/.config/solana/id2.json
```

**Output:**
```
Creating account G5FuJnAFh7QF5hueW1mrRafi99QpYxUytfFZpVUS1bvq

Signature: 5yKYJTG4SBYuVeKUWuL1NFM6EsZRyEFB4vae1Mx1JRt9WgwnQPgikXoxAog7BCpy7MCUxtZUNPxiyMavoxVCGDci
```

**Token Account Creation Transaction:** `5yKYJTG4SBYuVeKUWuL1NFM6EsZRyEFB4vae1Mx1JRt9WgwnQPgikXoxAog7BCpy7MCUxtZUNPxiyMavoxVCGDci`

**Withdraw liquidity:**
```bash
export ANCHOR_WALLET=~/.config/solana/id2.json
yarn ts-node scripts/emergency-withdraw.ts EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v 0.01
```

**Output:**
```
============================================================
EMERGENCY WITHDRAW LIQUIDITY
============================================================

Configuration:
- Program ID: GadmXgM1J4NhkbqbpnAbEQxHssZAavWxG5uV6AHiLMHv
- Pool PDA: 5QoFtuiVkt5cXcBxmPUGp1waq3b9H5Q9RgKTpV3NcjEh
- Token Mint: EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v
- Token Decimals: 6
- Vault PDA: GZHACYSwd3TWc4AVjWnHVwudVXrXWdh6qqKhgGcf1aFx
- Vault Token Account: 9XX1dwrvpxAqzZ8jEbE8NMmTA7nGK2eVApuoXJxPGrfS
- Operations Authority: Fj33DQzvJf3GkLa11ejpvNhDvhCFrSdpk5rJQ7KHJhor
- Operations Authority Token Account: G5FuJnAFh7QF5hueW1mrRafi99QpYxUytfFZpVUS1bvq
- Your Wallet: Fj33DQzvJf3GkLa11ejpvNhDvhCFrSdpk5rJQ7KHJhor

Current State:
- Vault Total Balance: 2 tokens
- Reserved Amount: 0 tokens
- Available to Withdraw: 2 tokens
- Token Disabled: false

⚠️  WITHDRAWING 0.01 TOKENS

Withdrawal Details:
- Amount (tokens): 0.01
- Amount (base units): 10000

Sending transaction...

✅ Liquidity withdrawn successfully!

Transaction Details:
- Signature: 4P4CbFWuH5Lj4dvckNAmnTdVMZGq9oSTRShDUTXFtXPWXNPJ4QuYwHNohZGT7oazZeTyQ8T6L3KFmogcJ4KGmBiD
- Explorer: https://solscan.io/tx/4P4CbFWuH5Lj4dvckNAmnTdVMZGq9oSTRShDUTXFtXPWXNPJ4QuYwHNohZGT7oazZeTyQ8T6L3KFmogcJ4KGmBiD

Updated State:
- Vault Balance After: 1.99 tokens
- Amount Withdrawn: 0.01 tokens

============================================================
✅ EMERGENCY WITHDRAWAL COMPLETE
============================================================
```

**Withdrawal Transaction:** `4P4CbFWuH5Lj4dvckNAmnTdVMZGq9oSTRShDUTXFtXPWXNPJ4QuYwHNohZGT7oazZeTyQ8T6L3KFmogcJ4KGmBiD`

**Verification:**
```bash
spl-token accounts
```

**Output:**
```
Token                                         Balance
-----------------------------------------------------
EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v  0.01
```

**Result:** New wallet successfully withdrew liquidity, balance confirmed ✅

### Step 4: Transfer Operations Authority Back to Original Wallet

```bash
export ANCHOR_WALLET=~/.config/solana/id2.json
yarn ts-node scripts/update-operations-authority.ts 13V7ou4zHHwDVaAGWxqHSwU2sVzRR4m62XWqCFxhA5fD
```

**Output:**
```
============================================================
UPDATE OPERATIONS AUTHORITY
============================================================

Configuration:
- Program ID: GadmXgM1J4NhkbqbpnAbEQxHssZAavWxG5uV6AHiLMHv
- Pool PDA: 5QoFtuiVkt5cXcBxmPUGp1waq3b9H5Q9RgKTpV3NcjEh
- Current Operations Authority: Fj33DQzvJf3GkLa11ejpvNhDvhCFrSdpk5rJQ7KHJhor
- Your Wallet: Fj33DQzvJf3GkLa11ejpvNhDvhCFrSdpk5rJQ7KHJhor
- New Operations Authority: 13V7ou4zHHwDVaAGWxqHSwU2sVzRR4m62XWqCFxhA5fD

⚠️  WARNING: This will transfer operations authority control!
   The new operations authority will be able to:
   - Add and remove tokens
   - Deposit and withdraw liquidity
   - Update reserved amounts
   - Transfer operations authority to another address

Sending transaction...

✅ Operations authority updated successfully!

Transaction Details:
- Signature: 2gAeBnkNpQb6uC71gpwscj6w7e2VYE3rFy79N4XEGYVEoSC1dKH3SBxQBLUMEzcHhUqd8BzYUgBUXvkktjxNuatD
- Explorer: https://solscan.io/tx/2gAeBnkNpQb6uC71gpwscj6w7e2VYE3rFy79N4XEGYVEoSC1dKH3SBxQBLUMEzcHhUqd8BzYUgBUXvkktjxNuatD

Authority Transfer:
- Old Operations Authority: Fj33DQzvJf3GkLa11ejpvNhDvhCFrSdpk5rJQ7KHJhor
- New Operations Authority: 13V7ou4zHHwDVaAGWxqHSwU2sVzRR4m62XWqCFxhA5fD

============================================================
✅ Authority transfer complete!
============================================================
```

**Transaction:** `2gAeBnkNpQb6uC71gpwscj6w7e2VYE3rFy79N4XEGYVEoSC1dKH3SBxQBLUMEzcHhUqd8BzYUgBUXvkktjxNuatD`

**Result:** Authority transferred back successfully ✅

### Step 5: Verify Original Wallet Can Deposit Liquidity

```bash
export ANCHOR_WALLET=~/.config/solana/id.json
solana config set -k /Users/salioudiallo/.config/solana/id.json
yarn ts-node scripts/03-deposit-liquidity.ts EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v 0.01
```

**Output:**
```
============================================================
DEPOSITING LIQUIDITY
============================================================

Configuration:
- Program ID: GadmXgM1J4NhkbqbpnAbEQxHssZAavWxG5uV6AHiLMHv
- Pool PDA: 5QoFtuiVkt5cXcBxmPUGp1waq3b9H5Q9RgKTpV3NcjEh
- Token Mint: EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v
- Token Decimals: 6
- Vault PDA: GZHACYSwd3TWc4AVjWnHVwudVXrXWdh6qqKhgGcf1aFx
- Vault Token Account: 9XX1dwrvpxAqzZ8jEbE8NMmTA7nGK2eVApuoXJxPGrfS
- Operations Authority: 13V7ou4zHHwDVaAGWxqHSwU2sVzRR4m62XWqCFxhA5fD
- Operations Authority Token Account: 7vqUNuSd8jYFcbV3RXMyHFTV8kZx2uUVFVSCSQCoQQgw

Deposit Details:
- Amount (tokens): 0.01
- Amount (base units): 10000

Your Balance: 10 tokens
Vault Balance Before: 1.99 tokens

Sending transaction...
✅ Liquidity deposited successfully!

Transaction Details:
- Signature: 37TKsDbHLHL49XXp3EpRUzzoK71DTCZfWp7xs5mZtHSb1NEkp61qYvUrAYqbBNPSEokQRTR3yMpZ1Ehn9k5hjR6w
- Explorer: https://solscan.io/tx/37TKsDbHLHL49XXp3EpRUzzoK71DTCZfWp7xs5mZtHSb1NEkp61qYvUrAYqbBNPSEokQRTR3yMpZ1Ehn9k5hjR6w

Vault Balance After: 2 tokens
Amount Deposited: 0.010000000000000009 tokens

============================================================
✅ Deposit complete!
============================================================
```

**Transaction:** `37TKsDbHLHL49XXp3EpRUzzoK71DTCZfWp7xs5mZtHSb1NEkp61qYvUrAYqbBNPSEokQRTR3yMpZ1Ehn9k5hjR6w`

**Result:** Original wallet successfully deposited liquidity ✅

---

### Final Pool State Verification

After completing all authority transfer tests, verified final pool state:

```bash
yarn ts-node scripts/view-pool-state.ts
```

**Output:**
```
============================================================
POOL STATE VERIFICATION
============================================================

Addresses:
- Program ID: GadmXgM1J4NhkbqbpnAbEQxHssZAavWxG5uV6AHiLMHv
- Pool PDA: 5QoFtuiVkt5cXcBxmPUGp1waq3b9H5Q9RgKTpV3NcjEh
- Whitelist PDA: 9bEDjK1LWyi9dxWcW2qNbYqc6MWTmwoMuX6qucEyJTmm

Pool Configuration:
- Operations Authority: 13V7ou4zHHwDVaAGWxqHSwU2sVzRR4m62XWqCFxhA5fD
- Pause Authority: 13V7ou4zHHwDVaAGWxqHSwU2sVzRR4m62XWqCFxhA5fD
- Fee Recipient: 13V7ou4zHHwDVaAGWxqHSwU2sVzRR4m62XWqCFxhA5fD
- Fee Rate: 0 bps (0%)
- Swaps Paused: false
- Liquidity Paused: false

Supported Tokens:
- Count: 2

Token 1:
- Mint: 9gJ94RYM3kUbFyKzzXAaGaRQ4n39XrDCLPZ1XnpZhnms
- Vault: EPFgtsNL4VVqwbh6cPwFoWCoqjW1WQvgbRAcitV49HYH
- Vault Token Account: 3y6MPgBvQqCS5EJkWE8w6dYwVLT3sue4s6inP8AoAkJv
- Decimals: 6
- Total Balance: 8 tokens
- Reserved Amount: 0 tokens
- Available Liquidity: 8 tokens
- Disabled: false

Token 2:
- Mint: EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v
- Vault: GZHACYSwd3TWc4AVjWnHVwudVXrXWdh6qqKhgGcf1aFx
- Vault Token Account: 9XX1dwrvpxAqzZ8jEbE8NMmTA7nGK2eVApuoXJxPGrfS
- Decimals: 6
- Total Balance: 2 tokens
- Reserved Amount: 0 tokens
- Available Liquidity: 2 tokens
- Disabled: false

Whitelist State:
- Enabled: false
- Addresses Count: 0

============================================================
✅ Pool verification complete!
============================================================
✨  Done in 1.58s.
```

**Verification Summary:**
- ✅ Both authorities restored to original wallet
- ✅ No pausing active (swaps and liquidity operational)
- ✅ Fee rate at 0% as configured
- ✅ Both tokens active and available
- ✅ Whitelist disabled
- ✅ Pool fully operational after all testing phases

---

### Operations Authority Transfer Testing Summary

**All Tests Passed:** ✅

| Test | Expected | Actual | Result |
|------|----------|--------|--------|
| Transfer to new wallet | Success | Success | ✅ Pass |
| Old wallet rejected | Error | Error (Not operations authority) | ✅ Pass |
| Create token account | Success | Success | ✅ Pass |
| New wallet can withdraw | Success | Success (0.01 USDC) | ✅ Pass |
| Transfer back to original | Success | Success | ✅ Pass |
| Original wallet can deposit | Success | Success (0.01 USDC) | ✅ Pass |

**Key Findings:**
1. ✅ Operations authority can be transferred to another wallet
2. ✅ Old authority is immediately revoked after transfer
3. ✅ New authority can exercise liquidity operations (withdraw/deposit)
4. ✅ Token accounts must be created for new authority before withdrawals
5. ✅ Authority can be transferred back (round-trip works)
6. ✅ Access control enforcement is immediate and correct
7. ✅ Useful for multi-signature setups or authority rotation

**Operations Authority Transfer Transactions:**
- Transfer to new wallet: `W6bEKXiUs2y3W1LKn1s84MqEhCjyZgfQu64VsoaPBMTH8bijedV5oxAVWpYV7LQRkbutMPuxtGUSNaNbDUiZvKD`
- Token account creation: `5yKYJTG4SBYuVeKUWuL1NFM6EsZRyEFB4vae1Mx1JRt9WgwnQPgikXoxAog7BCpy7MCUxtZUNPxiyMavoxVCGDci`
- New wallet withdraw: `4P4CbFWuH5Lj4dvckNAmnTdVMZGq9oSTRShDUTXFtXPWXNPJ4QuYwHNohZGT7oazZeTyQ8T6L3KFmogcJ4KGmBiD`
- Transfer back to original: `2gAeBnkNpQb6uC71gpwscj6w7e2VYE3rFy79N4XEGYVEoSC1dKH3SBxQBLUMEzcHhUqd8BzYUgBUXvkktjxNuatD`
- Original wallet deposit: `37TKsDbHLHL49XXp3EpRUzzoK71DTCZfWp7xs5mZtHSb1NEkp61qYvUrAYqbBNPSEokQRTR3yMpZ1Ehn9k5hjR6w`

---

## Post-Deployment Summary

### Critical Addresses (SAVE THESE!)
```
Program ID: GadmXgM1J4NhkbqbpnAbEQxHssZAavWxG5uV6AHiLMHv
Pool: 5QoFtuiVkt5cXcBxmPUGp1waq3b9H5Q9RgKTpV3NcjEh
Whitelist: 9bEDjK1LWyi9dxWcW2qNbYqc6MWTmwoMuX6qucEyJTmm
Custom Token Mint: 9gJ94RYM3kUbFyKzzXAaGaRQ4n39XrDCLPZ1XnpZhnms
Custom Token Vault: EPFgtsNL4VVqwbh6cPwFoWCoqjW1WQvgbRAcitV49HYH
Custom Token Vault Token Account: 3y6MPgBvQqCS5EJkWE8w6dYwVLT3sue4s6inP8AoAkJv
USDC Mint: EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v
USDC Vault: GZHACYSwd3TWc4AVjWnHVwudVXrXWdh6qqKhgGcf1aFx
USDC Vault Token Account: 9XX1dwrvpxAqzZ8jEbE8NMmTA7nGK2eVApuoXJxPGrfS
```

### Pool Statistics
- **Liquidity:** 5 Custom Tokens + 5 USDC (~$10 total)
- **Fee Rate:** 0% (perfect 1:1 swaps)
- **Swaps Executed:** 2 (bidirectional test complete)
- **Status:** Live and operational ✅

### Next Steps
- [x] Configure whitelist if needed
- [ ] Set up monitoring
- [ ] Update frontend with new addresses
- [ ] Communicate pool address to users
- [ ] Set up alerts for vault balances

---

## Emergency Contacts & Commands

### Pause Swaps
```bash
ts-node scripts/emergency-pause-swaps.ts
```

### Pause Liquidity Operations
```bash
ts-node scripts/emergency-pause-liquidity.ts
```

### Withdraw Emergency Liquidity
```bash
ts-node scripts/emergency-withdraw.ts
```

---

## Notes & Issues Encountered

### Issue Log
1. `___________________`
2. `___________________`
3. `___________________`

### Resolutions
1. `___________________`
2. `___________________`
3. `___________________`

---

**Deployment Status:** ⏳ In Progress

**Completion Date:** `___________________`

**Deployed By:** `___________________`

**Verified By:** `___________________`
