# Devnet Deployment Runbook - Liquidity Pool Program

**Status:** Not Started
**Date Started:** 2026-01-20
**Deployer:** `___________________`

---

## ⚠️ CRITICAL: Devnet Environment Setup

**Before running ANY scripts, you MUST set these environment variables:**

```bash
export ANCHOR_PROVIDER_URL="https://api.devnet.solana.com"
export ANCHOR_WALLET="$HOME/.config/solana/id.json"
```

**Failure to set these will cause scripts to run against MAINNET instead of DEVNET!**

Verify with:
```bash
echo $ANCHOR_PROVIDER_URL  # Should output: https://api.devnet.solana.com
```

---

## Overview

This runbook guides you through deploying the liquidity pool program to Solana **DEVNET** for testing and development purposes.

**Program ID:** `___________________`

---

## Key Information

### Addresses
- **Deployer Wallet:** `13V7ou4zHHwDVaAGWxqHSwU2sVzRR4m62XWqCFxhA5fD`
- **USDC Mint (Devnet):** `4zMMC9srt5Ri5X14GAgXhaHii3GnPAEERYPJgZJDncDU` (Devnet USDC - 6 decimals)
- **USDF Mint (Devnet):** `Ejgz8rRPySWomDUnsYr1gNpHYm6ZBQnjqbAPfi1dbbwQ` (Devnet USDF - USD stablecoin for testing)
- **SFTUSD25 Mint (Devnet):** `AreQsswF44khJHLjsuWzgboJcG31JvALcWMkMcsVs2uC` (Devnet SFTUSD25 - stablecoin variant for testing)
- **Pool PDA:** `68xwTJYRyUdULbb5ve4JMWTc2xvw9wQmtEj9GRoHSenF`
- **USDC Vault:** `DHCU6cSXeEwk5GUhGVw7XkNfcWF6bY2gsUbtUEUitHhY`
- **USDC Vault Token Account:** `7hktVUoYS9q1c6iq5cnNVmKths3kJ1fJQkozvo4vpHR9`
- **USDF Vault:** `3g3UUaL6y6AjrQuc2cmJHbJmi1XWhEK7VqGrY4CL2Lgn`
- **USDF Vault Token Account:** `pH8X9mDMGEywYHH5fAprVE57LWaHtviwx1J6ZnhgJfm`
- **SFTUSD25 Vault:** `Hon72MLLmPMqQTNphjCvE9Epwdh88S5tZYa1mtLwtn1c`
- **SFTUSD25 Vault Token Account:** `4M8SWnpq6nu7Ud4Qctq3w8HNTWBZP89tYQ27VwaqfvNo`

### Configuration
- **Fee Rate:** 0 basis points (0% - for 1:1 swaps)
- **Operations Authority:** 2yRhUBaydvJzkyVYpFtMBrWZWCnxdYRQtJmqtH2ugtzS
- **Pause Authority:** CC2ymqGpoSjk2estBTC4iYzuxooqSamnoYR2KGo8CYM6
- **Fee Recipient:** Deployer wallet (13V7ou4zHHwDVaAGWxqHSwU2sVzRR4m62XWqCFxhA5fD)

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
- [x] Completed
- Solana version: `2.2.21`
- Anchor version: `0.31.1`
- SPL Token version: `5.3.0`
- Notes: All versions verified

---

### ✅ Step 1.1: Configure Environment to Solana Devnet
**Command:**
```bash
solana config set -u d
```

**Verify:**
```bash
solana config get
```

**Expected output should show:**
```
RPC URL: https://api.devnet.solana.com
```

**Result:**
- [x] Completed
- RPC URL: `https://api.devnet.solana.com`
- Notes: Successfully configured for devnet

---

### ✅ Step 1.2: Get Wallet Address
**Command:**
```bash
solana address
```

**Result:**
- [x] Completed
- Wallet Address: `13V7ou4zHHwDVaAGWxqHSwU2sVzRR4m62XWqCFxhA5fD`

---

### ✅ Step 1.3: Fund Wallet with Devnet SOL

**Command:**
```bash
# Request 2 SOL from devnet faucet (can be run multiple times)
solana airdrop 2

# Check balance
solana balance
```

**Expected:** At least 4-5 SOL (run airdrop command multiple times if needed)

**Alternative:** Use web faucet at https://faucet.solana.com

**Result:**
- [x] Completed
- Balance: `9.23` SOL
- Notes: Sufficient balance for deployment

---

### ✅ Step 1.4: Build the Program
**Command:**
```bash
anchor clean
anchor build
```

**Result:**
- [x] Completed
- Notes: Build successful

---

### ✅ Step 1.5: Verify Program Build
**Command:**
```bash
# Check that the program is built
ls -lh target/deploy/scaas_liquidity.so

# Verify program keypair exists
solana address -k target/deploy/scaas_liquidity-keypair.json

# Compare with what's in Anchor.toml [programs.devnet] section
cat Anchor.toml | grep -A 3 "[programs.devnet]"
```

