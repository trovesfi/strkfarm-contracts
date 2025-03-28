# STRKFarm Contracts

## Overview

STRKFarm is a decentralized yield aggregator built on Starknet, designed to maximize returns for users by automatically reallocating assets across various DeFi protocols. Leveraging Starknet's scalability and low transaction costs, STRKFarm offers efficient yield farming opportunities through automated vaults and strategies. Users can deposit their assets into STRKFarm's vaults, which then optimize and manage the yield farming process to earn passive income. The platform emphasizes transparency, security, and user-friendly interfaces to enhance the DeFi experience.

## Strategies

STRKFarm employs various strategies to generate passive income for its users. Two notable strategies include:

### Ekubo Concentrated Liquidity Vault

An automated concentrated liquidity management protocol for the Ekubo AMM, this vault combines dynamic position management with fee auto-compounding and STRK reward harvesting. It allows users to deposit token pairs into optimized liquidity positions on Ekubo, automatically reinvesting earned fees and handling complex operations like reward harvesting. Governance-controlled rebalancing maintains optimal price bounds, while role-based security restricts critical operations. The system tracks positions via NFT ownership and enforces strict precision checks for capital efficiency.

For more detailed information, please refer to the [Ekubo Concentrated Liquidity Vault README](https://github.com/strkfarm/strkfarm-contracts/blob/ariyan/strat_readme/src/strategies/cl_vault/README.md).

### Vesu Rebalance Strategy

This strategy automates yield optimization across multiple Vesu liquidity pools. Utilizing ERC-4626 vault mechanics, it dynamically rebalances positions between different pools while auto-compounding fees and harvesting STRK rewards. Governance-set parameters control pool weights and fee structures, with strict precision checks ensuring capital efficiency within a 0.01% tolerance.

For more detailed information, please refer to the [Vesu Rebalance Strategy README](https://github.com/strkfarm/strkfarm-contracts/blob/ariyan/strat_readme/src/strategies/vesu_rebalance/README.md).

By implementing these strategies, STRKFarm aims to provide users with the best possible yield farming opportunities, fostering growth and innovation within the DeFi ecosystem.