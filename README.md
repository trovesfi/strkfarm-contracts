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


## Vesu Rebalance Strategy

### How It Works 🔄
The Vesu Rebalance Strategy automates yield optimization across multiple Vesu liquidity pools. Using ERC-4626 vault mechanics, it dynamically rebalances positions between different pools while auto-compounding fees and harvesting STRK rewards. Governance-set parameters control pool weights and fee structures, with strict precision checks ensuring capital efficiency within 0.01% tolerance.

## Core Operations ⚙️

### `deposit(assets)` 💰
- Converts ERC-20 assets to vault shares (ERC-4626 standard)
- Auto-collects protocol fees before new deposits
- Deposits to governance-set default Vesu pool
- Mints shares 1:1 with contributed liquidity
- Enforces maximum pool weight constraints

### `withdraw(shares)` 🏧
- Burns shares proportionally across all pools
- Withdraws from highest-liquidity pools first
- Transfers base asset directly to receiver
- Executes emergency withdrawal if pools are frozen
- Verifies 100% balance utilization (0.01% tolerance)

### `rebalance(actions)` 🔄
1. Collects outstanding protocol fees (0.3% basis)
2. Executes batch actions across Vesu pools:
   - `DEPOSIT`: Allocate to target pools
   - `WITHDRAW`: Deallocate from underperforming pools
3. Validates post-rebalance yield improvement
4. Enforces governance-set max weight per pool
5. Requires Relayer role authorization

### `harvest(claim, swapInfo)` 🌾
1. Claims STRK rewards from Vesu distributor
2. Swaps 100% to base asset via Avnu routes
3. Redeposits harvested assets into default pool
4. Distributes rewards through share mechanism
5. Charges protocol fee on harvested amount

### `rebalance_weights(actions)` ⚖️
- Reallocates assets between approved pools
- Maintains total assets while adjusting weights
- Requires Relayer authorization
- Collects protocol fees pre-execution
- Enforces governance-set pool caps

## Emergency Operations 🚨

### `emergency_withdraw()` 🆘
1. Withdraws all liquidity from all pools
2. Bypasses normal weight constraints
3. Requires Emergency Actor role
4. Executes even with frozen pools
5. Preserves asset balances

### `emergency_withdraw_pool(pool_index)` ⚠️
- Force-withdraws from specific pool
- Ignores utilization checks
- Requires Emergency Actor role
- Handles frozen pool edge cases
- Preserves remaining allocations

## Security Architecture 🛡️

### Access Control
| Role              | Privileges                          | Critical Functions                  |
|-------------------|-------------------------------------|--------------------------------------|
| **Governor**      | Update protocol settings<br>Modify allowed pools<br>Toggle incentive systems | `set_settings()`<br>`set_allowed_pools()`<br>`set_incentives_off()` |
| **Relayer**       | Execute position rebalancing<br>Adjust pool weight allocations | `rebalance()`<br>`rebalance_weights()` |
| **Emergency Actor** | Emergency liquidity extraction<br>Frozen pool recovery | `emergency_withdraw()`<br>`emergency_withdraw_pool()` |

**Privilege Details**  
- Governor: Full protocol configuration control  
- Relayer: Operational execution with yield validation  
- Emergency Actor: Bypass normal constraints for capital preservation  
