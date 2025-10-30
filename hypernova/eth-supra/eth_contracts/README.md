# Ethereum Smart Contracts

This directory contains the Ethereum smart contracts for the SupraNova project, built using the Foundry framework.

## Project Structure

```
eth_contracts/
├── contracts/                # Smart contract source files
│   ├── fee-operator/        # Fee operator contracts
│   │   └── implementations/ # Implementation contracts
│   ├── hypernova-core/      # Core Hypernova functionality
│   │   └── implementations/ # Implementation contracts
│   ├── interfaces/          # Shared interfaces
│   ├── token-vault/         # Token vault contracts
│   │   └── implementations/ # Implementation contracts
│   └── tokenBridge-service/ # Token bridge service contracts
│       └── implementations/ # Implementation contracts
├── foundry.toml
├── lib/                     # Dependencies
├── README.md
├── script/                  # Deployment and interaction scripts
│   ├── forge-scripts/      # Main deployment scripts
│   │   └── bash/           # Bash deployment helpers
│   └── test_scripts/       # Test deployment scripts
└── test/                   # Test files
    ├── fuzz/              # Fuzz tests
    ├── mock/              # Mock contracts for testing
    └── unit/              # Unit tests
```

## Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- Node.js and npm
- An Ethereum wallet with testnet/mainnet funds for deployment

## Setup

1. Install dependencies:
```bash
forge install
```

2. Copy the `.env.example` to `.env` and fill in your configuration:
```bash
cp .env.example .env
```

## Building

To compile the contracts:
```bash
forge build
```

## Testing

### Local Tests
Run the test suite without forking:
```bash
forge test
```

### Fuzz Tests
Run fuzz tests with specific iterations:
```bash
forge test --match-path "test/fuzz/*" -vv
```

### Fork Tests
Run tests against forked networks:

1. Ethereum Mainnet:
```bash
forge test --fork-url $ETH_MAINNET_RPC_URL  -vv
```

2. Sepolia Testnet:
```bash
forge test --fork-url $SEPOLIA_RPC_URL -vv
```

### Coverage Testing

Due to stack depth limitations in some contracts, coverage testing requires the `--ir-minimum` flag:

```bash
forge coverage --no-match-coverage "script" --ir-minimum  
```

This flag enables minimal IR optimization while maintaining accurate coverage reporting. The coverage report will show:
- Line coverage
- Statement coverage
- Branch coverage
- Function coverage

Current coverage metrics:
- Overall line coverage: ~82%
- Overall statement coverage: ~83%
- Overall branch coverage: ~73%
- Overall function coverage: ~90%

## Deployment

The contracts should be deployed in the following sequence:
1. Hypernova Core
2. Fee Operator
3. Token Bridge

For each component, you need to:

1. Create and configure your `.env` file:
```bash
cp .env.example .env
```

2. Modify the constants in the respective deployment scripts (`script/forge-scripts/`):

### Hypernova Core Deployment
In `DeployAndSetupHN.s.sol`:
- `ADMIN`: Address of the admin/multisig wallet

Deploy using either:
```bash
# Using forge script
forge script script/forge-scripts/DeployAndSetupHN.s.sol --rpc-url <RPC_URL> --broadcast

# Or using the bash script
./script/forge-scripts/bash/deployAndSetupHN.sh
```

### Fee Operator Deployment
In `DeployAndSetupFO.s.sol`:
- `ADMIN`: Address of the admin/multisig wallet
- `HYPERNOVA_CORE`: Address of the deployed Hypernova Core contract
- `S_VALUE_FEED`: Address of the Supra S-Value Feed contract
- `SUPRA_USDT_PAIR_INDEX`: Pair index for USDT price feed (default: 500)

Deploy using either:
```bash
# Using forge script
forge script script/forge-scripts/DeployAndSetupFO.s.sol --rpc-url <RPC_URL> --broadcast

# Or using the bash script
./script/forge-scripts/bash/deployAndSetupFO.sh
```

### Token Bridge Deployment
In `DeployAndSetupTB.s.sol`:
- `HYPERNOVA_CORE`: Address of the deployed Hypernova Core contract
- `FEE_OPERATOR`: Address of the deployed Fee Operator contract
- `ADMIN`: Address of the admin/multisig wallet
- `WETH9`: Address of the WETH9 contract on the target network
- `DELAY`: Time delay for admin operations (default: 1 hour)

Deploy using either:
```bash
# Using forge script
forge script script/forge-scripts/DeployAndSetupTB.s.sol --rpc-url <RPC_URL> --broadcast

# Or using the bash script
./script/forge-scripts/bash/deployAndSetupTB.sh
```

Note: Each deployment script includes post-deployment setup functions that should be called by the admin after deployment:

#### Hypernova Core
- `adminHNSetup`: Configures chain-specific parameters and fees

#### Fee Operator
- `adminFOSetup`: Configures fee parameters for different chains

#### Token Bridge
- `adminVaultSetup`: Sets token limits for the vault
- `adminTBSetup`: Registers chains and tokens in the bridge

## Contract Components

### Hypernova Core
The Hypernova Core is the central component of the cross-chain messaging protocol. It provides:
- Cross-chain message posting functionality through `postMessage`
- Message verification fee management
- Chain support management
- Message event emission for tracking cross-chain communications
- Initialization and admin controls


### Fee Operator
The Fee Operator component manages:
- Cross-chain fee calculations
- Relayer reward computations
- Service fee management
- Tier-based fee structures
- Fee configuration per chain


### Token Vault
The Token Vault is a secure storage component that:
- Manages token deposits and withdrawals
- Handles token locking and unlocking for cross-chain transfers
- Maintains token balances for bridge operations
- Ensures secure token custody during cross-chain transfers
- Implements admin withdrawal controls
- Manages token limits and restrictions

### Token Bridge Service
The Token Bridge Service enables:
- Cross-chain token transfers
- Native token (ETH) transfers
- Token registration and management
- Chain registration and support
- Fee management and calculation
- Service state management
- Implementation upgrades

## Dependencies

- OpenZeppelin Contracts (managed through Foundry)
- Uniswap V3 Core (for price feed integration)
