# Vesu Rebalance Strategy

## How It Works 🔄
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
