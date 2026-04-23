# Mainnet Deployment Runbook - Liquidity Pool Program

**Status:** In Progress
**Date Started:** 2025-12-19
**Deployer:** [To be filled]

---

## Overview

This runbook guides you through deploying the liquidity pool program to Solana mainnet and initializing it with your custom token and USDC.

**Program ID:** `GadmXgM1J4NhkbqbpnAbEQxHssZAavWxG5uV6AHiLMHv`

---

## Key Information

### Addresses
- **Deployer Wallet:** `___________________`
- **Custom Token Mint:** `___________________`
- **Custom Token Decimals:** `___`
- **USDC Mint:** `EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v`
- **Pool PDA:** `___________________`
- **Whitelist PDA:** `___________________`
- **Custom Token Vault:** `___________________`
- **Custom Token Vault Token Account:** `___________________`
- **USDC Vault:** `___________________`
- **USDC Vault Token Account:** `___________________`

### Configuration
- **Fee Rate:** 0 basis points (0% - for 1:1 swaps)
- **Operations Authority:** Deployer wallet
- **Pause Authority:** Deployer wallet
- **Fee Recipient:** Deployer wallet

---

## PHASE 1: Pre-Deployment Setup

### ✅ Step 1.0: Install Solana Development Tools

Follow the official Solana installation guide (installs Rust, Solana CLI, and Anchor Framework):

**Guide:** https://solana.com/docs/intro/installation

**After installation, verify:**
```bash
solana --version
anchor --version
spl-token --version
```

**Tested versions:**
- Solana CLI: 2.2.21+
- Anchor CLI: 0.31.1+
- SPL Token CLI: 5.3.0+ (included with Solana CLI)

**Result:**
- [ ] Completed
- Solana version: `___________________`
- Anchor version: `___________________`
- SPL Token version: `___________________`
- Notes: `___________________`

---

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
- [ ] Completed
- Wallet Address: `___________________`

Fund your wallet with enough SOL if needed. You will likely need about 4-5 SOL.

---

### ✅ Step 1.3: Check SOL Balance
**Command:**
```bash
solana balance
```

**Expected:** At least 4-5 SOL

**Result:**
- [ ] Completed
- Balance: `___________________` SOL
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

# Verify program keypair matches Anchor.toml
solana address -k target/deploy/scaas_liquidity-keypair.json

# Compare with what's in Anchor.toml [programs.mainnet] section
cat Anchor.toml | grep "scaas_liquidity ="
```

**Important:** The keypair address MUST match the program ID in Anchor.toml!

**Common Issues:**
- If they don't match, you likely ran `anchor clean` and lost the original keypair
- For upgrades: You need the original keypair file from the initial deployment
- For new deployments: Update Anchor.toml and lib.rs `declare_id!` to match the generated keypair

**Result:**
- [ ] Completed
- Program Size: `___________________`
- Program ID from keypair: `___________________`
- Program ID in Anchor.toml: `___________________`
- IDs Match: `___________________`
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
- Custom Token Mint: `___________________`
- Custom Token Decimals: `___`
- Your Token Account: `___________________`
- Your Token Balance: `___________________`
- Notes: `___________________`

---

## PHASE 2: Program Deployment

### ✅ Step 2.1: Deploy Program to Mainnet
**Command:**
```bash
anchor deploy --provider.cluster mainnet
```

**Result:**
- [ ] Completed
- Transaction Signature: `___________________`
- Program ID: `___________________`
- Deployment Cost: `___________________` SOL
- Timestamp: `___________________`
- Notes: `___________________`

---

### ✅ Step 2.3: Verify Deployment
**Command:**
```bash
solana program show GadmXgM1J4NhkbqbpnAbEQxHssZAavWxG5uV6AHiLMHv
```

**Result:**
- [ ] Completed
- Program Exists: `___________________`
- **Program Id**: `___________________`
- **Owner**: `___________________`
- **ProgramData Address**: `___________________`
- **Authority**: `___________________`
- **Last Deployed In Slot**: `___________________`
- **Data Length**: `___________________`
- **Balance**: `___________________` SOL
- Notes: `___________________`

---

## PHASE 3: Initialize Pool

### ✅ Step 3.1: Install TypeScript Dependencies
**Command:**
```bash
yarn add -D ts-node typescript @types/node
```

**Result:**
- [ ] Completed
- Notes: `___________________`

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
- [ ] Completed
- Script Created: `___________________`
- Notes: `___________________`

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
- [ ] Completed
- Fee Rate Used: `___________________` bps
- Transaction Signature: `___________________`
- Pool PDA: `___________________`
- Whitelist PDA: `___________________`
- Timestamp: `___________________`
- Notes: `___________________`

---

### ✅ Step 3.5: Verify Pool State
**Command:**
```bash
ts-node scripts/verify-pool.ts
```

**Result:**
- [ ] Completed
- Operations Authority: `___________________`
- Pause Authority: `___________________`
- Fee Recipient: `___________________`
- Fee Rate: `___________________` bps
- Swaps Paused: `___________________`
- Liquidity Paused: `___________________`
- Supported Tokens Count: `___________________`
- Whitelist Enabled: `___________________`
- Notes: `___________________`

---

## PHASE 4: Add Custom Token

### ✅ Step 4.1: Add Custom Token to Pool
**Note:** We use a universal `02-add-token.ts` script that works for any token.

**Command:**
```bash
yarn ts-node scripts/02-add-token.ts <YOUR_CUSTOM_TOKEN_MINT>
```

**Result:**
- [ ] Completed
- Transaction Signature: `___________________`
- Custom Token Vault PDA: `___________________`
- Custom Token Vault Token Account: `___________________`
- Fee Recipient Token Account: `___________________`
- Timestamp: `___________________`
- Notes: `___________________`

---

### ✅ Step 4.2: Verify Custom Token Added
**Result:**
- [ ] Completed
- Token in Supported List: `___________________`
- Vault Exists: `___________________`
- Vault Token Account Exists: `___________________`
- Fee Recipient ATA Created: `___________________`
- Notes: `___________________`

---

## PHASE 5: Add USDC

### ✅ Step 5.1: Add USDC to Pool
**Note:** We use the same `02-add-token.ts` script for all tokens.

**Command:**
```bash
yarn ts-node scripts/02-add-token.ts EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v
```

**Result:**
- [ ] Completed
- Transaction Signature: `___________________`
- USDC Vault PDA: `___________________`
- USDC Vault Token Account: `___________________`
- Fee Recipient Token Account: `___________________`
- Timestamp: `___________________`
- Notes: `___________________`

---

### ✅ Step 5.2: Verify USDC Added
**Result:**
- [ ] Completed
- Token in Supported List: `___________________`
- Vault Exists: `___________________`
- Vault Token Account Exists: `___________________`
- Fee Recipient ATA Created: `___________________`
- Notes: `___________________`

---

## PHASE 6: Deposit Liquidity

### ✅ Step 6.1: Check Token Balances
**Commands:**
```bash
# Check your custom token balance
spl-token balance <YOUR_CUSTOM_TOKEN_MINT>

