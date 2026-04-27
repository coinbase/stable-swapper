# Mainnet Deployment Runbook - Liquidity Pool Program

**Status:** In Progress
**Date Started:** 2026-01-08
**Deployer:** DxRhDVvDbUhM5jCkyVsFoG5qoydnUFkkkvx5DzPfjahN

---

## Overview

This runbook guides you through deploying the liquidity pool program to Solana mainnet and initializing it with your custom token and USDC.

**Program ID:** `pqgqKahpG1y2wsgxFhzaAnkV1cL9vk8MSg9qm4q646F`

---

## Key Information

### Addresses
- **Deployer Wallet:** `DxRhDVvDbUhM5jCkyVsFoG5qoydnUFkkkvx5DzPfjahN`
- **Custom Token Mint:** `5AMAA9JV9H97YYVxx8F6FsCMmTwXSuTTQneiup4RYAUQ`
- **Custom Token Decimals:** `6`
- **USDC Mint:** `EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v`
- **Pool PDA:** `CrDL9SoCyW1tBgn8k7rgGSpWhnszneWDbvKvqPAU4PL9`
- **Custom Token Vault:** `3vxe5BnJUWNz3kgSLXKaGuibTnjofxgGuAjhpMeEq95s`
- **Custom Token Vault Token Account:** `ZR8euZnAt7duoF7PfEqkq6ZqFJmaLQzKqEWAmozH4uq`
- **USDC Vault:** `2bQv8iFVXm9Z6wJk7KMFhhtLegNFZPtcDeJc5qrwJNqZ`
- **USDC Vault Token Account:** `YioohQk1msG36osqTZ9bUG9GwaygVpq9ACQ7gUrtUHr`

### Configuration
- **Fee Rate:** 0 basis points (0% - for 1:1 swaps)
- **Operations Authority:** `7GSEFPKdHUZabc4qJkrrEmE4ZVVC1QJ721HmQTQBaUTw` (Squad multisig)
- **Pause Authority:** `7GSEFPKdHUZabc4qJkrrEmE4ZVVC1QJ721HmQTQBaUTw` (Squad multisig)
- **Fee Recipient:** `DxRhDVvDbUhM5jCkyVsFoG5qoydnUFkkkvx5DzPfjahN` (Deployer wallet)

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
- Notes: All versions verified and compatible

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
- [x] Completed
- Wallet Address: `DxRhDVvDbUhM5jCkyVsFoG5qoydnUFkkkvx5DzPfjahN`

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
- Balance: `4.5` SOL
- Notes: `___________________`

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
- [x] Completed
- Program Size: (verified)
- Program ID from keypair: `pqgqKahpG1y2wsgxFhzaAnkV1cL9vk8MSg9qm4q646F`
- Program ID in Anchor.toml: `pqgqKahpG1y2wsgxFhzaAnkV1cL9vk8MSg9qm4q646F`
- IDs Match: `Yes`
- Notes: All program IDs verified and matching

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
- [x] Completed
- Transaction Signature: `5whPL6zDk3bnCSXfqAFNEe5CJLyNsXsyMXV2apq7sopz1GbrbxidHspGnD4onLaerGLSB4dsrgSrhfdHoYptzZZJ`
- Program ID: `pqgqKahpG1y2wsgxFhzaAnkV1cL9vk8MSg9qm4q646F`
- Deployment Cost: (to be calculated from balance change)
- Timestamp: `2026-01-08`
- Notes: Deploy success

---

### ✅ Step 2.3: Verify Deployment
**Command:**
```bash
solana program show GadmXgM1J4NhkbqbpnAbEQxHssZAavWxG5uV6AHiLMHv
```

**Result:**
- [x] Completed
- Program Exists: `Yes`
- **Program Id**: `pqgqKahpG1y2wsgxFhzaAnkV1cL9vk8MSg9qm4q646F`
- **Owner**: `BPFLoaderUpgradeab1e11111111111111111111111`
- **ProgramData Address**: `DTm7oAyMA5VZEthWxYVz4T4hC7rReH5gWAVndi7X38hc`
- **Authority**: `DxRhDVvDbUhM5jCkyVsFoG5qoydnUFkkkvx5DzPfjahN`
- **Last Deployed In Slot**: `392183756`
- **Data Length**: `462928 bytes`
- **Balance**: `3.22318296 SOL`
- Notes: Program successfully deployed and verified on mainnet

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
export ANCHOR_WALLET="$HOME/.config/solana/prod-deploy.json"
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
- [x] Completed
- Fee Rate Used: `0` bps
- Transaction Signature: `4K3GHRFcfirJhvWGf6ztqebSAjx5enab49Ymx9TRjs94mNA3wcQSXmcqk9m4v9uYrdKMk2bqMTxRKxKYNpDHHaEm`
- Pool PDA: `CrDL9SoCyW1tBgn8k7rgGSpWhnszneWDbvKvqPAU4PL9`
- Timestamp: `2026-01-08`
- Notes: Pool initialized successfully with 0% fee for 1:1 swaps

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
- Notes: `___________________`

