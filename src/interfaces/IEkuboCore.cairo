use starknet::ContractAddress;
use ekubo::types::position::Position;
use ekubo::types::i129::{i129};

// Tick bounds for a position
#[derive(Copy, Drop, Serde, PartialEq, Hash, starknet::Store)]
pub struct Bounds {
    pub lower: i129,
    pub upper: i129
}

#[derive(Copy, Drop, Serde, PartialEq, Hash, starknet::Store)]
pub struct PoolKey {
    pub token0: ContractAddress,
    pub token1: ContractAddress,
    pub fee: u128,
    pub tick_spacing: u128,
    pub extension: ContractAddress,
}

#[derive(Copy, Drop, Serde, PartialEq, Hash)]
pub struct PositionKey {
    pub salt: u64,
    pub owner: ContractAddress,
    pub bounds: Bounds,
}

#[starknet::interface]
pub trait IEkuboCore<TContractState> {
    fn get_position(
        ref self: TContractState, pool_key: PoolKey, position_key: PositionKey
    ) -> Position;
}