# Check your USDC balance
spl-token balance EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v
```

Fund your wallet with your custom token and USDC, e.g. 10 of each.

**Result:**
- [ ] Completed
- Custom Token Balance: `___________________`
- USDC Balance: `___________________`
- Notes: `___________________`

---

### ✅ Step 6.2: Seed Custom Token Liquidity
**Planned Amount:** `___________________` tokens

**Note:** Liquidity is seeded by sending tokens directly to the vault token account with a standard SPL Token transfer. The vault token account address for each mint is printed by `scripts/verify-pool.ts`.

**Command:**
```bash
# Look up the vault token account address
yarn ts-node scripts/verify-pool.ts

# Transfer liquidity to it
spl-token transfer <YOUR_CUSTOM_TOKEN_MINT> <AMOUNT> <VAULT_TOKEN_ACCOUNT> --fund-recipient --allow-unfunded-recipient
```

**Result:**
- [ ] Completed
- Transaction Signature: `___________________`
- Amount Transferred: `___________________` tokens
- Vault Balance After: `___________________`
- Timestamp: `___________________`
- Notes: `___________________`

---

### ✅ Step 6.3: Seed USDC Liquidity
**Planned Amount:** `___________________` USDC

**Command:**
```bash
spl-token transfer EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v <AMOUNT> <USDC_VAULT_TOKEN_ACCOUNT> --fund-recipient --allow-unfunded-recipient
```

**Result:**
- [ ] Completed
- Transaction Signature: `___________________`
- Amount Transferred: `___________________` USDC
- Vault Balance After: `___________________`
- Timestamp: `___________________`
- Notes: `___________________`

---

## PHASE 7: Final Verification

### ✅ Step 7.1: Verify Complete Pool State
**Command:**
```bash
yarn ts-node scripts/verify-pool.ts
```

**Result:**
- [ ] Completed
- Pool Initialized: `___________________`
- Supported Tokens: `___________________`
- Custom Token Vault Balance: `___________________`
- USDC Vault Balance: `___________________`
- Total Liquidity USD Value: `___________________`
- Notes: `___________________`

---

### ✅ Step 7.2: Test Swap (Optional but Recommended)
**Test:** Small swap of 1 USDC -> Custom Token

**Command:**
```bash
yarn ts-node scripts/04-test-swap.ts EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v <YOUR_CUSTOM_TOKEN_MINT> 1
```

**Result:**
- [ ] Completed
- Transaction Signature: `___________________`
- Input: `___________________` USDC
- Output: `___________________` Custom Token
- Exchange Rate: `___________________`
- Timestamp: `___________________`
- Notes: `___________________`

---

### ✅ Step 7.3: Test Reverse Swap (Optional but Recommended)
**Test:** Reverse swap of 1 Custom Token -> USDC

**Command:**
```bash
yarn ts-node scripts/04-test-swap.ts <YOUR_CUSTOM_TOKEN_MINT> EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v 1
```

**Result:**
- [ ] Completed
- Transaction Signature: `___________________`
- Input: `___________________` Custom Token
- Output: `___________________` USDC
- Exchange Rate: `___________________`
- Timestamp: `___________________`
- Notes: `___________________`

---

## Post-Deployment Summary

### Total Costs
- Program Deployment: `___________________` SOL
- Pool Initialization: `___________________` SOL
- Add Custom Token: `___________________` SOL
- Add USDC: `___________________` SOL
- Deposit Custom Token: `___________________` SOL
- Deposit USDC: `___________________` SOL
- Test Swap: `___________________` SOL
- **Total:** `___________________` SOL

### Critical Addresses (SAVE THESE!)
```
Program ID: GadmXgM1J4NhkbqbpnAbEQxHssZAavWxG5uV6AHiLMHv
Pool: ___________________
Whitelist: ___________________
Custom Token Mint: ___________________
Custom Token Vault: ___________________
Custom Token Vault Token Account: ___________________
USDC Mint: EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v
USDC Vault: ___________________
USDC Vault Token Account: ___________________
```

### Next Steps
- [ ] Configure whitelist if needed
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

## APPENDIX: Upgrading an Existing Program

If you need to upgrade an already-deployed program (bug fixes, new features, etc.), follow these steps:

### Step U1: Obtain the Original Program Keypair

**Critical:** You MUST have the original keypair from the initial deployment.

```bash
# Get scaas_liquidity-keypair.json from whoever did the original deployment
# Place it at: target/deploy/scaas_liquidity-keypair.json
```

**Verify the keypair:**
```bash
solana address -k target/deploy/scaas_liquidity-keypair.json
# Should output your deployed program ID
```

---

### Step U2: Make Your Code Changes

Edit the program code as needed in `programs/scaas-liquidity/src/`

**Important:** If you're adding new instructions or changing account structures, test thoroughly on devnet first!

---

### Step U3: Build the Updated Program

```bash
anchor build
```

**Result:**
- [ ] Completed
- Build successful: `___________________`
- Program size: `___________________`
- Notes: `___________________`

---

### Step U4: Verify Program ID Match

```bash
# Check keypair address
solana address -k target/deploy/scaas_liquidity-keypair.json

