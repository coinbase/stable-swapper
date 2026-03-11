# StableSwapper -- EVM

Solidity implementation of StableSwapper using the UUPS upgradeable proxy pattern with OpenZeppelin contracts.

## Features

- **UUPS Upgradeability** -- Upgradeable via the [ERC-1967](https://eips.ethereum.org/EIPS/eip-1967) proxy pattern
- **ERC-7201 Namespaced Storage** -- Collision-resistant storage layout
- **Role-Based Access Control** -- Four distinct roles:
  - `DEFAULT_ADMIN_ROLE` -- Upgrades and role management (single holder, 2-step transfer)
  - `TREASURY_ROLE` -- Liquidity withdrawals and reserved amount management
  - `CONFIGURE_ROLE` -- Token listing, fee updates, and allowlist management
  - `PAUSE_ROLE` -- Pause/unpause operations and individual token status

### Limitations

- **No fee-on-transfer tokens** -- The contract assumes 1:1 transfers where the received amount equals the specified amount. Tokens that deduct fees during transfers will cause accounting errors and must not be listed.

## Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation) (forge, cast, anvil)

## Build

```sh
forge build
```

## Test

```sh
forge test -vvv
```

## Format

```sh
forge fmt --check
```

## Deploy

Set the required environment variables and run the deployment script. `RPC_URL` should be set to an RPC endpoint for the target network (e.g., from [Alchemy](https://www.alchemy.com/), [Infura](https://www.infura.io/), or a self-hosted node):

```sh
export RPC_URL=<https://your-rpc-endpoint>
export DEFAULT_ADMIN=<address>
export TREASURY_AUTHORITY=<address>
export CONFIGURE_AUTHORITY=<address>
export PAUSE_AUTHORITY=<address>
export FEE_RECIPIENT=<address>
export FEE_BASIS_POINTS=<uint16>
export ADMIN_TRANSFER_DELAY=<seconds>

forge script script/DeployStableSwapper.s.sol:DeployStableSwapper \
  --rpc-url $RPC_URL \
  --broadcast \
  --verify
```

## Verify an Existing Deployment

```sh
export RPC_URL=<https://your-rpc-endpoint>
export STABLE_SWAPPER_PROXY=<proxy_address>

forge script script/VerifyDeployment.s.sol:VerifyDeployment \
  --rpc-url $RPC_URL
```

## Project Structure

```
evm/
├── src/
│   └── StableSwapper.sol              # Core swap contract
├── script/
│   ├── DeployStableSwapper.s.sol      # Deployment script (UUPS proxy)
│   ├── VerifyDeployment.s.sol         # Post-deployment verification
│   └── GenerateStorageLocation.s.sol  # ERC-7201 storage slot generator
├── test/
│   ├── unit/                          # Unit tests by function
│   ├── integration/                   # Multi-token swap scenarios
│   └── lib/                           # Test base contracts and mocks
├── lib/                               # Dependencies (git submodules)
├── foundry.toml                       # Foundry configuration
└── remappings.txt                     # Solidity import remappings
```

## Dependencies

| Dependency | Purpose |
|---|---|
| [OpenZeppelin Contracts Upgradeable](https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable) | Access control, proxy patterns, ERC20 utilities |
| [forge-std](https://github.com/foundry-rs/forge-std) | Foundry testing and scripting standard library |
