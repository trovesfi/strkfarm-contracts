use starknet::{ContractAddress, get_contract_address, get_caller_address};
use strkfarm_contracts::interfaces::lendcomp::{
    ILendMod, BorrowData, MMTokenTrait, max_borrow_amount, mm_health_factor
};
use core::num::traits::Zero;
use strkfarm_contracts::interfaces::zkLend::{
    IZkLendMarket, IZkLendMarketDispatcher, IZkLendMarketDispatcherTrait
};
use strkfarm_contracts::interfaces::zkLend::MarketReserveData;
use strkfarm_contracts::interfaces::oracle::{
    IPriceOracle, IPriceOracleDispatcher, IPriceOracleDispatcherTrait, PriceWithUpdateTime
};
use strkfarm_contracts::helpers::safe_decimal_math;
use strkfarm_contracts::helpers::ERC20Helper;

#[derive(Drop, Copy, Serde, starknet::Store)]
pub struct zkLendStruct {
    pub zkLendRouter: IZkLendMarketDispatcher,
    pub oracle: IPriceOracleDispatcher,
}

#[derive(Drop, Serde, Copy)]
pub struct ZklendToken {
    pub underlying_asset: ContractAddress,
}

pub impl zkLendSettingsImpl of ILendMod<zkLendStruct, ZklendToken> {
    fn deposit(self: zkLendStruct, token: ContractAddress, amount: u256,) -> u256 {
        let dispatcher = self.zkLendRouter;
        let zkLendRouter = dispatcher.contract_address;
        ERC20Helper::approve(token, zkLendRouter, amount);

        // deposit amount
        // let felt_amount: felt252 = amount.try_into().unwrap();
        //// println!("Depositing feltamount: {:?}", felt_amount);
        dispatcher.deposit(token, amount.try_into().unwrap());
        // enable collateral if not already active
        let this: ContractAddress = get_contract_address();
        let is_collateral_enabled: bool = dispatcher.is_collateral_enabled(this, token);
        if (!is_collateral_enabled) {
            IZkLendMarketDispatcher { contract_address: zkLendRouter }.enable_collateral(token);
        }
        amount
    }

    fn withdraw(self: zkLendStruct, token: ContractAddress, amount: u256) -> u256 {
        // withdraw amount
        self.zkLendRouter.withdraw(token, amount.try_into().unwrap());
        amount
    }

    fn borrow(self: zkLendStruct, token: ContractAddress, amount: u256) -> u256 {
        // borrow amount
        self.zkLendRouter.borrow(token, amount.try_into().unwrap());
        amount
    }

    fn repay(self: zkLendStruct, token: ContractAddress, amount: u256) -> u256 {
        // repay amount
        let dispatcher: IZkLendMarketDispatcher = self.zkLendRouter;
        ERC20Helper::approve(token, dispatcher.contract_address, amount);
        self.zkLendRouter.repay(token, amount.try_into().unwrap());
        amount
    }

    // returns hf in basis points
    fn health_factor(
        self: @zkLendStruct,
        user: ContractAddress,
        deposits: Array<ZklendToken>,
        borrows: Array<ZklendToken>,
    ) -> u32 {
        mm_health_factor(self, user, deposits, borrows)
    }

    fn assert_valid(self: @zkLendStruct) {
        assert(self.zkLendRouter.contract_address.is_non_zero(), 'zkLend::router::zero');
        assert(self.oracle.contract_address.is_non_zero(), 'zkLend::oracle::zero');
    }

    fn max_borrow_amount(
        self: @zkLendStruct,
        deposit_token: ZklendToken,
        deposit_amount: u256,
        borrow_token: ZklendToken,
        min_hf: u32
    ) -> u256 {
        max_borrow_amount(self, deposit_token, deposit_amount, borrow_token, min_hf)
    }

    fn min_borrow_required(self: @zkLendStruct, token: ContractAddress,) -> u256 {
        return 0;
    }

    fn get_repay_amount(self: @zkLendStruct, token: ContractAddress, amount: u256) -> u256 {
        return amount;
    }

