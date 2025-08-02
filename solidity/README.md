# MVS Manager - Solidity Implementation

This directory contains the Solidity implementation of the MVS (Multi-Vault Strategy) Manager, which is an ERC4626 compatible vault that supports multiple sub-extensions.

## Overview

The MVSManager is designed to manage multiple investment strategies through modular extensions while maintaining ERC4626 compatibility for standardized vault operations.

### Key Features

- **ERC4626 Compatibility**: Full compliance with ERC4626 vault standard
- **Modular Extensions**: Support for up to 10 different strategy extensions
- **Configurable Rebalancing**: Admin-defined rebalance combinations with configurable steps
- **Total Assets Calculation**: Aggregates manager balance + extension assets
- **Role-based Access Control**: Admin and rebalancer roles for different operations
- **Emergency Controls**: Emergency withdrawal and pause functionality

## Architecture

### Core Contracts

1. **MVSManager.sol**: Main vault contract implementing ERC4626
2. **IMVSSubExtension.sol**: Interface for all strategy extensions
3. **LeverageVault.sol**: Example extension implementing leveraged strategies

### Key Components

#### MVSManager
- Inherits from OpenZeppelin's ERC4626, AccessControl, Pausable, and ReentrancyGuard
- Manages array of extensions and rebalance combinations
- Calculates total assets as: manager balance + sum of extension assets
- Provides configurable rebalance operations

#### IMVSSubExtension Interface
Required methods for all extensions:
- `totalAssets()`: Returns total assets managed by extension
- `asset()`: Returns underlying asset address
- `pushAssets()`: Receives assets from manager
- `pullAssets()`: Returns assets to manager
- `maxPush()/maxPull()`: Returns maximum operation amounts
- `emergencyWithdraw()`: Emergency asset recovery
- `extensionId()`: Returns extension identifier

#### Rebalance System
- **Rebalance Combinations**: Named collections of rebalance steps
- **Rebalance Steps**: Individual operations (push/pull) with specific parameters
- **Operation Types**: 
  - `0` = Push assets to extension
  - `1` = Pull assets from extension
- **Configurable Parameters**: Extension index, operation type, amount, and custom data

## Usage Examples

### 1. Deploy Manager
```solidity
MVSManager manager = new MVSManager(
    IERC20(assetToken),
    "My Vault Token",
    "MVT",
    adminAddress
);
```

### 2. Add Extension
```solidity
LeverageVault leverageVault = new LeverageVault(
    assetToken,
    address(manager),
    15000 // 1.5x leverage
);

manager.addExtension(leverageVault);
```

### 3. Create Rebalance Combination
```solidity
MVSManager.RebalanceStep[] memory steps = new MVSManager.RebalanceStep[](2);

// Push 50% to leverage vault
steps[0] = MVSManager.RebalanceStep({
    extensionIndex: 0,
    operation: 0, // push
    amount: 0, // 0 = use available balance
    data: abi.encode(20000) // 2x leverage
});

// Pull from another extension
steps[1] = MVSManager.RebalanceStep({
    extensionIndex: 1,
    operation: 1, // pull
    amount: 1000e18,
    data: ""
});

uint256 combinationId = manager.addRebalanceCombination("Rebalance to Leverage", steps);
```

### 4. Execute Rebalance
```solidity
manager.rebalance(combinationId);
```

## Security Features

### Access Control
- **ADMIN_ROLE**: Can add/remove extensions, create rebalance combinations, emergency actions
- **REBALANCER_ROLE**: Can execute rebalance operations
- **DEFAULT_ADMIN_ROLE**: Can manage roles

### Safety Mechanisms
- Reentrancy protection on all state-changing functions
- Pausable functionality for emergency stops
- Maximum extension limit (10)
- Extension validation (must use same asset)
- Step validation in rebalance combinations

### Emergency Controls
- `emergencyWithdrawExtension()`: Withdraw from specific extension
- `emergencyWithdrawAll()`: Withdraw from all extensions
- `pause()/unpause()`: Stop/resume vault operations

## Testing

The implementation includes comprehensive tests covering:
- Basic ERC4626 functionality
- Extension management
- Rebalance combination creation and execution
- Emergency scenarios
- Access control
- Edge cases and error conditions

Run tests with:
```bash
npx hardhat test
```

## Deployment Considerations

1. **Asset Compatibility**: All extensions must use the same underlying asset
2. **Gas Optimization**: Rebalance operations with many steps can be gas-intensive
3. **Extension Limits**: Maximum 10 extensions to prevent excessive gas usage
4. **Role Management**: Carefully manage admin and rebalancer roles
5. **Extension Security**: Thoroughly audit all extension contracts

## Integration with Existing Systems

This Solidity implementation maintains compatibility with:
- Standard ERC4626 vault interfaces
- OpenZeppelin access control patterns
- Common DeFi protocols and interfaces

The modular design allows for easy integration of new strategy types while maintaining a consistent interface for vault users.