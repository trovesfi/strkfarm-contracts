use starknet::ContractAddress;

#[starknet::interface]
pub trait IEkuboNFT<TContractState> {
    fn get_next_token_id(ref self: TContractState) -> u64;
    fn ownerOf(self: @TContractState, token_id: u256) -> ContractAddress;
    fn balanceOf(self: @TContractState, account: ContractAddress) -> u256;
}