# Check Anchor.toml
cat Anchor.toml | grep "scaas_liquidity ="

# Check lib.rs declare_id!
grep "declare_id!" programs/scaas-liquidity/src/lib.rs
```

**All three MUST show the same program ID!**

**Result:**
- [ ] Completed
- Keypair ID: `___________________`
- Anchor.toml ID: `___________________`
- lib.rs ID: `___________________`
- All match: `___________________`

---

### Step U5: Upgrade the Program

**Command:**
```bash
# Use 'upgrade' not 'deploy' for existing programs
anchor upgrade --program-id GadmXgM1J4NhkbqbpnAbEQxHssZAavWxG5uV6AHiLMHv target/deploy/scaas_liquidity.so --provider.cluster mainnet
```

**What this does:**
- Replaces the program code at the existing address
- Maintains the same program ID
- Preserves all existing accounts (pool, vaults, etc.)
- Requires upgrade authority (your wallet)

**Result:**
- [ ] Completed
- Transaction Signature: `___________________`
- Upgrade successful: `___________________`
- Timestamp: `___________________`
- Notes: `___________________`

---

### Step U6: Verify the Upgrade

```bash
# Check program info
solana program show GadmXgM1J4NhkbqbpnAbEQxHssZAavWxG5uV6AHiLMHv

# Look for "Last Deployed In Slot" - should be recent
```

**Result:**
- [ ] Completed
- Last Deployed Slot: `___________________`
- Data Length: `___________________`
- Authority: `___________________`

---

### Step U7: Update the IDL Onchain

```bash
# Update the onchain IDL
anchor idl upgrade --filepath target/idl/scaas_liquidity.json GadmXgM1J4NhkbqbpnAbEQxHssZAavWxG5uV6AHiLMHv --provider.cluster mainnet

# Verify
anchor idl fetch GadmXgM1J4NhkbqbpnAbEQxHssZAavWxG5uV6AHiLMHv --provider.cluster mainnet
```

**Result:**
- [ ] Completed
- IDL updated: `___________________`
- Transaction Signature: `___________________`

---

### Step U8: Test the Upgrade

Run your test scripts to verify the upgrade works:

```bash
# Verify pool state
yarn ts-node scripts/verify-pool.ts

# Test swap (if applicable)
yarn ts-node scripts/04-test-swap.ts <FROM_MINT> <TO_MINT> <AMOUNT>
```

**Result:**
- [ ] Completed
- Pool state verified: `___________________`
- Test swap successful: `___________________`
- All functionality working: `___________________`
- Notes: `___________________`

---

### Upgrade Summary

**Upgrade Date:** `___________________`
**Upgraded By:** `___________________`
**Changes Made:**
- `___________________`
- `___________________`
- `___________________`

**Upgrade Transaction:** `___________________`
**IDL Update Transaction:** `___________________`

**Testing Results:**
- `___________________`

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
