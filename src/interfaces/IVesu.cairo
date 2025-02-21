use starknet::{ContractAddress};
use alexandria_math::i257::i257;

#[derive(PartialEq, Copy, Drop, Serde, Default)]
pub enum AmountType {
    #[default]
    Delta,
    Target,
}

#[derive(PartialEq, Copy, Drop, Serde, Default)]
pub enum AmountDenomination {
    #[default]
    Native,
    Assets,
}

#[derive(PartialEq, Copy, Drop, Serde, Default)]
pub struct Amount {
    pub amount_type: AmountType,
    pub denomination: AmountDenomination,
    pub value: i257,
}

#[derive(PartialEq, Copy, Drop, Serde)]
pub struct ModifyPositionParams {
    pub pool_id: felt252,
    pub collateral_asset: ContractAddress,
    pub debt_asset: ContractAddress,
    pub user: ContractAddress,
    pub collateral: Amount,
    pub debt: Amount,
    pub data: Span<felt252>
}

#[derive(PartialEq, Copy, Drop, Serde)]
pub struct UpdatePositionResponse {
    collateral_delta: i257, // [asset scale]
    collateral_shares_delta: i257, // [SCALE]
    debt_delta: i257, // [asset scale]
    nominal_debt_delta: i257, // [SCALE]
    bad_debt: u256, // [asset scale]
}

#[derive(PartialEq, Copy, Drop, Serde, starknet::Store)]
pub struct LTVConfig {
    pub max_ltv: u64, // [SCALE]
}

#[derive(PartialEq, Copy, Drop, Serde, Default)]
struct AssetPrice {
    pub value: u256,
    pub is_valid: bool,
}

#[derive(PartialEq, Copy, Drop, Serde)]
pub struct AssetConfig { //                                     | slot | packed | notes
    //                                                      | ---- | ------ | -----
    pub total_collateral_shares: u256, //       [SCALE]         | 1    | u128   |
    pub total_nominal_debt: u256, //            [SCALE]         | 1    | u123   |
    pub reserve: u256, //                       [asset scale]   | 2    | u128   |
    pub max_utilization: u256, //               [SCALE]         | 2    | u8     | constant percentage
    pub floor: u256, //                         [SCALE]         | 2    | u8     | constant decimals
    pub scale: u256, //                         [SCALE]         | 2    | u8     | constant decimals 
    pub is_legacy: bool, //                                     | 2    | u8     | constant
    pub last_updated: u64, //                   [seconds]       | 3    | u32    |
    pub last_rate_accumulator: u256, //         [SCALE]         | 3    | u64    |
    pub last_full_utilization_rate: u256, //    [SCALE]         | 3    | u64    |
    pub fee_rate: u256, //                      [SCALE]         | 3    | u8     | percentage
}

#[derive(PartialEq, Copy, Drop, Serde, starknet::Store)]
pub struct Position {
    pub collateral_shares: u256, // packed as u128 [SCALE] 
    pub nominal_debt: u256, // packed as u123 [SCALE]
}

pub trait IVesu<T> {
    fn getParams(self: T) -> ModifyPositionParams;
}

#[starknet::interface]
pub trait ISton<TContractState> {
    fn modify_position(
        ref self: TContractState, params: ModifyPositionParams
    ) -> UpdatePositionResponse;
    fn check_collateralization(
        ref self: TContractState,
        pool_id: felt252,
        collateral_asset: ContractAddress,
        debt_asset: ContractAddress,
        user: ContractAddress
    ) -> (bool, u256, u256);
    fn ltv_config(
        self: @TContractState,
        pool_id: felt252,
        collateral_asset: ContractAddress,
        debt_asset: ContractAddress
    ) -> LTVConfig;
    fn asset_config(
        ref self: TContractState, pool_id: felt252, asset: ContractAddress
    ) -> (AssetConfig, u256);
    fn asset_config_unsafe(
        self: @TContractState, pool_id: felt252, asset: ContractAddress
    ) -> (AssetConfig, u256);
    fn position(
        ref self: TContractState,
        pool_id: felt252,
        collateral_asset: ContractAddress,
        debt_asset: ContractAddress,
        user: ContractAddress
    ) -> (Position, u256, u256);
    fn extension(self: @TContractState, pool_id: felt252) -> ContractAddress;
    fn utilization(self: @TContractState, pool_id: felt252, asset: ContractAddress) -> u256;
}

#[starknet::interface]
pub trait IVesuExtension<TContractState> {
    fn singleton(self: @TContractState) -> ContractAddress;
    fn price(self: @TContractState, pool_id: felt252, asset: ContractAddress) -> AssetPrice;
    fn interest_rate(
        self: @TContractState,
        pool_id: felt252,
        asset: ContractAddress,
        utilization: u256,
        last_updated: u64,
        last_full_utilization_rate: u256,
    ) -> u256;
}