**Important:** For devnet, you can generate a new keypair or use an existing one.

**Result:**
- [x] Completed
- Program Size: `452K`
- Program ID from keypair: `9vDwZVJXw5nxymWmUcgmNpemDH5EBcJwLNhtsznrgJDH`
- Program ID in Anchor.toml: `9vDwZVJXw5nxymWmUcgmNpemDH5EBcJwLNhtsznrgJDH`
- IDs Match: `Yes`
- Notes: All program IDs match correctly

---

### ✅ Step 1.6: Create or Verify Custom Token

**Option A: Create a new test token**
```bash
# Create a new token mint with 6 decimals
spl-token create-token --decimals 6

# Create token account for your wallet
spl-token create-account <TOKEN_MINT>

# Mint some tokens for testing (e.g., 100,000 tokens)
spl-token mint <TOKEN_MINT> 100000
```

**Option B: Use existing token**
```bash
# Check your token mint address
spl-token accounts

# Get specific token balance and verify decimals
spl-token account-info <YOUR_TOKEN_MINT>

# If you have no token account for the token mint, create it
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

### ✅ Step 1.7: Get Devnet USDC (Optional)

**Note:** You can use Devnet USDC or skip this for asymmetric liquidity testing.

**Devnet USDC Mint:** `4zMMC9srt5Ri5X14GAgXhaHii3GnPAEERYPJgZJDncDU`

**Commands:**
```bash
# Create USDC token account
spl-token create-account 4zMMC9srt5Ri5X14GAgXhaHii3GnPAEERYPJgZJDncDU

# Check balance
spl-token balance 4zMMC9srt5Ri5X14GAgXhaHii3GnPAEERYPJgZJDncDU
```

**To get devnet USDC:**
- Use SPL Token Faucet: https://spl-token-faucet.com
- Or request from other devnet faucets

**Result:**
- [ ] Completed
- USDC Token Account: `___________________`
- USDC Balance: `___________________`
- Notes: `___________________`

---

## PHASE 2: Program Deployment

### ✅ Step 2.1: Deploy Program to Devnet
**Command:**
```bash
anchor deploy --provider.cluster devnet
```

**Result:**
- [x] Completed
- Transaction Signature: `83NapGXe2Zrk7CCwv496CbakQrXXnZRLo1umVQ8RZXpx3WvbGKSBYeyqcHEspxHQkZFVhoQiFNMwFovp3i2kuB8`
- Program ID: `9vDwZVJXw5nxymWmUcgmNpemDH5EBcJwLNhtsznrgJDH`
- Deployment Cost: `~3.22` SOL
- Timestamp: `2026-01-20`
- Notes: Deployment successful to devnet

---

### ✅ Step 2.2: Verify Deployment
**Command:**
```bash
solana program show <YOUR_PROGRAM_ID>
```

**Result:**
- [x] Completed
- Program Exists: `Yes`
- **Program Id**: `9vDwZVJXw5nxymWmUcgmNpemDH5EBcJwLNhtsznrgJDH`
- **Owner**: `BPFLoaderUpgradeab1e11111111111111111111111`
- **ProgramData Address**: `6Hs6o7iXt4jPL7s9hrvgN7vZX3WMPpek4mhgzroCLXiR`
- **Authority**: `13V7ou4zHHwDVaAGWxqHSwU2sVzRR4m62XWqCFxhA5fD`
- **Last Deployed In Slot**: `436473580`
- **Data Length**: `462928 bytes`
- **Balance**: `3.22318296 SOL`
- Notes: Program successfully deployed and verified on devnet

---

## PHASE 3: Initialize Pool

**⚠️ IMPORTANT:** Before running any scripts in this phase, ensure you have set the environment variables in Step 3.2 to point to devnet!

### ✅ Step 3.1: Verify TypeScript Dependencies
**Command:**
```bash
# Check if already installed
ls node_modules/ts-node

# If not installed, run:
yarn add -D ts-node typescript @types/node
```

**Result:**
- [ ] Completed
- Notes: `___________________`

---

### ✅ Step 3.2: Set Environment Variables for Devnet

**⚠️ CRITICAL:** You MUST set these environment variables to ensure scripts run against devnet, not mainnet!

**Command:**
```bash
# Export these in your shell (or add to ~/.bashrc or ~/.zshrc)
export ANCHOR_PROVIDER_URL="https://api.devnet.solana.com"
export ANCHOR_WALLET="$HOME/.config/solana/id.json"
```

**Verify the variables are set:**
```bash
echo $ANCHOR_PROVIDER_URL
# Should output: https://api.devnet.solana.com

