# StableSwapper -- Solana

Solana / Anchor implementation of StableSwapper: a 1:1 stablecoin swap program that lets a custom stablecoin be paired with USDC (or other listed stablecoins) at a fixed rate with configurable fees, slippage protection, and administrative controls.

## Features

- **1:1 Token Swaps** -- Fixed-rate swapping between any listed stablecoins
- **Dual Authority Model** -- Separate operations and pause authorities, both compatible with multisigs
- **Slippage Protection** -- User-supplied minimum output amount per swap
- **Granular Pause Controls** -- Independent pause flags for swaps and liquidity management
- **Configurable Fees** -- Admin-controlled fee rate (0--10%) with a dedicated fee recipient
- **Multi-token Support** -- Add up to 50 supported tokens, each with its own vault
- **Access Controls** -- Authority validation enforced via PDAs

## Project Structure

```
solana/
├── programs/stable-swapper/         # Solana program (Rust/Anchor)
│   └── src/
│       ├── lib.rs                   # Main program logic
│       ├── state.rs
│       ├── constants.rs
│       ├── errors.rs
│       └── utils.rs
├── tests/                           # Program tests (Anchor / Mocha)
├── Anchor.toml                      # Anchor configuration
└── Cargo.toml                       # Workspace configuration
```

## Prerequisites

- **Rust** 1.70+
- **Solana CLI** 2.2.21+
- **Anchor CLI** 0.31.1+
- **Node.js** 18+ with Yarn

## Getting Started

1. **Clone the repository**

```bash
git clone https://github.com/coinbase/stable-swapper.git
cd stable-swapper/solana
```

2. **Install dependencies**

```bash
cargo build
yarn install --frozen-lockfile
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

## Development Workflow

### Building the program

```bash
anchor build
```

### Running the test suite

The committed `declare_id!` and `[programs.devnet]` / `[programs.mainnet]`
entries in `Anchor.toml` point at the real deployed programs. To run the
Anchor / Mocha suite against a local validator, generate a throwaway keypair
and align all three references to it before building:

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

### Deploying

```bash
# Build verifiably
anchor build --verifiable

# Deploy
anchor deploy --provider.cluster <devnet|mainnet>

# Verify deployment
solana program show <PROGRAM_ID>
```

Deployments, pool initialization, and authority management are performed via
out-of-repo tooling; the contract under `programs/` is the source of truth
for the on-chain behavior.

## Program Architecture

### Pool design

The program uses a single centralized pool for all users and tokens:
- Pool PDA: `[b"liquidity_pool"]` (no authority in the seeds)
- Exactly one pool exists per program deployment
- All users interact with the same pool
- The operations authority controls the pool but does not "own" separate instances

### Fee model

Fees are charged on the **input token** (the token being swapped from). The user provides the full swap amount, which is split:

- **Net amount** (after fee) → goes to the destination vault as liquidity
- **Fee amount** → goes to the fee recipient as protocol revenue

Example: swap 100 USDC → custom stablecoin with a 1% fee:
- User transfers: 100 USDC total
- Vault receives: 99 USDC (liquidity)
- Fee recipient receives: 1 USDC (protocol fee)
- User receives: 99 custom-stablecoin (1:1 with the net amount)

### Swap permissions

- Swaps are permissionless when `swaps_paused` is `false` and both tokens are enabled.
- `user_from_token_account` does not need to be owned by `user`; the SPL Token program enforces that `user` is either the owner or a valid delegate.
- `to_token_account` may be any valid token account for the output mint, so delegated swaps can route output to a recipient chosen by the delegate.

### Core instructions

- **`initialize_pool`** — Creates the pool with operations + pause authorities and fee configuration
- **`add_supported_token`** — Adds a token with its dedicated vault (operations authority)
- **`swap`** — Executes a 1:1 swap with slippage protection (`min_amount_out`)
- **`withdraw_liquidity`** — Removes liquidity from a vault (operations authority, gated by `liquidity_paused`)
- **`update_fee_config`** — Updates the fee rate and recipient (operations authority)
- **`update_pause_config`** — Controls `swaps_paused` and `liquidity_paused` (pause authority)
- **`update_operations_authority`** — Operations authority updates itself
- **`update_pause_authority`** — Pause authority updates itself

Liquidity is seeded by sending tokens directly to the vault token account via an SPL Token transfer; there is no dedicated deposit instruction.

## Security

### Access controls
- **Dual authority model**: separate operations and pause authorities (both multisig-ready)
- **Self-updating authorities**: each authority can only update itself
- **Authority validation**: enforced via program-derived addresses
- **Granular pause controls**: independent `swaps_paused` and `liquidity_paused` flags
- **Fee rate cap**: maximum 10% (1000 basis points) enforced at program level

### Liquidity safety
- **Slippage protection**: users supply `min_amount_out` to prevent TOCTOU attacks
- **PDA-based validation**: accounts validated using program-derived addresses
- **Balance validation**: ensures sufficient vault balance before swaps and withdrawals
- **Overflow protection**: checked arithmetic throughout

### Error handling
- **Comprehensive error codes**: detailed messages for debugging
- **Input validation**: all parameters validated at the program level
- **Account ownership verification**: fee recipient token accounts verified against the pool configuration

For vulnerability disclosure, see the repository-root [`SECURITY.md`](../SECURITY.md).