---

## PHASE 4: Add Custom Token

### ✅ Step 4.1: Add Custom Token to Pool
**Note:** We use a universal `02-add-token.ts` script that works for any token.

**Command:**
```bash
yarn ts-node scripts/02-add-token.ts 5AMAA9JV9H97YYVxx8F6FsCMmTwXSuTTQneiup4RYAUQ
```

**Result:**
- [x] Completed
- Transaction Signature: `4mnyk5f2d8DZnMmYNvbgxheeka7skmzd9coNoXqVNBpxmz11i6z9WhyATkg2csJ6jf4dbT9FnS2Ya3odAXF5q7fF`
- Custom Token Vault PDA: `3vxe5BnJUWNz3kgSLXKaGuibTnjofxgGuAjhpMeEq95s`
- Custom Token Vault Token Account: `ZR8euZnAt7duoF7PfEqkq6ZqFJmaLQzKqEWAmozH4uq`
- Fee Recipient Token Account: `4EPEmWxcw1bAjskVStpWpuDzstT8Vuv67r7j1aCFQhAp`
- Timestamp: `2026-01-08`
- Notes: Custom token 5AMAA9JV9H97YYVxx8F6FsCMmTwXSuTTQneiup4RYAUQ added successfully

---

### ✅ Step 4.2: Verify Custom Token Added
**Result:**
- [x] Completed
- Token in Supported List: `Yes`
- Vault Exists: `Yes`
- Vault Token Account Exists: `Yes`
- Fee Recipient ATA Created: `Yes`
- Notes: Pool now has 2 supported tokens (Custom Token + USDC)

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
- Transaction Signature: `4PK7HfJZY7cy8pbQCQcMEDzmgiJgApY1A1FZng3hguTUYupe2QVSvMEyXGzF5UFvxaF5hmBjavQxQM1qjuu9okHt`
- USDC Vault PDA: `2bQv8iFVXm9Z6wJk7KMFhhtLegNFZPtcDeJc5qrwJNqZ`
- USDC Vault Token Account: `YioohQk1msG36osqTZ9bUG9GwaygVpq9ACQ7gUrtUHr`
- Fee Recipient Token Account: `C9jw5StZLXWwM6N7NGqfxeZfvKmToKivT74148EnNGBJ`
- Timestamp: `2026-01-08`
- Notes: USDC added successfully to pool

---

### ✅ Step 5.2: Verify USDC Added
**Result:**
- [x] Completed
- Token in Supported List: `Yes`
- Vault Exists: `Yes`
- Vault Token Account Exists: `Yes`
- Fee Recipient ATA Created: `Yes`
- Notes: Pool verified with 1 supported token (USDC), 0 balance

---

## PHASE 6: Deposit Liquidity