echo $ANCHOR_WALLET
# Should output: /Users/<your-user>/.config/solana/id.json (or your wallet path)
```

**Alternative: Set them for a single command:**
```bash
ANCHOR_PROVIDER_URL="https://api.devnet.solana.com" ANCHOR_WALLET="$HOME/.config/solana/id.json" yarn ts-node scripts/01-initialize-pool.ts 0
```

**Result:**
- [ ] Completed
- ANCHOR_PROVIDER_URL verified: `___________________`
- ANCHOR_WALLET verified: `___________________`
- Notes: `___________________`

---

### ✅ Step 3.3: Run Pool Initialization

**⚠️ Double-check before running:**
```bash
# Verify you're on devnet
echo $ANCHOR_PROVIDER_URL
# Must output: https://api.devnet.solana.com
```

**Command:**
```bash
# For 0% fee (1:1 swaps)
yarn ts-node scripts/01-initialize-pool.ts 0

# Or for 1% fee
yarn ts-node scripts/01-initialize-pool.ts 100
```

**Result:**
- [x] Completed
- Fee Rate Used: `0` bps
- Transaction Signature: `43RNFGxYpLSQ2iUHWxQLA1HZfW6AiE3Y44hTemHwTWnZgDPqxLmutRZEaGc9ajZQhRnNym1n5wBb28gfvS4BDczL`
- Pool PDA: `68xwTJYRyUdULbb5ve4JMWTc2xvw9wQmtEj9GRoHSenF`
- Timestamp: `2026-01-20`
- Explorer URL: `https://solscan.io/tx/43RNFGxYpLSQ2iUHWxQLA1HZfW6AiE3Y44hTemHwTWnZgDPqxLmutRZEaGc9ajZQhRnNym1n5wBb28gfvS4BDczL?cluster=devnet`
- Notes: Pool initialized successfully with 0% fee

---

### ✅ Step 3.4: Verify Pool State
**Command:**
```bash
yarn ts-node scripts/verify-pool.ts
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
- Notes: `___________________`

---

## PHASE 4: Add USDC (Devnet)

### ✅ Step 4.1: Add Devnet USDC to Pool
**Note:** We use the same `02-add-token.ts` script for all tokens.

**Command:**
```bash
yarn ts-node scripts/02-add-token.ts 4zMMC9srt5Ri5X14GAgXhaHii3GnPAEERYPJgZJDncDU
```

**Result:**
- [x] Completed
- Transaction Signature: `xagREaP2vDJKPG5x5Gqb3t44HJvgMBksGBoMmk6JK7CMBVZ9x6BhoCYKJ1X8dHdju97pudj7cN1apmZrWQ3fxKB`
- USDC Vault PDA: `DHCU6cSXeEwk5GUhGVw7XkNfcWF6bY2gsUbtUEUitHhY`
- USDC Vault Token Account: `7hktVUoYS9q1c6iq5cnNVmKths3kJ1fJQkozvo4vpHR9`
- Fee Recipient Token Account: `ApRsuEag25j28AXDH7HQ68cG1oHzNyuauKtk98szm6Y8`
- Timestamp: `2026-01-20`
- Explorer URL: `https://solscan.io/tx/xagREaP2vDJKPG5x5Gqb3t44HJvgMBksGBoMmk6JK7CMBVZ9x6BhoCYKJ1X8dHdju97pudj7cN1apmZrWQ3fxKB?cluster=devnet`
- Notes: USDC added successfully

---

### ✅ Step 4.2: Verify USDC Added
**Command:**
```bash
yarn ts-node scripts/verify-pool.ts
```

**Result:**
- [x] Completed
- Token in Supported List: `Yes`
- Vault Exists: `Yes`
- Vault Token Account Exists: `Yes`
- Fee Recipient ATA Created: `Yes`
- Notes: Pool has 1 supported token

---

## PHASE 5: Add USDF (Devnet)

### ✅ Step 5.1: Add Devnet USDF to Pool
**Note:** We use the same `02-add-token.ts` script for all tokens.

**Command:**
```bash
yarn ts-node scripts/02-add-token.ts Ejgz8rRPySWomDUnsYr1gNpHYm6ZBQnjqbAPfi1dbbwQ
```

**Result:**
- [x] Completed
- Transaction Signature: `5i1eaaQM2qVGhYn81j2b8L1Gnj6kwFuE71ZRPdwq1ditDxtQ4NuwQXEA1ffhKyHPeDDnQ6GiqRyThYgeX3vKnFQG`
- USDF Vault PDA: `3g3UUaL6y6AjrQuc2cmJHbJmi1XWhEK7VqGrY4CL2Lgn`
- USDF Vault Token Account: `pH8X9mDMGEywYHH5fAprVE57LWaHtviwx1J6ZnhgJfm`
- Fee Recipient Token Account: `8scZbgPB2rWEsSbBtwiPYG77R5e591cLwEqAMiAHCuC1`
- Timestamp: `2026-01-20`
- Explorer URL: `https://solscan.io/tx/5i1eaaQM2qVGhYn81j2b8L1Gnj6kwFuE71ZRPdwq1ditDxtQ4NuwQXEA1ffhKyHPeDDnQ6GiqRyThYgeX3vKnFQG?cluster=devnet`
- Notes: USDF added successfully

