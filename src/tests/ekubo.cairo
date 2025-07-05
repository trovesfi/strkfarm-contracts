use starknet::ContractAddress;
use starknet::contract_address::contract_address_const;

// Import existing interfaces and types
use strkfarm_contracts::interfaces::IEkuboCore::{
    Bounds, PoolKey, PositionKey, IEkuboCoreDispatcher, IEkuboCoreDispatcherTrait
};
use strkfarm_contracts::interfaces::IEkuboPosition::{
    GetTokenInfoResult, IEkuboDispatcher, IEkuboDispatcherTrait
};
use strkfarm_contracts::interfaces::IEkuboPositionsNFT::{
    IEkuboNFTDispatcher, IEkuboNFTDispatcherTrait
};

// Import Ekubo types
use ekubo::types::pool_price::PoolPrice;
use ekubo::types::position::Position;
use ekubo::types::i129::i129;

// Import ERC20 interface from OpenZeppelin
use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};

// Import constants
use strkfarm_contracts::helpers::constants::{
    EKUBO_CORE, EKUBO_ROUTER, EKUBO_POSITIONS, EKUBO_POSITIONS_NFT,
    ETH_ADDRESS, USDC_ADDRESS, STRK_ADDRESS, WST_ADDRESS
};

// Utility functions for Ekubo liquidity operations
pub mod ekubo_utils {
    use super::{
        ContractAddress, PoolKey, Bounds, PositionKey, IEkuboDispatcher, 
        IEkuboDispatcherTrait, IEkuboCoreDispatcher, IEkuboCoreDispatcherTrait,
        IEkuboNFTDispatcher, IEkuboNFTDispatcherTrait, IERC20Dispatcher, IERC20DispatcherTrait,
        Position, PoolPrice, EKUBO_CORE, EKUBO_POSITIONS, EKUBO_POSITIONS_NFT,
        ETH_ADDRESS, USDC_ADDRESS, STRK_ADDRESS, WST_ADDRESS, contract_address_const,
        i129
    };
    use starknet::{get_contract_address};
    use ekubo::interfaces::mathlib::{IMathLibDispatcherTrait, dispatcher as ekuboLibDispatcher};

    /// Transfer tokens to Ekubo positions contract for liquidity operations
    /// @param sender The address sending the tokens  
    /// @param token The token contract address
    /// @param amount The amount to transfer
    pub fn pay_ekubo(sender: ContractAddress, token: ContractAddress, amount: u256) {
        let this = get_contract_address();
        let positions_contract = EKUBO_POSITIONS();
        
        if (this == sender) {
            let token_dispatcher = IERC20Dispatcher { contract_address: token };
            token_dispatcher.transfer(positions_contract, amount);
        } else {
            let token_dispatcher = IERC20Dispatcher { contract_address: token };
            token_dispatcher.transfer_from(sender, positions_contract, amount);
        }
    }

    /// Deposit liquidity into Ekubo pool and return the liquidity amount added
    /// @param sender The address providing the tokens
    /// @param amount0 The amount of token0 to deposit
    /// @param amount1 The amount of token1 to deposit 
    /// @param receiver The address to receive any leftover tokens
    /// @param pool_key The pool identification
    /// @param bounds The tick bounds for the position
    /// @param nft_id The NFT ID for the position (0 to mint new)
    /// @return The amount of liquidity added
    pub fn deposit_liquidity(
        sender: ContractAddress,
        amount0: u256,
        amount1: u256,
        receiver: ContractAddress,
        pool_key: PoolKey,
        bounds: Bounds,
        nft_id: u64
    ) -> (u256, u64) {
        let positions_disp = IEkuboDispatcher { 
            contract_address: EKUBO_POSITIONS() 
        };
        
        // Transfer tokens to Ekubo positions contract
        pay_ekubo(sender, pool_key.token0, amount0);
        pay_ekubo(sender, pool_key.token1, amount1);

        // Get liquidity before deposit
        let position_key = PositionKey {
            salt: nft_id,
            owner: EKUBO_POSITIONS(),
            bounds: bounds
        };
        
        let core_disp = IEkuboCoreDispatcher { 
            contract_address: EKUBO_CORE() 
        };
        let liq_before_deposit = core_disp.get_position(pool_key, position_key).liquidity;

        let final_nft_id = if nft_id == 0 {
            // Mint new NFT and deposit
            let nft_disp = IEkuboNFTDispatcher {
                contract_address: EKUBO_POSITIONS_NFT()
            };
            let new_nft_id = nft_disp.get_next_token_id();
            positions_disp.mint_and_deposit(pool_key, bounds, 0);
            new_nft_id
        } else {
            // Deposit to existing position
            positions_disp.deposit(nft_id, pool_key, bounds, 0);
            nft_id
        };

        // Clear any unused tokens and send to receiver
        positions_disp.clear_minimum_to_recipient(pool_key.token0, 0, receiver);
        positions_disp.clear_minimum_to_recipient(pool_key.token1, 0, receiver);

        // Calculate liquidity added
        let position_key_final = PositionKey {
            salt: final_nft_id,
            owner: EKUBO_POSITIONS(),
            bounds: bounds
        };
        let liq_after_deposit = core_disp.get_position(pool_key, position_key_final).liquidity;
        let liquidity_added = (liq_after_deposit - liq_before_deposit).into();

        (liquidity_added, final_nft_id)
    }

