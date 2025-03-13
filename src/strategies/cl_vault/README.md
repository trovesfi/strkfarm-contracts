# Ekubo Concentrated Liquidity Vault

Automated concentrated liquidity management protocol for Ekubo AMM, combining dynamic position management with fee auto-compounding and STRK reward harvesting.

## How It Works
The vault lets users deposit token pairs into optimized liquidity positions on Ekubo. Using similar mechanics as ERC-4626 token issuance, it automatically reinvests earned fees back into the position and handles complex operations like reward harvesting. Governance-controlled rebalancing maintains optimal price bounds while role-based security restricts critical operations. The system tracks positions via NFT ownership and enforces strict precision checks for capital efficiency.

## Core Operations
To define convention, total assets is the total liquidity held by the vault. Total supply is erc20 tokens minted by the vault.
Everytime when earned fee are added to liquidity or strk rewards harvested to add liquidity, it increases the total liquidity (i.e. total assets)  
to increase the erc20 (share) value.

### `deposit(amount0, amount1)` 💰
- Given two precisely accurate amounts, deposits them into Ekubo Pool
- Auto-collects any previous earned fees before deposit. 
- Mints ERC-20 shares proportional to liquidity created

### `withdraw(shares)` 🏧
- Burns shares and redeems proportional liquidity
- Withdraws tokens from Ekubo position
- Transfers assets directly to receiver
- Updates NFT state if position empties

### `rebalance(new_bounds, swap_params)` 🔄  
(Permissioned function)  
1. Withdraws all liquidity from current position
2. Updates price bounds 
3. Swaps available assets to match asset requirements as per new bounds
4. Deposits optimized liquidity with new bounds
5. Enforces ≤0.01% balance tolerance

### `handle_fees`
1. Collects fees
2. Uses the fees earned to create as much liquidity as possible
3. Remaining assets stay in vault un-unused.
4. `handle_unused` function can be called anytime by an off-chain service, to adjust assets and use all free balance to add liquidity


### Access Control
| Role         | Privileges                          | Methods                   |
|--------------|-------------------------------------|--------------------------|
| **Governor** | Update settings | `set_settings()`<br>`set_incentives_off()` |
| **Emergency Actor** | Pause/unpause | `pause()`<br>`unpause()` |
| **Relayer**  | Execute rebalances                  | `rebalance()`            |
| **Super admin**  | Upgrade                  | `upgrade()`            |
