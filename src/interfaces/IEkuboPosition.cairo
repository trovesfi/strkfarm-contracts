use starknet::{ContractAddress};
use strkfarm_contracts::interfaces::IEkuboCore::{Bounds, PoolKey};
use ekubo::types::pool_price::PoolPrice;

#[derive(Copy, Drop, Serde, PartialEq)]
pub struct GetTokenInfoResult {
    pub pool_price: PoolPrice,
    pub liquidity: u128,
    pub amount0: u128,
    pub amount1: u128,
    pub fees0: u128,
    pub fees1: u128,
}

#[starknet::interface]
pub trait IEkubo<TContractState> {
    fn mint_and_deposit(
        ref self: TContractState, pool_key: PoolKey, bounds: Bounds, min_liquidity: u128
    );
    fn deposit(
        ref self: TContractState, id: u64, pool_key: PoolKey, bounds: Bounds, min_liquidity: u128
    ) -> u128;
    fn withdraw(
        ref self: TContractState,
        id: u64,
        pool_key: PoolKey,
        bounds: Bounds,
        liquidity: u128,
        min_token: u128,
        min_token1: u128,
        collect_fees: bool
    ) -> (u128, u128);
    fn collect_fees(
        ref self: TContractState, id: u64, pool_key: PoolKey, bounds: Bounds
    ) -> (u128, u128);
    fn get_pool_price(ref self: TContractState, pool_key: PoolKey) -> PoolPrice;
    fn get_token_info(
        self: @TContractState, id: u64, pool_key: PoolKey, bounds: Bounds
    ) -> GetTokenInfoResult;
    fn clear(ref self: TContractState, token: ContractAddress) -> u256;
    fn clear_minimum_to_recipient(
        ref self: TContractState, token: ContractAddress, minimum: u256, recipient: ContractAddress
    ) -> u256;
}