---

### ✅ Step 5.2: Verify USDF Added
**Command:**
```bash
yarn ts-node scripts/verify-pool.ts
```

**Result:**
- [x] Completed
- Token in Supported List: `Yes`
- Vault Exists: `Yes`
- Vault Token Account Exists: `Yes`
- Fee Recipient ATA Created: `Yes`
- Notes: Pool has 2 supported tokens

---

## PHASE 6: Add SFTUSD25 (Devnet)

### ✅ Step 6.1: Add Devnet SFTUSD25 to Pool
**Note:** We use the same `02-add-token.ts` script for all tokens.

**Command:**
```bash
yarn ts-node scripts/02-add-token.ts AreQsswF44khJHLjsuWzgboJcG31JvALcWMkMcsVs2uC
```

**Result:**
- [x] Completed
- Transaction Signature: `3wUhgLRJHDnsUoTn4Ydi4ag13XKdHGqk7SLWkX9ivicruZ16ZPMHvQeQ3RdeGsNpA2d9RrZzFAnoiByAHswWikGb`
- SFTUSD25 Vault PDA: `Hon72MLLmPMqQTNphjCvE9Epwdh88S5tZYa1mtLwtn1c`
- SFTUSD25 Vault Token Account: `4M8SWnpq6nu7Ud4Qctq3w8HNTWBZP89tYQ27VwaqfvNo`
- Fee Recipient Token Account: `8w2c1QnSFHtSg5jzjN5GzaisjFb61mJgQSTdNEVPiiQo`
- Timestamp: `2026-01-20`
- Explorer URL: `https://solscan.io/tx/3wUhgLRJHDnsUoTn4Ydi4ag13XKdHGqk7SLWkX9ivicruZ16ZPMHvQeQ3RdeGsNpA2d9RrZzFAnoiByAHswWikGb?cluster=devnet`
- Notes: SFTUSD25 added successfully

---

### ✅ Step 6.2: Verify SFTUSD25 Added
**Command:**
```bash
yarn ts-node scripts/verify-pool.ts
```

**Result:**
- [x] Completed
- Token in Supported List: `Yes`
- Vault Exists: `Yes`
- Vault Token Account Exists: `Yes`
- Fee Recipient ATA Created: `Yes`
- Notes: Pool has 3 supported tokens (USDC, USDF, SFTUSD25)

---

## PHASE 7: Deposit Liquidity

### ✅ Step 7.1: Check Token Balances
**Commands:**
```bash
# Check your custom token balance
spl-token balance <YOUR_CUSTOM_TOKEN_MINT>

# Check your USDC balance
spl-token balance 4zMMC9srt5Ri5X14GAgXhaHii3GnPAEERYPJgZJDncDU

# Check your USDF balance
spl-token balance Ejgz8rRPySWomDUnsYr1gNpHYm6ZBQnjqbAPfi1dbbwQ

# Check your SFTUSD25 balance
spl-token balance AreQsswF44khJHLjsuWzgboJcG31JvALcWMkMcsVs2uC
```

**Result:**
- [x] Completed
- Custom Token Balance: `N/A (skipped custom token)`
- USDC Balance: `1`
- USDF Balance: `10`
- SFTUSD25 Balance: `10`
- Notes: Decided to only deposit USDF and SFTUSD25, not USDC

---

### ✅ Step 7.2: Deposit USDC Liquidity
**Planned Amount:** `0` USDC (Skipped for asymmetric liquidity testing)

**Command:**
```bash
yarn ts-node scripts/03-deposit-liquidity.ts 4zMMC9srt5Ri5X14GAgXhaHii3GnPAEERYPJgZJDncDU <AMOUNT>

# Example: Deposit 1000 USDC
yarn ts-node scripts/03-deposit-liquidity.ts 4zMMC9srt5Ri5X14GAgXhaHii3GnPAEERYPJgZJDncDU 1000
```

**Result:**
- [x] Skipped
- Transaction Signature: `N/A`
- Amount Deposited: `0` USDC
- Vault Balance After: `0`
- Timestamp: `2026-01-20`
- Explorer URL: `N/A`
- Notes: Intentionally skipped USDC deposit to test asymmetric liquidity pool (only USDF and SFTUSD25 deposited)

---

### ✅ Step 7.3: Deposit USDF Liquidity
**Planned Amount:** `10` USDF

**Command:**
```bash
yarn ts-node scripts/03-deposit-liquidity.ts Ejgz8rRPySWomDUnsYr1gNpHYm6ZBQnjqbAPfi1dbbwQ <AMOUNT>

# Example: Deposit 1000 USDF
yarn ts-node scripts/03-deposit-liquidity.ts Ejgz8rRPySWomDUnsYr1gNpHYm6ZBQnjqbAPfi1dbbwQ 1000
```

