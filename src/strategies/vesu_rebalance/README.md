# Vesu Rebalance Strategy

## How It Works 🔄
The Vesu Rebalance Strategy automates yield optimization across multiple Vesu liquidity pools. Using ERC-4626 vault mechanics, it dynamically rebalances positions between different pools while auto-compounding fees and harvesting STRK rewards. Governance-set parameters control pool weights and fee structures, with strict precision checks ensuring capital efficiency within 0.01% tolerance.

## Core Operations ⚙️

### `deposit(assets)` 💰
- Converts ERC-20 assets to vault shares (ERC-4626 standard)
- Auto-collects protocol fees before new deposits
- Deposits to governance-set default Vesu pool

### `withdraw(shares)` 🏧
- Burns shares proportionally across all pools
- Withdraws from pools sequentially
- Transfers base asset directly to receiver

### `rebalance(actions)` 🔄
- Collects outstanding protocol fees (0.3% basis)
- Executes batch actions across Vesu pools:
   - `DEPOSIT`: Allocate to target pools
   - `WITHDRAW`: Deallocate from underperforming pools
- Validates post-rebalance yield improvement
- Enforces governance-set max weight per pool
- Requires Relayer role authorization

### `harvest(claim, swapInfo)` 🌾
- Claims STRK rewards from Vesu distributor
- Swaps 100% to base asset via Avnu routes
- Redeposits harvested assets into default pool
- Distributes rewards through share mechanism
- Charges protocol fee on harvested amount

### `rebalance_weights(actions)` ⚖️
- Reallocates assets between approved pools
- Maintains total assets while adjusting weights
- Requires Relayer authorization
- Collects protocol fees pre-execution
- Enforces governance-set pool caps

## Emergency Operations 🚨

### `emergency_withdraw()` 🆘
- Withdraws all liquidity from all pools
- Requires Emergency Actor role
- Preserves asset balances

### `emergency_withdraw_pool(pool_index)` ⚠️
- Force-withdraws from specific pool
- Requires Emergency Actor role
- Handles frozen pool edge cases (allows to skip such pools)
- Preserves remaining allocations

## Security Architecture 🛡️

### Access Control
| Role              | Privileges                          | Critical Functions                  |
|-------------------|-------------------------------------|--------------------------------------|
| **Governor**      | Update protocol settings<br>Modify allowed pools<br>Toggle incentive systems | `set_settings()`<br>`set_allowed_pools()`<br>`set_incentives_off()` |
| **Relayer**       | Execute position rebalancing<br>Adjust pool weight allocations | `rebalance()`<br>`rebalance_weights()` |
| **Emergency Actor** | Emergency liquidity extraction<br>Frozen pool recovery | `emergency_withdraw()`<br>`emergency_withdraw_pool()` |
| **Super admin**   | Upgrade contract implementation | `upgrade()` |

**Privilege Details**  
- Governor: Full protocol configuration control  
- Relayer: Operational execution with yield validation  
- Emergency Actor: Bypass normal constraints for capital preservation
- Super admin: Contract upgrade authorization