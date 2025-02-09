use starknet::{ClassHash, ContractAddress};

#[starknet::interface]
pub trait ICommon<TState> {
    fn upgrade(ref self: TState, new_class: ClassHash);
    fn pause(ref self: TState);
    fn unpause(ref self: TState);
    fn is_paused(self: @TState) -> bool;

    // ownable stuff
    fn owner(self: @TState) -> ContractAddress;
    fn transfer_ownership(ref self: TState, new_owner: ContractAddress);
    fn renounce_ownership(ref self: TState);
}