**Result:**
- [x] Completed
- Transaction Signature: `Td2KqReYyavxBAzmP6xnaw52hqRDWFTRPPakfkExHctPjuqAnsa7xbKBtPtZ8jn598cFTZic8qte5zCpafV2RZ7`
- Amount Deposited: `10` USDF
- Vault Balance After: `10`
- Timestamp: `2026-01-20`
- Explorer URL: `https://solscan.io/tx/Td2KqReYyavxBAzmP6xnaw52hqRDWFTRPPakfkExHctPjuqAnsa7xbKBtPtZ8jn598cFTZic8qte5zCpafV2RZ7?cluster=devnet`
- Notes: Successfully deposited 10 USDF to vault

---

### ✅ Step 7.4: Deposit SFTUSD25 Liquidity
**Planned Amount:** `10` SFTUSD25

**Command:**
```bash
yarn ts-node scripts/03-deposit-liquidity.ts AreQsswF44khJHLjsuWzgboJcG31JvALcWMkMcsVs2uC <AMOUNT>

# Example: Deposit 1000 SFTUSD25
yarn ts-node scripts/03-deposit-liquidity.ts AreQsswF44khJHLjsuWzgboJcG31JvALcWMkMcsVs2uC 1000
```

**Result:**
- [x] Completed
- Transaction Signature: `47dH8PwZTdKLFjSDY6bxd9HLBfeUZxCYY26MspHEUf4yfa3YH3ef1N7xU75p6MRuhM74AbyqUneZJVNBpMgdcmQ7`
- Amount Deposited: `10` SFTUSD25
- Vault Balance After: `10`
- Timestamp: `2026-01-20`
- Explorer URL: `https://solscan.io/tx/47dH8PwZTdKLFjSDY6bxd9HLBfeUZxCYY26MspHEUf4yfa3YH3ef1N7xU75p6MRuhM74AbyqUneZJVNBpMgdcmQ7?cluster=devnet`
- Notes: Successfully deposited 10 SFTUSD25 to vault

---

## PHASE 8: Testing & Verification

### ✅ Step 8.1: Verify Complete Pool State
**Command:**
```bash
yarn ts-node scripts/verify-pool.ts
```

**Result:**
- [ ] Completed
- Pool Initialized: `___________________`
- Supported Tokens: `5 (Custom Token, USDC, USDF, SFTUSD25, + any others)`
- USDC Vault Balance: `___________________`
- USDF Vault Balance: `___________________`
- SFTUSD25 Vault Balance: `___________________`
- Total Liquidity USD Value: `___________________`
- Notes: `___________________`

---

### ✅ Step 8.2: Test Swap (USDC -> USDF)
**Test:** Small swap of 1 USDC -> USDF

**Command:**
```bash
yarn ts-node scripts/04-test-swap.ts 4zMMC9srt5Ri5X14GAgXhaHii3GnPAEERYPJgZJDncDU Ejgz8rRPySWomDUnsYr1gNpHYm6ZBQnjqbAPfi1dbbwQ 1
```

**Result:**
- [x] Completed
- Transaction Signature: `3Y12X8sn9ixE5rAK2YGa8UHUt4UcmLaqVJyRR7QvMYvCXypv3fH5mb9rdi267Q54SMvsEnNWjAB5TaY4soU8qKha`
- Input: `1` USDC
- Output: `1` USDF
- Exchange Rate: `1:1 (0% fee)`
- Timestamp: `2026-01-20`
- Explorer URL: `https://solscan.io/tx/3Y12X8sn9ixE5rAK2YGa8UHUt4UcmLaqVJyRR7QvMYvCXypv3fH5mb9rdi267Q54SMvsEnNWjAB5TaY4soU8qKha?cluster=devnet`
- Notes: Swap successful - pool now has 1 USDC, 9 USDF, 10 SFTUSD25

---

### ✅ Step 8.3: Test Reverse Swap (USDF -> USDC)
**Test:** Reverse swap of 1 USDF -> USDC

**Command:**
```bash
yarn ts-node scripts/04-test-swap.ts Ejgz8rRPySWomDUnsYr1gNpHYm6ZBQnjqbAPfi1dbbwQ 4zMMC9srt5Ri5X14GAgXhaHii3GnPAEERYPJgZJDncDU 1
```

**Result:**
- [ ] Completed
- Transaction Signature: `___________________`
- Input: `1` USDF
- Output: `___________________` USDC
- Exchange Rate: `___________________`
- Timestamp: `___________________`
- Explorer URL: `https://solscan.io/tx/<TX_SIG>?cluster=devnet`
- Notes: `___________________`

---

### ✅ Step 8.4: Test Swap (USDC -> SFTUSD25)
**Test:** Small swap of 1 USDC -> SFTUSD25

