# StableSwapper -- Solana

A production-ready Solana-based liquidity management system designed for secure, efficient 1:1 stablecoin swapping with configurable fees and comprehensive admin controls.

## 🏗️ Key Features

- ✅ **1:1 Token Swaps**: Guaranteed parity swapping between supported stablecoins
- ✅ **Role-Based Authority Model**: Four in-program roles split between cold and hot keys (Pause, Unpause, Treasury, Configure)
- ✅ **Withdraw Recipient Allowlist**: `withdraw_liquidity` can only target a token account owned by an allowlisted address; the allowlist is managed by the cold-key Configure Authority
- ✅ **Slippage Protection**: User-defined minimum output amounts prevent unexpected losses
- ✅ **Granular Pause Controls**: Independent pause flags for swaps, withdraws, and per-token; pausing is hot, unpausing is cold
- ✅ **Configurable Fees**: Cold-key controlled fee rates (0-10% max) with separate fee recipient
- ✅ **Multi-token Support**: Dynamic token addition with vault creation (up to 50 tokens)

## 📁 Project Structure

```
├── programs/stable-swapper/         # Solana program (Rust/Anchor)
│   ├── src/
│   │   ├── lib.rs                    # Instructions + account constraints
│   │   ├── state.rs                  # Pool / vault account layouts
│   │   ├── utils.rs                  # Decimal normalization (round-down)
│   │   ├── constants.rs
│   │   └── errors.rs
│   └── Cargo.toml
├── tests/                            # Anchor / bankrun program tests
│   ├── stable-swapper.ts            # RBAC roles, allowlist, swaps, pauses
│   ├── initialize-guards.ts          # initialize role guards (bankrun)
│   └── migration.ts                  # Legacy → role-layout migrate_authorities
├── Anchor.toml                       # Anchor configuration
├── Cargo.toml                        # Workspace configuration
└── package.json                      # JS test / tooling deps
```

Production deploy and one-shot `migrate_authorities` execution are handled outside
this package (internal tooling). This repo carries the on-chain program and its tests.

## 🚀 Getting Started

### Prerequisites

- **Rust** 1.70.0+
- **Node.js** 18.0.0+
- **Anchor CLI** 0.31.1+
- **Solana CLI** 1.18.0+

### Installation

1. **Clone the repository**
   ```bash
   git clone https://github.com/coinbase/stable-swapper.git
   cd stable-swapper/solana
   ```

2. **Install dependencies**
   ```bash
   # Install Rust dependencies
   cargo build
   ```

3. **Configure Solana for development**
   ```bash
   # Set to devnet
   solana config set --url devnet

   # Create a keypair (if needed)
   solana-keygen new --outfile ~/.config/solana/id.json

   # Airdrop SOL for testing
   solana airdrop 2
   ```

## 🔧 Development Workflow

### Building the Solana Program

```bash
# Build the program
anchor build

# Deploy to devnet
anchor deploy --provider.cluster devnet
```

### Running the Test Suite

The committed `declare_id!` is the **mainnet** program ID (`pqgqK…`, matching
`[programs.mainnet]` and `[programs.localnet]`); `[programs.devnet]` points at
the separate devnet deployment. To run the Anchor / Mocha suite against a local
validator, generate a throwaway keypair and align all three references to it
before building:

```bash
# Mint an ephemeral test keypair and align the program ID everywhere
mkdir -p target/deploy
solana-keygen new --no-bip39-passphrase --silent --force \
  --outfile target/deploy/stable_swapper-keypair.json
TEST_ID=$(solana address -k target/deploy/stable_swapper-keypair.json)
perl -pi -e "s/declare_id!\\(\"[^\"]+\"\\)/declare_id!(\"$TEST_ID\")/" \
  programs/stable-swapper/src/lib.rs
awk -v id="$TEST_ID" '
  /^\[/  { in_localnet = ($0 ~ /^\[programs\.localnet\]$/) }
  in_localnet && /^stable_swapper[[:space:]]*=/ {
    print "stable_swapper = \"" id "\""; next
  }
  { print }
' Anchor.toml > Anchor.toml.tmp && mv Anchor.toml.tmp Anchor.toml

# Build and run the suite
yarn install --frozen-lockfile
anchor build
anchor test --provider.cluster localnet --skip-build

# Restore the committed IDs when done
git checkout -- programs/stable-swapper/src/lib.rs Anchor.toml
```

