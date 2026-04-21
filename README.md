# StableSwapper

A 1:1 stablecoin swap contract with decimal normalization, fee collection, and role-based access control.

## Overview

StableSwapper enables swapping between stablecoins at a 1:1 ratio, automatically handling decimal differences between tokens. It is designed for protocols that need to offer stablecoin liquidity with configurable fees, token allowlisting, and granular operational controls.

### Features

- **1:1 Stablecoin Swaps** -- Swap between any listed stablecoins with automatic decimal normalization
- **Fee Collection** -- Configurable fee in basis points, charged on the input token
- **Role-Based Access Control** -- Distinct roles with separated concerns for administration, treasury, configuration, and pausing
- **Feature Flags** -- Independent toggles for swaps, withdrawals, and allowlist enforcement
- **Reserved Amounts** -- Reserve token balances from being consumed by swaps
- **Slippage Protection** -- Users specify a minimum output amount per swap

## Implementations

| Chain | Directory | Details |
|---|---|---|
| EVM | [`evm/`](evm/) | Solidity, UUPS upgradeable proxy, OpenZeppelin |
| SVM | [`solana/`](solana/) | Rust / Anchor 0.31, single centralized liquidity pool |

See each implementation's README for chain-specific quickstart, build, test, and deployment instructions.

## Repository Structure

```
stable-swapper/
├── evm/                       # EVM (Solidity) implementation
│   ├── src/                   # Production contracts
│   ├── script/                # Deployment and utility scripts
│   ├── test/                  # Unit and integration tests
│   └── README.md
├── solana/                    # SVM (Rust / Anchor) implementation
│   ├── programs/              # On-chain Anchor program
│   ├── tests/                 # Anchor / Mocha integration tests
│   ├── scripts/               # Admin, whitelist, and emergency scripts
│   ├── runbooks/              # Deployment runbooks
│   └── README.md
├── LICENSE
├── SECURITY.md
├── CONTRIBUTING.md
└── .github/
    └── PULL_REQUEST_TEMPLATE.md
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for development setup, coding standards, and the pull request workflow.

## Security

See [SECURITY.md](SECURITY.md) for our security policy and how to report vulnerabilities.

## License

This project is licensed under the Apache 2.0 License. See [LICENSE](LICENSE) for details.