**Command:**
```bash
yarn ts-node scripts/04-test-swap.ts 4zMMC9srt5Ri5X14GAgXhaHii3GnPAEERYPJgZJDncDU AreQsswF44khJHLjsuWzgboJcG31JvALcWMkMcsVs2uC 1
```

**Result:**
- [ ] Completed
- Transaction Signature: `___________________`
- Input: `1` USDC
- Output: `___________________` SFTUSD25
- Exchange Rate: `___________________`
- Timestamp: `___________________`
- Explorer URL: `https://solscan.io/tx/<TX_SIG>?cluster=devnet`
- Notes: `___________________`

---

### ✅ Step 8.5: Test Swap (SFTUSD25 -> USDC)
**Test:** Reverse swap of 1 SFTUSD25 -> USDC

**Command:**
```bash
yarn ts-node scripts/04-test-swap.ts AreQsswF44khJHLjsuWzgboJcG31JvALcWMkMcsVs2uC 4zMMC9srt5Ri5X14GAgXhaHii3GnPAEERYPJgZJDncDU 1
```

**Result:**
- [ ] Completed
- Transaction Signature: `___________________`
- Input: `1` SFTUSD25
- Output: `___________________` USDC
- Exchange Rate: `___________________`
- Timestamp: `___________________`
- Explorer URL: `https://solscan.io/tx/<TX_SIG>?cluster=devnet`
- Notes: `___________________`

---

### ✅ Step 8.6: Test Swap (USDF -> SFTUSD25)
**Test:** Cross-stablecoin swap of 1 USDF -> SFTUSD25

**Command:**
```bash
yarn ts-node scripts/04-test-swap.ts Ejgz8rRPySWomDUnsYr1gNpHYm6ZBQnjqbAPfi1dbbwQ AreQsswF44khJHLjsuWzgboJcG31JvALcWMkMcsVs2uC 1
```

**Result:**
- [x] Completed
- Transaction Signature: `4MPaC22MHHP8mXPNPKDEP3ryhNywpJ84UJJqEKAFHSG3SKtbgWcWfQDQhGAdcAMtijxAMmAgARbvhwD5VXGCS3Ay`
- Input: `1` USDF
- Output: `1` SFTUSD25
- Exchange Rate: `1:1 (0% fee)`
- Timestamp: `2026-01-20`
- Explorer URL: `https://solscan.io/tx/4MPaC22MHHP8mXPNPKDEP3ryhNywpJ84UJJqEKAFHSG3SKtbgWcWfQDQhGAdcAMtijxAMmAgARbvhwD5VXGCS3Ay?cluster=devnet`
- Notes: Swap successful - pool now has 1 USDC, 10 USDF, 9 SFTUSD25

---

### ✅ Step 8.7: Test Swap (SFTUSD25 -> USDF)
**Test:** Cross-stablecoin swap of 1 SFTUSD25 -> USDF

**Command:**
```bash
yarn ts-node scripts/04-test-swap.ts AreQsswF44khJHLjsuWzgboJcG31JvALcWMkMcsVs2uC Ejgz8rRPySWomDUnsYr1gNpHYm6ZBQnjqbAPfi1dbbwQ 1
```

**Result:**
- [ ] Completed
- Transaction Signature: `___________________`
- Input: `1` SFTUSD25
- Output: `___________________` USDF
- Exchange Rate: `___________________`
- Timestamp: `___________________`
- Explorer URL: `https://solscan.io/tx/<TX_SIG>?cluster=devnet`
- Notes: `___________________`

---

## PHASE 9: Transfer Authorities

### ✅ Step 9.1: Transfer Operations Authority

**Command:**
```bash
yarn ts-node scripts/update-operations-authority.ts 2yRhUBaydvJzkyVYpFtMBrWZWCnxdYRQtJmqtH2ugtzS
```

**Result:**
- [x] Completed
- Transaction Signature: `pzuGXvAorujrzPmRAtQGoKBtd1hoitvV43kiNFSDMaUSKUXd4UVoZL5RNxAthYwqTWtnU8Tg5EExgSCdhM6Mn8n`
- Old Operations Authority: `13V7ou4zHHwDVaAGWxqHSwU2sVzRR4m62XWqCFxhA5fD`
- New Operations Authority: `2yRhUBaydvJzkyVYpFtMBrWZWCnxdYRQtJmqtH2ugtzS`
- Timestamp: `2026-01-20`
- Explorer URL: `https://solscan.io/tx/pzuGXvAorujrzPmRAtQGoKBtd1hoitvV43kiNFSDMaUSKUXd4UVoZL5RNxAthYwqTWtnU8Tg5EExgSCdhM6Mn8n?cluster=devnet`
- Notes: Operations authority successfully transferred

---

### ✅ Step 9.2: Transfer Pause Authority