CI runs the equivalent of these steps in `.github/workflows/test.yml`.

### Network Configuration

The system is configured for **Solana Devnet** by default. To change networks:

1. Point the Anchor provider at the target cluster in `Anchor.toml` (`[provider] cluster`),
   or pass `--provider.cluster` on the command line.
2. Update your Solana CLI configuration:
   ```bash
   solana config set --url mainnet-beta # or devnet
   ```

## 🏛️ Program Architecture

### Design Philosophy

**StableSwapper uses a single centralized pool** for all users and tokens:
- Pool PDA: `[b"liquidity_pool"]` (no authority in seeds)
- Only ONE pool exists per program deployment
- All users interact with the same global pool
- Authority controls the pool but doesn't "own" separate instances

**Fee Model**:
- Fees are charged on the **input token** (the token being swapped FROM)
- User provides the full swap amount, which is split:
  - **Net amount** (after fee) → goes to vault as liquidity
  - **Fee amount** → goes to fee_recipient as protocol revenue
- Example: Swap 100 USDC → AppStable with 1% fee:
  - User transfers: 100 USDC total
  - Vault receives: 99 USDC (liquidity)
  - Fee recipient receives: 1 USDC (protocol fee)
  - User receives: 99 AppStable (1:1 with net amount)

**Swap Account Model**:
- Swaps are permissionless when `swaps_paused` is false and both tokens are enabled
- `user_from_token_account` does not need to be owned by `user`; the SPL Token program enforces that `user` is either the owner or a valid delegate
- `to_token_account` may be any valid token account for the output mint, so delegated swaps can route output to a recipient chosen by the delegate

### Roles

| Role | Key class | Permissions |
| --- | --- | --- |
| Pause Authority | hot | `pause_swaps`, `pause_withdraws`, `pause_token` |
| Unpause Authority | cold | `unpause_swaps`, `unpause_withdraws`, `unpause_token` |
| Treasury Authority | hot | `withdraw_liquidity` (recipient must be on `withdraw_recipients` allowlist) |
| Configure Authority | cold | `add_supported_token`, `remove_supported_token`, `update_fee_rate`, `update_fee_recipient`, `add_withdraw_recipient`, `remove_withdraw_recipient` |
| Each role | (self) | `update_<role>_authority` (strict self-rotation) |

The on-chain program upgrade authority is held by the BPF loader (rotate via `solana program set-upgrade-authority`) and is independent from the in-program roles above. It cannot exercise any of them, but it is the only key that can run the two pool-lifecycle instructions: `initialize` and `migrate_authorities` both require the payer to be the current upgrade authority. This is not extra privilege — a key that can deploy new bytecode to this program ID can already rewrite the pool account however it likes — but it does mean the upgrade authority alone can seed or redistribute every role, so it must be held to the same standard as the cold keys it assigns.

### Core Instructions

