use strkfarm_contracts::helpers::ERC20Helper;
use starknet::{ContractAddress, get_contract_address, get_caller_address};
use strkfarm_contracts::unaudited::IFlashloan::{IFlash, IVesuDispatcher, IVesuDispatcherTrait, IVesuCallback};

// @dev call this function to take flash loan
// Your contract must implement IFlash interface which handles the flash loan utility
pub fn init_vesu_flashloan<
  TState, 
  impl TIFlash: IFlash<TState>, 
  impl TIVesuCallback: IVesuCallback<TState>, 
  impl TDrop: Drop<TState>
>(
  ref self: TState,
  vesu: IVesuDispatcher,
  token: ContractAddress,
  flash_amount: u128,
  calldata: Span<felt252>
) -> Span<felt252> {
  // init the flash loan
  vesu.flash_loan(get_contract_address(), token, flash_amount.into(), false, calldata);
  let arr: Array<felt252> = array![];
  return arr.span();

  // vesu internally will call on_flash_loan function of the contract which implements IVesuCallback
}

// @dev ensure caller is verified to be vesu in use_flash_loan implementation
pub fn on_vesu_flash_loan<
  TState, 
  impl TIFlash: IFlash<TState>, 
  impl TDrop: Drop<TState>
>(
  ref self: TState,
  sender: ContractAddress,
  asset: ContractAddress,
  amount: u256,
  data: Span<felt252>
) {
  // do stuff with the flash loan
  IFlash::use_flash_loan(ref self, asset, amount.try_into().unwrap(), data);
  
  let caller = get_caller_address();
  
  // repay flash loan
  let bal = ERC20Helper::balanceOf(asset, get_contract_address());
  ERC20Helper::approve(asset, caller, amount);
}