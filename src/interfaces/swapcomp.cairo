use strkfarm_contracts::components::swap::{AvnuMultiRouteSwap, Route};

//   All params of Route may not be required all the time,
//   but using it anyway for simplicity and generality.

// @dev
// Specify token_to_amount if u want exact amount out of the swap

pub trait ISwapMod<TSettings> {
    fn swap(self: TSettings, swap_params: AvnuMultiRouteSwap,) -> u256;

    fn get_amounts_in(self: TSettings, amount_out: u256, path: Array<Route>,) -> Array<u256>;

    fn get_amounts_out(self: TSettings, amount_in: u256, path: Array<Route>,) -> Array<u256>;

    fn assert_valid(self: TSettings);
}
