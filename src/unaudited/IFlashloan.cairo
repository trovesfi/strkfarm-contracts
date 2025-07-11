use starknet::ContractAddress;

// generic interface for flash loans
pub trait IFlash<TState> {
  fn use_flash_loan(
      ref self: TState, token: ContractAddress, flash_amount: u128, calldata: Span<felt252>
  );
}

// Vesu flash loan callback
#[starknet::interface]
pub trait IVesuCallback<TContractState> {
    // Flash loan callback
    fn on_flash_loan(
        ref self: TContractState,
        sender: ContractAddress,
        asset: ContractAddress,
        amount: u256,
        data: Span<felt252>
    );
}

// Function to call a flash loan on vesu
#[starknet::interface]
pub trait IVesu<TContractState> {
    fn flash_loan(
        ref self: TContractState,
        receiver: ContractAddress,
        asset: ContractAddress,
        amount: u256,
        is_legacy: bool,
        data: Span<felt252>
    );
}