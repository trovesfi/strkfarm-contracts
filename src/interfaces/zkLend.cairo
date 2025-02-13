use starknet::{ContractAddress};

#[derive(Drop, Serde, starknet::Store)]
pub struct MarketReserveData {
    pub enabled: bool,
    pub decimals: u8,
    pub z_token_address: ContractAddress,
    pub interest_rate_model: ContractAddress,
    pub collateral_factor: felt252,
    pub borrow_factor: felt252,
    pub reserve_factor: felt252,
    pub last_update_timestamp: felt252,
    pub lending_accumulator: felt252,
    pub debt_accumulator: felt252,
    pub current_lending_rate: felt252,
    pub current_borrowing_rate: felt252,
    pub raw_total_debt: felt252,
    pub flash_loan_fee: felt252,
    pub liquidation_bonus: felt252,
    pub debt_limit: felt252
}

#[starknet::interface]
pub trait IZkLendMarket<TContractState> {
    fn deposit(ref self: TContractState, token: ContractAddress, amount: felt252);
    fn withdraw(ref self: TContractState, token: ContractAddress, amount: felt252);
    fn enable_collateral(ref self: TContractState, token: ContractAddress);
    fn is_collateral_enabled(
        self: @TContractState, user: ContractAddress, token: ContractAddress
    ) -> bool;
    fn borrow(ref self: TContractState, token: ContractAddress, amount: felt252);
    fn repay(ref self: TContractState, token: ContractAddress, amount: felt252);
    fn get_reserve_data(self: @TContractState, token: ContractAddress) -> MarketReserveData;
    fn get_user_debt_for_token(
        self: @TContractState, user: ContractAddress, token: ContractAddress
    ) -> felt252;
    fn flash_loan(
        ref self: TContractState,
        receiver: ContractAddress,
        token: ContractAddress,
        amount: felt252,
        calldata: Span<felt252>
    );
}

#[starknet::interface]
pub trait IZToken<TContractState> {
    fn underlying_token(self: @TContractState) -> ContractAddress;
}