    fn deposit_amount(self: @zkLendStruct, asset: ContractAddress, user: ContractAddress) -> u256 {
        let reserve_data = (*self.zkLendRouter).get_reserve_data(asset);
        ERC20Helper::balanceOf(reserve_data.z_token_address, user)
    }

    fn borrow_amount(self: @zkLendStruct, asset: ContractAddress, user: ContractAddress) -> u256 {
        self._zkLend_get_debt(user, asset).into()
    }
}

pub impl zkLendMMTokenImpl of MMTokenTrait<ZklendToken, zkLendStruct> {
    fn collateral_value(self: @ZklendToken, state: zkLendStruct, user: ContractAddress) -> u256 {
        let token = *self.underlying_asset;
        let reserve_data = state.zkLendRouter.get_reserve_data(token);
        let bal = ERC20Helper::balanceOf(reserve_data.z_token_address, user);
        state._calculate_collateral_value(*self, reserve_data, bal)
    }

    fn required_value(self: @ZklendToken, state: zkLendStruct, user: ContractAddress) -> u256 {
        let token = *self.underlying_asset;
        let dispatcher = state.zkLendRouter;
        let reserve_data = dispatcher.get_reserve_data(token);
        let price = state.oracle.get_price(token);
        let debt = state._zkLend_get_debt(user, token);
        let debt_usd = safe_decimal_math::mul_decimals(
            price.into(), debt.into(), reserve_data.decimals
        );
        safe_decimal_math::div(debt_usd, reserve_data.borrow_factor.into())
    }

    fn calculate_collateral_value(self: @ZklendToken, state: zkLendStruct, amount: u256) -> u256 {
        state
            ._calculate_collateral_value(
                *self, state.zkLendRouter.get_reserve_data(*self.underlying_asset), amount
            )
    }

    fn price(self: @ZklendToken, state: zkLendStruct) -> (u256, u8) {
        let token = *self.underlying_asset;
        let price = state.oracle.get_price(token);
        (price.into(), 8)
    }

    fn underlying_asset(self: @ZklendToken, state: zkLendStruct) -> ContractAddress {
        *self.underlying_asset
    }

    fn get_borrow_data(self: @ZklendToken, state: zkLendStruct) -> BorrowData {
        let token = *self.underlying_asset;
        let dispatcher = state.zkLendRouter;
        let reserve_data = dispatcher.get_reserve_data(token);
        BorrowData { token, borrow_factor: reserve_data.borrow_factor.into(), }
    }
}

#[generate_trait]
impl InternalImpl of InternalTrait {
    fn _zkLend_get_debt(
        self: @zkLendStruct, user: ContractAddress, token: ContractAddress
    ) -> felt252 {
        (*self.zkLendRouter).get_user_debt_for_token(user, token)
    }

    fn _calculate_collateral_value(
        self: zkLendStruct, tokenInfo: ZklendToken, reserve_data: MarketReserveData, amount: u256
    ) -> u256 {
        let token = tokenInfo.underlying_asset;
        let price: u256 = self.oracle.get_price(token).into();
        let bal_usd = safe_decimal_math::mul_decimals(price, amount.into(), reserve_data.decimals);
        safe_decimal_math::mul(bal_usd, reserve_data.collateral_factor.into())
    }
}


#[cfg(test)]
mod tests {
    use starknet::{
        ContractAddress, get_contract_address, get_block_timestamp,
        contract_address::contract_address_const
    };
    use core::num::traits::Zero;
    use strkfarm_contracts::components::zkLend::{zkLendStruct, ZklendToken, zkLendSettingsImpl};
    use strkfarm_contracts::helpers::constants;
    use snforge_std::{
        declare, ContractClassTrait, start_cheat_caller_address, stop_cheat_caller_address,
        start_cheat_block_timestamp, stop_cheat_block_timestamp_global, mock_call,
    };
    use strkfarm_contracts::helpers::ERC20Helper;
    use strkfarm_contracts::interfaces::zkLend::{
        IZkLendMarket, IZkLendMarketDispatcher, IZkLendMarketDispatcherTrait
    };
    use strkfarm_contracts::interfaces::oracle::{
        IPriceOracle, IPriceOracleDispatcher, IPriceOracleDispatcherTrait, PriceWithUpdateTime
    };
    // use snforge_std::{spy_events, SpyOn, EventSpy, EventFetcher,
//     event_name_hash, Event};

