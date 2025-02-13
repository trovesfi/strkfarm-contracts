use starknet::{ContractAddress};
use strkfarm_contracts::interfaces::IEkuboCore::{Bounds, PoolKey, PositionKey};
use ekubo::types::position::Position;
use strkfarm_contracts::components::swap::{AvnuMultiRouteSwap};
use strkfarm_contracts::interfaces::IEkuboDistributor::Claim;

#[derive(Drop, Copy, Serde, starknet::Store)]
pub struct ClSettings { // @audit seems like a duplicate of self.asset() (ERC4626)
  pub ekubo_positions_contract: ContractAddress,
  pub bounds_settings: Bounds,
  pub pool_key: PoolKey,
  pub ekubo_positions_nft: ContractAddress,
  pub contract_nft_id: u64, // NFT position id of Ekubo position
  pub ekubo_core: ContractAddress,
  pub oracle: ContractAddress,
  pub fee_settings: FeeSettings,
}

#[derive(Drop, Copy, Serde)]
pub struct MyPosition {
  pub liquidity: u256,
  pub amount0: u256,
  pub amount1: u256,
}

#[derive(Drop, Copy, Serde, starknet::Store, starknet::Event)]
pub struct FeeSettings {
  pub fee_bps: u256,
  pub fee_collector: ContractAddress
}

#[starknet::interface]
pub trait IClVault<TContractState> {
  // returns shares
  fn deposit(ref self: TContractState, amount0: u256, amount1: u256, receiver: ContractAddress) -> u256;
  fn withdraw(ref self: TContractState, shares: u256, receiver: ContractAddress) -> MyPosition;
  fn convert_to_shares(self: @TContractState, amount0: u256, amount1: u256) -> u256;
  fn convert_to_assets(self: @TContractState, shares: u256) -> MyPosition;
  fn total_liquidity(self: @TContractState) -> u256;
  fn get_position_key(self: @TContractState) -> PositionKey;
  fn get_position(self: @TContractState) -> Position;
  fn handle_fees(ref self: TContractState);
  fn harvest(ref self: TContractState, rewardsContract: ContractAddress, claim: Claim, proof: Span<felt252>, swapInfo: AvnuMultiRouteSwap);
  fn get_settings(self: @TContractState) -> ClSettings; // @audit should be get_settings (follow snake_case)
  fn rebalance(ref self: TContractState, new_bounds: Bounds, swap_params: AvnuMultiRouteSwap);
  fn handle_unused(ref self: TContractState, swap_params: AvnuMultiRouteSwap);
  fn set_settings(ref self: TContractState, fee_settings: FeeSettings);
}