### ✅ Step 6.1: Check Token Balances
**Commands:**
```bash
# Check your custom token balance
spl-token balance 5AMAA9JV9H97YYVxx8F6FsCMmTwXSuTTQneiup4RYAUQ

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

### ✅ Step 6.2: Deposit Custom Token Liquidity
**Planned Amount:** `10000` tokens

**Note:** Custom token liquidity was added via direct transfer to the vault token account instead of using the deposit-liquidity script.

**Method Used:** Direct SPL token transfer

**Transfer Details:**
- From: External account with token supply
- To: Vault Token Account `ZR8euZnAt7duoF7PfEqkq6ZqFJmaLQzKqEWAmozH4uq`
- Transfer 1: 1 token
- Transfer 2: 9999 tokens
- Total: 10000 tokens

**Result:**
- [x] Completed
- Transaction Signature: `(direct transfers - not via program)`
- Amount Deposited: `10000` tokens
- Vault Balance After: `10000` tokens
- Timestamp: `2026-01-08`
- Notes: Direct transfers bypass program deposit tracking but add liquidity to vault. For future deposits, prefer using deposit-liquidity script for proper tracking.

---

### ✅ Step 6.3: Deposit USDC Liquidity
**Planned Amount:** `0` USDC (skipped for initial deployment)

**Note:** USDC liquidity will be added organically through swaps. Starting with only custom token liquidity allows users to swap USDC → Custom Token.

**Result:**
- [x] Completed (skipped)
- Transaction Signature: `N/A`
- Amount Deposited: `0` USDC
- Vault Balance After: `0` USDC
- Timestamp: `2026-01-08`
- Notes: Pool launched with asymmetric liquidity - 10,000 Custom Tokens only. USDC will accumulate as users swap.

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
- Custom Token Vault Balance: `10,000 tokens`
- USDC Vault Balance: `0 USDC`
- Total Liquidity USD Value: `~$10,000 (assuming 1:1 peg)`
- Notes: Pool verified and ready for swaps. Asymmetric liquidity - only custom token side funded initially.

---

### ✅ Step 7.2: Test Swap (Optional but Recommended)
**Test:** Small swap of 1 USDC -> Custom Token

**Command:**
```bash
yarn ts-node scripts/04-test-swap.ts EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v 5AMAA9JV9H97YYVxx8F6FsCMmTwXSuTTQneiup4RYAUQ 1
```

**Result:**
- [x] Completed
- Transaction Signature: `3wexohabLBTZTjrA8knVqU6Td6aGrioYJAo61SpStchg4AUc15AtyobYNMSovYTrHCJPdbx8jmaa8cRQhhiy9r5`
- Input: `1` USDC
- Output: `1` Custom Token
- Exchange Rate: `1:1 (0% fee)`
- Timestamp: `2026-01-08`
- Notes: Swap successful. Pool now has 1 USDC and 9,999 Custom Tokens

---

### ✅ Step 7.3: Test Reverse Swap (Optional but Recommended)
**Test:** Reverse swap of 1 Custom Token -> USDC

**Command:**
```bash
yarn ts-node scripts/04-test-swap.ts 5AMAA9JV9H97YYVxx8F6FsCMmTwXSuTTQneiup4RYAUQ EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v 1
```

**Result:**
- [x] Completed
- Transaction Signature: `C4XLd2L1sGiifWp8c4ALrwXA6AbNobhTc2ZiogiizCWmQ4Wtchx3YjRL7iUWHpLXKhcEQJZejM2WNDyMTmwDHCE`
- Input: `1` Custom Token
- Output: `1` USDC
- Exchange Rate: `1:1 (0% fee)`
- Timestamp: `2026-01-08`
- Notes: Swap successful (confirmation timed out but transaction succeeded). Pool restored to original state: 0 USDC and 10,000 Custom Tokens

---

## PHASE 8: Transfer Pause Authority to Squad Multisig

### ✅ Step 8.1: Transfer Pause Authority to Squad

**Squad Multisig Address:** `7GSEFPKdHUZabc4qJkrrEmE4ZVVC1QJ721HmQTQBaUTw`

**Command:**
```bash
yarn ts-node scripts/update-pause-authority.ts 7GSEFPKdHUZabc4qJkrrEmE4ZVVC1QJ721HmQTQBaUTw
```

**Result:**
- [x] Completed
- Transaction Signature: `4rzuiFqW7uNLQcC5PoXPAsFJ8tMLrFLasQotZDvAwRStJct4b95a43GyMo4BSUf2jgr9paeMiaZee4sKGZw1BZpG`
- Old Pause Authority: `DxRhDVvDbUhM5jCkyVsFoG5qoydnUFkkkvx5DzPfjahN` (Deployer wallet)
- New Pause Authority: `7GSEFPKdHUZabc4qJkrrEmE4ZVVC1QJ721HmQTQBaUTw` (Squad multisig)
- Timestamp: `2026-01-08`
- Notes: Pause authority successfully transferred to Squad multisig for enhanced security

---

### ✅ Step 8.2: Verify Authority Transfer

**Command:**
```bash
yarn ts-node scripts/view-pool-state.ts
```

**Result:**
- [x] Completed
- Pause Authority Verified: `7GSEFPKdHUZabc4qJkrrEmE4ZVVC1QJ721HmQTQBaUTw`
- Operations Authority: `DxRhDVvDbUhM5jCkyVsFoG5qoydnUFkkkvx5DzPfjahN` (Still with deployer)
- Notes: Pause operations now require Squad multisig approval

---

## PHASE 9: Transfer Operations Authority to Squad Multisig

### ✅ Step 9.1: Transfer Operations Authority to Squad

**Squad Multisig Address:** `7GSEFPKdHUZabc4qJkrrEmE4ZVVC1QJ721HmQTQBaUTw`

**Command:**
```bash
yarn ts-node scripts/update-operations-authority.ts 7GSEFPKdHUZabc4qJkrrEmE4ZVVC1QJ721HmQTQBaUTw
```

**Result:**
- [x] Completed
- Transaction Signature: `3GHiRxe4K13FnupTCsYpcZ57Z6VaiU4maq3nKehCSuv8FC7nMPKYZB36vLcDSFVjN5pLVxNcZ2zNjQ5cAPGr958w`
- Old Operations Authority: `DxRhDVvDbUhM5jCkyVsFoG5qoydnUFkkkvx5DzPfjahN` (Deployer wallet)
- New Operations Authority: `7GSEFPKdHUZabc4qJkrrEmE4ZVVC1QJ721HmQTQBaUTw` (Squad multisig)
- Timestamp: `2026-01-08`
- Notes: Operations authority successfully transferred to Squad multisig for enhanced security

---

### ✅ Step 9.2: Verify Authority Transfer

**Command:**
```bash
yarn ts-node scripts/view-pool-state.ts
```

**Result:**
- [x] Completed
- Operations Authority Verified: `7GSEFPKdHUZabc4qJkrrEmE4ZVVC1QJ721HmQTQBaUTw`
- Pause Authority Verified: `7GSEFPKdHUZabc4qJkrrEmE4ZVVC1QJ721HmQTQBaUTw`
- Notes: Both critical authorities now require Squad multisig approval for maximum security

---

## PHASE 10: Transfer Program Upgrade Authority to Squad Multisig

### ✅ Step 10.1: Verify Current Upgrade Authority

**Command:**
```bash
solana program show pqgqKahpG1y2wsgxFhzaAnkV1cL9vk8MSg9qm4q646F
```

**Result:**
- Authority: `DxRhDVvDbUhM5jCkyVsFoG5qoydnUFkkkvx5DzPfjahN` (Deployer wallet)

---

### ✅ Step 10.2: Transfer Upgrade Authority to Squad

**Squad Multisig Address:** `7GSEFPKdHUZabc4qJkrrEmE4ZVVC1QJ721HmQTQBaUTw`

**Command:**
```bash
solana program set-upgrade-authority pqgqKahpG1y2wsgxFhzaAnkV1cL9vk8MSg9qm4q646F --new-upgrade-authority /Users/salioudiallo/.config/solana/upgrade-authority-keypair.json
```

**Result:**
- [x] Completed
- Account Type: Program
- New Authority: `7GSEFPKdHUZabc4qJkrrEmE4ZVVC1QJ721HmQTQBaUTw` (Squad multisig)
- Timestamp: `2026-01-08`
- Notes: Program upgrade authority successfully transferred to Squad multisig

---

### ✅ Step 10.3: Verify Upgrade Authority Transfer

**Command:**
```bash
solana program show pqgqKahpG1y2wsgxFhzaAnkV1cL9vk8MSg9qm4q646F
```

**Result:**
- [x] Completed
- Program Id: `pqgqKahpG1y2wsgxFhzaAnkV1cL9vk8MSg9qm4q646F`
- Authority Verified: `7GSEFPKdHUZabc4qJkrrEmE4ZVVC1QJ721HmQTQBaUTw`
- ProgramData Address: `DTm7oAyMA5VZEthWxYVz4T4hC7rReH5gWAVndi7X38hc`
- Data Length: `462928 bytes`
- Balance: `3.22318296 SOL`
- Notes: All program upgrades now require Squad multisig approval

---

## PHASE 11: Publish IDL to Mainnet

### ✅ Step 11.1: Publish IDL

**Command:**
```bash
anchor idl init pqgqKahpG1y2wsgxFhzaAnkV1cL9vk8MSg9qm4q646F --filepath target/idl/scaas_liquidity.json --provider.cluster mainnet
```

**Result:**
- [x] Completed
- IDL Data Length: `3348 bytes`
- IDL Account Created: `GaoCsbFejpUYNjnLaHYh4bc4QPtth7Gq5oCtsJ6d4PKc`
- Timestamp: `2026-01-08`
- Notes: IDL successfully published to mainnet, making program interface publicly available

---

### ✅ Step 11.2: Verify IDL Published

**IDL Explorer URL:**
```
https://www.orbmarkets.io/address/pqgqKahpG1y2wsgxFhzaAnkV1cL9vk8MSg9qm4q646F/anchor-idl
```

**Result:**
- [x] Completed
- IDL Publicly Accessible: Yes
- Notes: Program interface now available for wallets, explorers, and frontends to interact with the liquidity pool

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
Custom Token Mint: ___________________
Custom Token Vault: ___________________
Custom Token Vault Token Account: ___________________
USDC Mint: EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v
USDC Vault: ___________________
USDC Vault Token Account: ___________________
```

### Next Steps
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