**Command:**
```bash
yarn ts-node scripts/update-pause-authority.ts CC2ymqGpoSjk2estBTC4iYzuxooqSamnoYR2KGo8CYM6
```

**Result:**
- [x] Completed
- Transaction Signature: `4sCtcnni1CaHVEodqsKWvrcst4gR6oAjAhZCuMrrB3MqjcB5A2QLU6y3Vmx5j5WSgTjXLUDsZVAcYmus67e55eb`
- Old Pause Authority: `13V7ou4zHHwDVaAGWxqHSwU2sVzRR4m62XWqCFxhA5fD`
- New Pause Authority: `CC2ymqGpoSjk2estBTC4iYzuxooqSamnoYR2KGo8CYM6`
- Timestamp: `2026-01-20`
- Explorer URL: `https://solscan.io/tx/4sCtcnni1CaHVEodqsKWvrcst4gR6oAjAhZCuMrrB3MqjcB5A2QLU6y3Vmx5j5WSgTjXLUDsZVAcYmus67e55eb?cluster=devnet`
- Notes: Pause authority successfully transferred

---

### ✅ Step 9.3: Verify Authority Transfers

**Command:**
```bash
yarn ts-node scripts/verify-pool.ts
```

**Result:**
- [x] Completed
- Operations Authority: `2yRhUBaydvJzkyVYpFtMBrWZWCnxdYRQtJmqtH2ugtzS` ✓
- Pause Authority: `CC2ymqGpoSjk2estBTC4iYzuxooqSamnoYR2KGo8CYM6` ✓
- Fee Recipient: `13V7ou4zHHwDVaAGWxqHSwU2sVzRR4m62XWqCFxhA5fD` (unchanged)
- Notes: All authorities verified successfully

---

## PHASE 10: Optional - Publish IDL to Devnet

### ✅ Step 10.1: Publish IDL

**Command:**
```bash
anchor idl init 9vDwZVJXw5nxymWmUcgmNpemDH5EBcJwLNhtsznrgJDH --filepath target/idl/scaas_liquidity.json --provider.cluster devnet
```

**Result:**
- [x] Completed
- IDL Account Created: `A86H6NXnycB7WPRtPFc9yL5pQJNFdtKSziGMNkNHorH1`
- IDL Data Length: `3352 bytes`
- Timestamp: `2026-01-20`
- Notes: IDL successfully published to devnet

---

### ✅ Step 10.2: Verify IDL Published

**Command:**
```bash
anchor idl fetch 9vDwZVJXw5nxymWmUcgmNpemDH5EBcJwLNhtsznrgJDH --provider.cluster devnet
```

**Result:**
- [x] Completed
- IDL Publicly Accessible: `Yes`
- Notes: IDL fetch successful - publicly accessible on devnet

---

## Post-Deployment Summary

### Total Costs
- Program Deployment: `~3.22` SOL
- Pool Initialization: `~0.01` SOL
- Add USDC: `~0.01` SOL
- Add USDF: `~0.01` SOL
- Add SFTUSD25: `~0.01` SOL
- Deposit USDF: `~0.0001` SOL
- Deposit SFTUSD25: `~0.0001` SOL
- Test Swaps (2 swaps): `~0.0002` SOL
- Transfer Authorities (2 txs): `~0.0002` SOL
- Publish IDL: `~0.02` SOL
- **Total:** `~3.27` SOL (all from devnet faucet)

### Critical Addresses (SAVE THESE!)
```
Network: Devnet
Program ID: 9vDwZVJXw5nxymWmUcgmNpemDH5EBcJwLNhtsznrgJDH
Pool PDA: 68xwTJYRyUdULbb5ve4JMWTc2xvw9wQmtEj9GRoHSenF
IDL Account: A86H6NXnycB7WPRtPFc9yL5pQJNFdtKSziGMNkNHorH1

Operations Authority: 2yRhUBaydvJzkyVYpFtMBrWZWCnxdYRQtJmqtH2ugtzS
Pause Authority: CC2ymqGpoSjk2estBTC4iYzuxooqSamnoYR2KGo8CYM6
Fee Recipient: 13V7ou4zHHwDVaAGWxqHSwU2sVzRR4m62XWqCFxhA5fD

USDC Mint (Devnet): 4zMMC9srt5Ri5X14GAgXhaHii3GnPAEERYPJgZJDncDU
USDC Vault: DHCU6cSXeEwk5GUhGVw7XkNfcWF6bY2gsUbtUEUitHhY
USDC Vault Token Account: 7hktVUoYS9q1c6iq5cnNVmKths3kJ1fJQkozvo4vpHR9

USDF Mint (Devnet): Ejgz8rRPySWomDUnsYr1gNpHYm6ZBQnjqbAPfi1dbbwQ
USDF Vault: 3g3UUaL6y6AjrQuc2cmJHbJmi1XWhEK7VqGrY4CL2Lgn
USDF Vault Token Account: pH8X9mDMGEywYHH5fAprVE57LWaHtviwx1J6ZnhgJfm

SFTUSD25 Mint (Devnet): AreQsswF44khJHLjsuWzgboJcG31JvALcWMkMcsVs2uC
SFTUSD25 Vault: Hon72MLLmPMqQTNphjCvE9Epwdh88S5tZYa1mtLwtn1c
SFTUSD25 Vault Token Account: 4M8SWnpq6nu7Ud4Qctq3w8HNTWBZP89tYQ27VwaqfvNo
```

