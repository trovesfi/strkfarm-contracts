use starknet::{ContractAddress, ClassHash};
use strkfarm_contracts::interfaces::IEkuboDistributor::{Claim};
use strkfarm_contracts::components::swap::{AvnuMultiRouteSwap};
use strkfarm_contracts::components::zkLend::zkLendStruct;

#[derive(Drop, Copy, Serde, starknet::Event, starknet::Store)]
pub struct Settings {
    pub rewardsContract: ContractAddress, // distribution contract
    pub lendClassHash: ClassHash, // our lending lib contract classhash
    pub swapClassHash: ClassHash, // our swap lib contract classhash
}

#[derive(Drop, Copy, Serde, starknet::Event, starknet::Store)]
pub struct Harvest {
    pub asset: ContractAddress, // e.g. STRk
    pub amount: u256,
    pub timestamp: u64
}

#[starknet::interface]
pub trait IStrategy<TContractState> {
    fn harvest(
        ref self: TContractState, claim: Claim, proof: Span<felt252>, swapInfo: AvnuMultiRouteSwap
    );
    fn set_settings(ref self: TContractState, settings: Settings, lend_settings: zkLendStruct);

    fn upgrade(ref self: TContractState, class_hash: ClassHash);

    //
    // view functions
    //

    fn get_settings(self: @TContractState) -> Settings;
}