- **`initialize`**: Creates pool with the four role authorities, fee recipient, and a withdraw allowlist seeded with one recipient. Restricted to the program's upgrade authority: takes the program's `ProgramData` account (the BPF upgradeable loader PDA seeded by the program ID) and requires `upgrade_authority_address == payer`, so deploy and initialize are performed by the same key
- **`migrate_authorities`**: One-shot migration of an existing legacy pool to the role-based layout; seeds the withdraw allowlist with the provided recipient. Restricted to the program's upgrade authority on the same `ProgramData` check as `initialize`; the legacy `operations_authority` and `pause_authority` stored in the pool are overwritten and are not consulted. Invoked by internal migration tooling, not by in-repo CLIs.
- **`add_supported_token` / `remove_supported_token`**: Configure Authority manages supported tokens
- **`swap`**: Executes 1:1 swaps with slippage protection (`min_amount_out`). Legacy account layout: still carries the deprecated `whitelist` PDA slot (seeds-verified, never read) so existing callers keep working; it is removed once callers cut over to `swap_v2`
- **`swap_v2`**: Same arguments, logic, and effects as `swap` without the deprecated `whitelist` account. Use this for new integrations
- **`withdraw_liquidity`**: Treasury Authority withdraws to a token account whose owner is on the `withdraw_recipients` allowlist
- **`update_fee_rate` / `update_fee_recipient`**: Configure Authority updates the fee rate (basis points) and the fee recipient independently. The fee recipient cannot be set to the default pubkey, at creation or afterwards, since it is the token-account authority every fee is transferred to
- **`add_withdraw_recipient` / `remove_withdraw_recipient`**: Configure Authority manages the withdraw allowlist (up to 10 entries)
- **`pause_swaps` / `pause_withdraws` / `pause_token`**: Pause Authority puts the corresponding flag in the paused state
- **`unpause_swaps` / `unpause_withdraws` / `unpause_token`**: Unpause Authority clears the flag
- **`update_<role>_authority`**: Each role self-rotates (no cross-role rotation)

Liquidity is seeded by sending tokens directly to the vault token account via an SPL Token transfer; there is no dedicated deposit instruction.

## 🔐 Security Features

### Access Controls
- **Deploy-gated lifecycle**: `initialize` and `migrate_authorities` are restricted to the program upgrade authority. The pool PDA has a fixed seed and no instruction can close it, so the first successful `initialize` claims the only pool a deployment will ever have; gating it removes the griefing window between deploy and initialize, whose only other remedy is redeploying at a new program ID. Note both instructions stop working once the program is made immutable
- **Four-role model**: Pause/Unpause/Treasury/Configure split across cold and hot keys
- **Strict self-rotation**: Each role rotates only itself; no role can take over another
- **Withdraw recipient allowlist**: `withdraw_liquidity` recipient must be a token account whose owner is on `pool.withdraw_recipients`; only the cold-key Configure Authority can add or remove entries, so a compromised hot Treasury key cannot redirect funds to a new address
- **Pausing is hot, unpausing is cold**: A compromised hot key can pause but cannot resume operations
- **Granular pause controls**: Independent `swaps_paused`, `liquidity_paused`, and per-token `disabled` flags
- **Fee rate cap**: Maximum 10% (1000 basis points) enforced at program level

### Liquidity Safety
- **Slippage protection**: Users specify `min_amount_out` to prevent TOCTOU attacks
- **PDA-based validation**: Accounts validated using program-derived addresses
- **Balance validation**: Ensures sufficient vault balance before swaps and withdrawals
- **Overflow protection**: Checked arithmetic throughout

### Error Handling
- **Comprehensive error codes**: Detailed error messages for debugging
- **Input validation**: All parameters validated at program level
- **Account ownership verification**: Fee recipient token accounts verified to match pool configuration

## 🚀 Deployment

Program binaries are built with Anchor and deployed via your usual Solana release
process (upgrade authority is independent of in-program roles). There are no
in-repo ops CLIs or deployment runbooks; use internal deploy / migration tooling
for production upgrades and `migrate_authorities`.

**Program ID must match the deployment.** `declare_id!` is compiled into the
binary and checked at runtime against the address the program is deployed at; a
mismatch makes the program reject every instruction with
`DeclaredProgramIdMismatch`. The committed `declare_id!` is the **mainnet** ID,
so a mainnet build uses the source as-is and CI enforces
`declare_id == [programs.mainnet]`. A **devnet** build must first patch
`declare_id!` (and `[programs.localnet]`) to `[programs.devnet]`; otherwise a
devnet upgrade bricks the same way.

```bash
# Local / CI build
anchor build

# Inspect a deployed program
solana program show <PROGRAM_ID>
```