    /// Withdraw liquidity from Ekubo pool
    /// @param nft_id The NFT ID for the position
    /// @param pool_key The pool identification
    /// @param bounds The tick bounds for the position
    /// @param liquidity The amount of liquidity to withdraw
    /// @param collect_fees Whether to collect fees during withdrawal
    /// @return (amount0, amount1) The amounts of tokens withdrawn
    pub fn withdraw_liquidity(
        nft_id: u64,
        pool_key: PoolKey,
        bounds: Bounds,
        liquidity: u256,
        collect_fees: bool
    ) -> (u128, u128) {
        let positions_disp = IEkuboDispatcher { 
            contract_address: EKUBO_POSITIONS() 
        };
        
        positions_disp.withdraw(
            nft_id,
            pool_key,
            bounds,
            liquidity.try_into().unwrap(),
            0,
            0,
            collect_fees
        )
    }

    /// Collect fees from an Ekubo position
    /// @param nft_id The NFT ID for the position
    /// @param pool_key The pool identification
    /// @param bounds The tick bounds for the position
    /// @return (fee0, fee1) The amounts of fees collected
    pub fn collect_fees(
        nft_id: u64,
        pool_key: PoolKey,
        bounds: Bounds
    ) -> (u128, u128) {
        let positions_disp = IEkuboDispatcher { 
            contract_address: EKUBO_POSITIONS() 
        };
        
        positions_disp.collect_fees(nft_id, pool_key, bounds)
    }

    /// Get current pool price
    /// @param pool_key The pool identification
    /// @return The current pool price
    pub fn get_pool_price(pool_key: PoolKey) -> PoolPrice {
        let positions_disp = IEkuboDispatcher { 
            contract_address: EKUBO_POSITIONS() 
        };
        
        positions_disp.get_pool_price(pool_key)
    }

    /// Get position information from Ekubo core
    /// @param nft_id The NFT ID for the position
    /// @param pool_key The pool identification
    /// @param bounds The tick bounds for the position
    /// @return The position data
    pub fn get_position(
        nft_id: u64,
        pool_key: PoolKey,
        bounds: Bounds
    ) -> Position {
        let position_key = PositionKey {
            salt: nft_id,
            owner: EKUBO_POSITIONS(),
            bounds: bounds
        };
        
        let core_disp = IEkuboCoreDispatcher { 
            contract_address: EKUBO_CORE() 
        };
        
        core_disp.get_position(pool_key, position_key)
    }


    pub fn max_liquidity(pool_key: PoolKey, lower_sqrt: u256, upper_sqrt: u256, amount0: u256, amount1: u256) -> u256 {
        let current_sqrt_price = get_pool_price(pool_key).sqrt_ratio;
        let liquidity = ekuboLibDispatcher()
            .max_liquidity(
                current_sqrt_price,
                lower_sqrt,
                upper_sqrt,
                amount0.try_into().unwrap(),
                amount1.try_into().unwrap()
            );
        return liquidity.into();
    }

    pub fn tick_to_sqrt_ratio(tick: i129) -> u256 {
        let sqrt_ratio = ekuboLibDispatcher().tick_to_sqrt_ratio(tick);
        return sqrt_ratio;
    }

    /// Create a standard ETH/USDC pool key for testing
    /// @param fee The fee tier for the pool
    /// @param tick_spacing The tick spacing for the pool
    /// @return PoolKey for ETH/USDC pool
    pub fn create_eth_usdc_pool_key(fee: u128, tick_spacing: u128) -> PoolKey {
        PoolKey {
            token0: ETH_ADDRESS(),
            token1: USDC_ADDRESS(),
            fee: fee,
            tick_spacing: tick_spacing,
            extension: contract_address_const::<0>(),
        }
    }