    // #[test]
// #[fork("mainnet_usdc_large")]
// fn test_zklend_component() {
//     let settings = zkLendStruct {
//         zkLendRouter: IZkLendMarketDispatcher {
//             contract_address: constants::ZKLEND_MARKET()
//         },
//         oracle: IPriceOracleDispatcher {
//             contract_address: constants::Oracle()
//         }
//     };
//     let this = get_contract_address();

    //     // mock price timestamp
//     cheat_utils::mock_pragma();

    //     let user = constants::TestUserUSDCLarge();
//     let amount: u256 = 100000000;

    //     start_cheat_caller_address(constants::USDC_ADDRESS(), user);
//     ERC20Helper::transfer(constants::USDC_ADDRESS(), this, amount);
//     stop_cheat_caller_address(constants::USDC_ADDRESS());

    //     let mut spy = spy_events(SpyOn::One(constants::ZKLEND_MARKET()));

    //     let pre_deposit_amount = settings.deposit_amount(constants::USDC_ADDRESS(), this);
//     settings.deposit(constants::USDC_ADDRESS(), amount);
//     let post_deposit_amount = settings.deposit_amount(constants::USDC_ADDRESS(), this);

    //     //// println!("Pre deposit amount: {:?}", pre_deposit_amount);
//     //// println!("Post deposit amount: {:?}", post_deposit_amount);

    //     spy.fetch_events();
//     assert(spy.events.len() >= 1, 'There should be atleast event');
//     //// println!("Events len: {:?}", spy.events.len());
//     let mut count = 0;
//     let mut foundEvent = false;
//     loop {
//         let (_from, event) = spy.events.at(count);
//         //// println!("Event name: {:?}", event.keys.at(0));
//         if (event.keys.at(0) == @event_name_hash('AccumulatorsSync')) {
//             foundEvent = true;
//             //// println!("Found, accumulator: {}", *event.data.at(1));
//         }
//         if (event.keys.at(0) == @event_name_hash('Deposit')) {
//             foundEvent = true;
//             //// println!("Found, deposit: {}", *event.data.at(2));
//         }
//         count += 1;
//         if (count >= spy.events.len()) {
//             break;
//         }
//     };

    //     assert(foundEvent, 'zkLend::deposit::event fail');

    //     let now = get_block_timestamp();
//    start_cheat_block_timestamp_global(now);

    //     let mut spy = spy_events(SpyOn::One(constants::ZKLEND_MARKET()));

    //     let net_amount = settings.deposit_amount(constants::USDC_ADDRESS(), this);
//     //// println!("Net deposit post update {:?}", net_amount);

    //     // withdraw
//     settings.withdraw(constants::USDC_ADDRESS(), amount / 2);
//     let post_withdraw_amount = settings.deposit_amount(constants::USDC_ADDRESS(), this);
//     //// println!("Post withdraw amount: {:?}", post_withdraw_amount);

    //     spy.fetch_events();
//     assert(spy.events.len() >= 1, 'There should be atleast event');
//     //// println!("Events len: {:?}", spy.events.len());
//     let mut count = 0;
//     let mut foundEvent = false;
//     loop {
//         let (_from, event) = spy.events.at(count);
//         //// println!("Event name: {:?}", event.keys.at(0));
//         if (event.keys.at(0) == @event_name_hash('AccumulatorsSync')) {
//             foundEvent = true;
//             //// println!("Found, accumulator: {}", *event.data.at(1));
//         }
//         if (event.keys.at(0) == @event_name_hash('Withdraw')) {
//             foundEvent = true;
//             //// println!("Found, withdraw: {}", *event.data.at(2));
//         }
//         count += 1;
//         if (count >= spy.events.len()) {
//             break;
//         }
//     };

    //     assert(post_withdraw_amount == amount / 2, 'zkLend::withdraw::amount');
//     stop_cheat_block_timestamp_global();
// }
}
