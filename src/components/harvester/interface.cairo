use starknet::{ContractAddress};
use strkfarm_contracts::interfaces::IEkuboDistributor::{Claim};

#[derive(Drop, Copy, Serde)]
pub struct ClaimResult {
    pub token: ContractAddress, // reward token
    pub amount: u256,
}

/// Implementing below implement on a struct
/// will allow to have custom harvesting methods depending
/// on the contract used by 3rd party dapps to distribute rewards
pub trait IClaimTrait<TStruct> {
    fn claim_with_proofs(self: @TStruct, claim: Claim, proof: Span<felt252>) -> ClaimResult;
}