    /// Create a standard STRK/ETH pool key for testing
    /// @param fee The fee tier for the pool  
    /// @param tick_spacing The tick spacing for the pool
    /// @return PoolKey for STRK/ETH pool
    pub fn create_strk_eth_pool_key(fee: u128, tick_spacing: u128) -> PoolKey {
        PoolKey {
            token0: STRK_ADDRESS(),
            token1: ETH_ADDRESS(),
            fee: fee,
            tick_spacing: tick_spacing,
            extension: contract_address_const::<0>(),
        }
    }

    /// Create symmetric bounds around current tick for testing
    /// @param current_tick The current tick of the pool
    /// @param tick_range The range of ticks around current tick
    /// @param tick_spacing The tick spacing (bounds must be aligned)
    /// @return Bounds symmetric around current tick
    pub fn create_symmetric_bounds(current_tick: i129, tick_range: u128, tick_spacing: u128) -> Bounds {
        let range_i129 = i129 { mag: tick_range, sign: false };
        let spacing_i129 = i129 { mag: tick_spacing, sign: false };
        
        // Align bounds to tick spacing
        let lower_raw = current_tick - range_i129;
        let upper_raw = current_tick + range_i129;
        
        // Round to nearest tick spacing
        let lower_aligned = (lower_raw / spacing_i129) * spacing_i129;
        let upper_aligned = (upper_raw / spacing_i129) * spacing_i129;
        
        Bounds {
            lower: lower_aligned,
            upper: upper_aligned
        }
    }
}

#[cfg(test)]
pub mod test_ekubo_module {
    use super::ekubo_utils;
    use super::{PoolKey, Bounds, IERC20Dispatcher, IERC20DispatcherTrait};
    use super::{ETH_ADDRESS, USDC_ADDRESS, STRK_ADDRESS, i129};
    use starknet::{get_contract_address, contract_address_const};
    use snforge_std::{start_cheat_caller_address, stop_cheat_caller_address};
    use super::{EKUBO_CORE, EKUBO_POSITIONS, EKUBO_POSITIONS_NFT};
    use core::num::traits::Zero;

    #[test]
    fn test_create_pool_keys() {
        let eth_usdc_pool = ekubo_utils::create_eth_usdc_pool_key(3000, 60);
        assert(eth_usdc_pool.token0 == ETH_ADDRESS(), 'Wrong ETH address');
        assert(eth_usdc_pool.token1 == USDC_ADDRESS(), 'Wrong USDC address');
        assert(eth_usdc_pool.fee == 3000, 'Wrong fee');
        assert(eth_usdc_pool.tick_spacing == 60, 'Wrong tick spacing');

        let strk_eth_pool = ekubo_utils::create_strk_eth_pool_key(3000, 60);
        assert(strk_eth_pool.token0 == STRK_ADDRESS(), 'Wrong STRK address');
        assert(strk_eth_pool.token1 == ETH_ADDRESS(), 'Wrong ETH address');
    }

    #[test]
    fn test_create_symmetric_bounds() {
        let current_tick = i129 { mag: 1000, sign: false }; // Example current tick (positive 1000)
        let tick_range = 500_u128;
        let tick_spacing = 60_u128;
        
        let bounds = ekubo_utils::create_symmetric_bounds(current_tick, tick_range, tick_spacing);
        
        // Check bounds are within expected range and aligned to tick spacing
        assert(bounds.lower <= current_tick, 'Lower bound too high');
        assert(bounds.upper >= current_tick, 'Upper bound too low');
        
        // Check alignment to tick spacing  
        let spacing_i129 = i129 { mag: tick_spacing, sign: false };
        let zero_i129 = i129 { mag: 0, sign: false };
        assert(bounds.lower.mag % spacing_i129.mag == zero_i129.mag, 'Lower bound not aligned');
        assert(bounds.upper.mag % spacing_i129.mag == zero_i129.mag, 'Upper bound not aligned');
    }

    #[test]
    fn test_ekubo_constants() {
        // Test that all constants return valid contract addresses
        let core = EKUBO_CORE();
        let positions = EKUBO_POSITIONS();
        let nft = EKUBO_POSITIONS_NFT();
        
        // Basic sanity check - addresses should not be zero
        assert!(!core.is_zero(), "Core address is zero");
        assert!(!positions.is_zero(), "Positions address is zero");
        assert!(!nft.is_zero(), "NFT address is zero");
    }
}