### Explorer Links
```
Program: https://solscan.io/account/9vDwZVJXw5nxymWmUcgmNpemDH5EBcJwLNhtsznrgJDH?cluster=devnet
Pool: https://solscan.io/account/68xwTJYRyUdULbb5ve4JMWTc2xvw9wQmtEj9GRoHSenF?cluster=devnet
IDL: https://solscan.io/account/A86H6NXnycB7WPRtPFc9yL5pQJNFdtKSziGMNkNHorH1?cluster=devnet
```

### Deployment Status
- ✅ Program deployed to devnet
- ✅ Pool initialized with 0% fee
- ✅ Three tokens added (USDC, USDF, SFTUSD25)
- ✅ Liquidity deposited (asymmetric: USDF=10, SFTUSD25=10, USDC=0 initially)
- ✅ Swaps tested (USDC→USDF, USDF→SFTUSD25)
- ✅ Authorities transferred
- ✅ IDL published to devnet

### Next Steps (Optional)
- [ ] Test additional swap scenarios
- [ ] Test pause/unpause functionality with new authorities
- [ ] Add more liquidity if needed
- [ ] Monitor pool performance
- [ ] Prepare for mainnet deployment when ready

---

## Testing Scenarios Checklist

### Basic Functionality - Stablecoin Swaps
- [x] Swap USDC -> USDF (small amount) - 1 USDC → 1 USDF ✓
- [ ] Swap USDF -> USDC (small amount)
- [ ] Swap USDC -> SFTUSD25 (small amount)
- [ ] Swap SFTUSD25 -> USDC (small amount)
- [x] Swap USDF -> SFTUSD25 (small amount) - 1 USDF → 1 SFTUSD25 ✓
- [ ] Swap SFTUSD25 -> USDF (small amount)
- [ ] Swap USDC -> USDF (large amount)
- [ ] Swap USDC -> SFTUSD25 (large amount)
- [x] Verify fee collection (0% fee - no fees collected) ✓

### Liquidity Operations
- [x] Deposit USDC liquidity - Skipped (asymmetric pool) ✓
- [x] Deposit USDF liquidity - 10 tokens ✓
- [x] Deposit SFTUSD25 liquidity - 10 tokens ✓
- [ ] Withdraw USDC liquidity
- [ ] Withdraw USDF liquidity
- [ ] Withdraw SFTUSD25 liquidity

### Security & Controls
- [ ] Pause swaps
- [ ] Unpause swaps
- [ ] Pause liquidity operations
- [ ] Unpause liquidity operations
- [ ] Update fee rate
- [x] Update authorities - Operations & Pause authorities transferred ✓

### Edge Cases
- [ ] Insufficient liquidity error
- [ ] Slippage exceeded error
- [ ] Maximum swap amount
- [ ] Minimum swap amount

---

## Emergency Commands

### Pause Swaps
```bash
yarn ts-node scripts/emergency-pause-swaps.ts
```

### Pause Liquidity Operations
```bash
yarn ts-node scripts/emergency-pause-liquidity.ts
```

### Withdraw Emergency Liquidity
```bash
yarn ts-node scripts/emergency-withdraw.ts <TOKEN_MINT> <AMOUNT>
```

### Resume Operations
```bash
yarn ts-node scripts/unpause-swaps.ts
yarn ts-node scripts/unpause-liquidity.ts
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

### Lessons Learned
1. `___________________`
2. `___________________`
3. `___________________`

---

## Differences from Mainnet Deployment

| Aspect | Mainnet | Devnet |
|--------|---------|--------|
| RPC URL | `https://api.mainnet-beta.solana.com` | `https://api.devnet.solana.com` |
| USDC Mint | `EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v` | `4zMMC9srt5Ri5X14GAgXhaHii3GnPAEERYPJgZJDncDU` |
| SOL Cost | Real SOL (~4-5 SOL) | Free from faucet |
| Explorer | `solscan.io/tx/<SIG>` | `solscan.io/tx/<SIG>?cluster=devnet` |
| Risk Level | High (real funds) | Low (test tokens) |
| Purpose | Production | Testing/Development |

---

**Deployment Status:** ⏳ Not Started

**Started Date:** `___________________`

**Completion Date:** `___________________`

**Deployed By:** `___________________`

**Verified By:** `___________________`
