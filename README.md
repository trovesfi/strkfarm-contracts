# STRKFarm Contracts

## Ekubo Concentrated Liquidity Vault

Automated concentrated liquidity management protocol for Ekubo AMM, combining dynamic position management with fee auto-compounding and STRK reward harvesting.

### How It Works
The vault lets users deposit token pairs into optimized liquidity positions on Ekubo. Using ERC-4626 share mechanics, it automatically reinvests earned fees back into the position and handles complex operations like reward harvesting. Governance-controlled rebalancing maintains optimal price bounds while role-based security restricts critical operations. The system tracks positions via NFT ownership and enforces strict precision checks for capital efficiency.

## Core Operations

### `deposit(amount0, amount1)` 💰
- Converts token amounts to liquidity shares
- Auto-collects existing fees before deposit
- Verifies liquidity matches expected value
- Mints ERC-20 shares proportional to contribution

### `withdraw(shares)` 🏧
- Burns shares and redeems proportional liquidity
- Withdraws tokens from Ekubo position
- Transfers assets directly to receiver
- Updates NFT state if position empties

### `rebalance(new_bounds, swap_params)` 🔄
1. Withdraws all liquidity from current position
2. Updates price bounds via governance-approved ticks
3. Swaps residual tokens using Avnu router
4. Deposits optimized liquidity with new bounds
5. Enforces ≤0.01% balance tolerance

## Security Architecture 🛡️

### Access Control
| Role         | Privileges                          | Methods                   |
|--------------|-------------------------------------|--------------------------|
| **Governor** | Update fee parameters<br>Emergency stop | `set_settings()`<br>`set_incentives_off()` |
| **Relayer**  | Execute rebalances                  | `rebalance()`            |

### Protections
- **Reentrancy Guards**: All user-facing functions
- **Input Validation**:
  ```cairo
  assert(amount0 > 0 || amount1 > 0, 'No zero deposits')
  assert(shares ≤ balance_of(caller), 'Over-withdraw')