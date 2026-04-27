# SCaaS - Stablecoin-as-a-Service Liquidity Management

A production-ready Solana-based liquidity management system designed for secure, efficient 1:1 stablecoin swapping with configurable fees and comprehensive admin controls.

## 🏗️ Key Features

- ✅ **1:1 Token Swaps**: Guaranteed parity swapping between supported stablecoins
- ✅ **Dual Authority Model**: Separate operations and pause authorities with multisig support
- ✅ **Slippage Protection**: User-defined minimum output amounts prevent unexpected losses
- ✅ **Granular Pause Controls**: Independent pause flags for swaps and liquidity management
- ✅ **Configurable Fees**: Admin-controlled fee rates (0-10% max) with separate fee recipient
- ✅ **Multi-token Support**: Dynamic token addition with vault creation (up to 50 tokens)
- ✅ **Access Controls**: Comprehensive authority validation and security measures

## 📁 Project Structure

```
├── programs/scaas-liquidity/         # Solana program (Rust/Anchor)
│   ├── src/
│   │   |── lib.rs                    # Main program logic
│   │   |── state.rs
│   │   |── constants.rs
│   │   └── errors.rs
│   └── Cargo.toml
├── tests/                            # Program tests
├── target/                           # Build artifacts
├── Anchor.toml                       # Anchor configuration
└── Cargo.toml                        # Workspace configuration
```

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
   cd stable-swapper/svm
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

The committed `declare_id!` and `[programs.devnet]` / `[programs.mainnet]`
entries point at the real deployed programs. To run the Anchor / Mocha suite
against a local validator, generate a throwaway keypair and align all three
references to it before building:

```bash
# Mint an ephemeral test keypair and align the program ID everywhere
mkdir -p target/deploy
solana-keygen new --no-bip39-passphrase --silent --force \
  --outfile target/deploy/scaas_liquidity-keypair.json
TEST_ID=$(solana address -k target/deploy/scaas_liquidity-keypair.json)
perl -pi -e "s/declare_id!\\(\"[^\"]+\"\\)/declare_id!(\"$TEST_ID\")/" \
  programs/scaas-liquidity/src/lib.rs
awk -v id="$TEST_ID" '
  /^\[/  { in_localnet = ($0 ~ /^\[programs\.localnet\]$/) }
  in_localnet && /^scaas_liquidity[[:space:]]*=/ {
    print "scaas_liquidity = \"" id "\""; next
  }
  { print }
' Anchor.toml > Anchor.toml.tmp && mv Anchor.toml.tmp Anchor.toml

# Build and run the suite
yarn install --frozen-lockfile
anchor build
anchor test --provider.cluster localnet --skip-build

# Restore the committed IDs when done
git checkout -- programs/scaas-liquidity/src/lib.rs Anchor.toml
```

CI runs the equivalent of these steps in `.github/workflows/test.yml`.

### Network Configuration

The system is configured for **Solana Devnet** by default. To change networks:

2. Update your Solana CLI configuration:
   ```bash
   solana config set --url mainnet-beta # or devnet
   ```

## 🏛️ Program Architecture

### Design Philosophy

**SCaaS uses a single centralized pool** for all users and tokens:
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

### Core Instructions

- **`initialize_pool`**: Creates pool with operations & pause authorities, fee configuration
- **`add_supported_token`**: Adds token with dedicated vault (operations authority)
- **`swap`**: Executes 1:1 swaps with slippage protection (`min_amount_out`)
- **`withdraw_liquidity`**: Removes liquidity from a vault (operations authority, checks `liquidity_paused`)
- **`update_fee_config`**: Updates fee rate and recipient (operations authority)
- **`update_pause_config`**: Controls `swaps_paused` and `liquidity_paused` (pause authority)
- **`update_operations_authority`**: Self-updates operations authority (operations authority only)
- **`update_pause_authority`**: Self-updates pause authority (pause authority only)

Liquidity is seeded by sending tokens directly to the vault token account via an SPL Token transfer; there is no dedicated deposit instruction.

## 🔐 Security Features

### Access Controls
- **Dual authority model**: Separate operations and pause authorities (multisig-ready)
- **Self-updating authorities**: Each authority can only update itself
- **Authority validation**: Operations enforce constraints via PDAs
- **Granular pause controls**: Independent `swaps_paused` and `liquidity_paused` flags
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

### Program Deployment

```bash
# Build for production
anchor build --verifiable

# Deploy
anchor deploy --provider.cluster <devnet or mainnet>

# Verify deployment
solana program show <PROGRAM_ID>
```
