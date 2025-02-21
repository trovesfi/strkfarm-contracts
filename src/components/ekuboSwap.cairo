use starknet::{ContractAddress};
use strkfarm_contracts::interfaces::swapcomp::{ISwapMod,};
use core::num::traits::Zero;
use strkfarm_contracts::helpers::ERC20Helper;
use strkfarm_contracts::components::swap::{AvnuMultiRouteSwap, Route};
use ekubo::interfaces::core::{ICoreDispatcher};
use ekubo::types::keys::{PoolKey};
use ekubo::types::i129::{i129};
use ekubo::components::clear::{IClearDispatcher, IClearDispatcherTrait};
use ekubo::interfaces::erc20::IERC20Dispatcher;
use ekubo::interfaces::router::{RouteNode, TokenAmount};
use ekubo::types::delta::{Delta};

#[starknet::interface]
pub trait IRouter<TState> {
    fn multihop_swap(
        ref self: TState, nodes: Array<RouteNode>, token_amount: TokenAmount,
    ) -> Array<Delta>;

    fn quote_multihop_swap(
        self: @TState, nodes: Array<RouteNode>, token_amount: TokenAmount,
    ) -> Array<Delta>;
}

#[derive(Drop, Copy, Serde, starknet::Store)]
pub struct EkuboSwapStruct {
    pub core: ICoreDispatcher,
    pub router: IRouterDispatcher
}

pub fn get_nodes(routes: Array<Route>, core: ICoreDispatcher) -> Array<RouteNode> {
    let n_routes = routes.len();
    assert(n_routes > 0, 'EkuboSwap: no routes');

    let mut nodes: Array<RouteNode> = array![];
    let n_routes = routes.len();
    let mut i = 0;

    loop {
        let route = routes.at(i);

        // just to ensure other routes aren't passed by mistake
        assert(*route.exchange_address == core.contract_address, 'EkuboSwap: invalid route [2]');

        let additional_swap_params = route.additional_swap_params;
        let pool_key = PoolKey {
            token0: (*additional_swap_params[0]).try_into().unwrap(),
            token1: (*additional_swap_params[1]).try_into().unwrap(),
            fee: (*additional_swap_params[2]).try_into().unwrap(),
            tick_spacing: (*additional_swap_params[3]).try_into().unwrap(),
            extension: (*additional_swap_params[4]).try_into().unwrap(),
        };
        let node = RouteNode {
            pool_key: pool_key,
            sqrt_ratio_limit: (*additional_swap_params[5]).try_into().unwrap(),
            skip_ahead: 100,
        };
        nodes.append(node);
        i += 1;
        if i >= n_routes {
            break;
        }
    };

    return nodes;
}

pub fn get_token_amount(from_token: ContractAddress, from_amount: u256) -> TokenAmount {
    TokenAmount {
        token: from_token, amount: i129 { mag: from_amount.try_into().unwrap(), sign: false, }
    }
}

pub fn process_swap_params(
    routes: Array<Route>,
    core: ICoreDispatcher,
    from_token: ContractAddress,
    to_token: ContractAddress,
    from_amount: u256,
    to_amount: u256,
) -> (Array<RouteNode>, TokenAmount,) {
    let n_routes = routes.len();
    assert(n_routes > 0, 'EkuboSwap: no routes');

    // assert atleast one of token0 and token1 is from token from route 0
    let token0: ContractAddress = (*routes.at(0).additional_swap_params[0]).try_into().unwrap();
    let token1: ContractAddress = (*routes.at(0).additional_swap_params[1]).try_into().unwrap();
    assert(token0 == from_token || token1 == from_token, 'EkuboSwap: invalid route [0]');

    // assert token_to_address is from token from route n_routes - 1
    let last_token0: ContractAddress = (*routes.at(n_routes - 1).additional_swap_params[0])
        .try_into()
        .unwrap();
    let last_token1: ContractAddress = (*routes.at(n_routes - 1).additional_swap_params[1])
        .try_into()
        .unwrap();
    assert(last_token0 == to_token || last_token1 == to_token, 'EkuboSwap: invalid route [1]');

    let mut nodes = get_nodes(routes, core);

    let token_amount = if (to_amount == 0) {
        get_token_amount(from_token, from_amount)
    } else {
        let mut output = get_token_amount(to_token, to_amount);
        output.amount.sign = true;
        output
    };

    return (nodes, token_amount);
}

pub fn perform_ekubo_swap(
    router: IRouterDispatcher,
    nodes: Array<RouteNode>,
    from_token: ContractAddress,
    to_token: ContractAddress,
    from_amount: u256,
    token_amount: TokenAmount, // could be both input and output token amount depending on the exact swap
    min_amount_out: u256,
) -> u256 {
    // execute swap
    ERC20Helper::strict_transfer(from_token, router.contract_address, from_amount);
    router.multihop_swap(nodes, token_amount);

    // withdraw remaining tokens
    let clearDisp = IClearDispatcher { contract_address: router.contract_address, };
    let to_token_out = clearDisp.clear(IERC20Dispatcher { contract_address: to_token });
    assert(min_amount_out == 0 || to_token_out >= min_amount_out, 'EkuboSwap: min amount out err');

    let from_token_out = if (token_amount
        .amount
        .sign) { // if true, we are trying to get exact output token amount
        // input token may be left out to meet required output token amount;
        // so transfer it back to the contract
        clearDisp.clear(IERC20Dispatcher { contract_address: from_token })
    } else {
        0
    };
    let from_token_used = from_amount - from_token_out;
    assert(from_token_used > 0, 'EkuboSwap: from token used');

    return to_token_out;
}

pub impl ekuboSwapImpl of ISwapMod<EkuboSwapStruct> {
    fn swap(self: EkuboSwapStruct, swap_params: AvnuMultiRouteSwap) -> u256 {
        let from_token = swap_params.token_from_address;
        let from_amount = swap_params.token_from_amount;
        let to_token = swap_params.token_to_address;
        let min_amount_out = swap_params.token_to_min_amount;
        let (nodes, token_amount) = process_swap_params(
            swap_params.routes,
            self.core,
            from_token,
            to_token,
            from_amount,
            swap_params.token_to_amount
        );

        perform_ekubo_swap(
            self.router, nodes, from_token, to_token, from_amount, token_amount, min_amount_out
        )
    }

    fn get_amounts_in(self: EkuboSwapStruct, amount_out: u256, path: Array<Route>,) -> Array<u256> {
        if (false) {
            core::panic_with_felt252('EkuboSwap: not implemented');
        }
        return array![];
    }

    fn get_amounts_out(self: EkuboSwapStruct, amount_in: u256, path: Array<Route>,) -> Array<u256> {
        if (false) {
            core::panic_with_felt252('EkuboSwap: not implemented');
        }
        return array![];
    }

    fn assert_valid(self: EkuboSwapStruct) {
        assert(self.core.contract_address.is_non_zero(), 'EkuboSwap: core zero');
        assert(self.router.contract_address.is_non_zero(), 'EkuboSwap: router zero');
    }
}

#[cfg(test)]
mod tests {
    use starknet::{get_contract_address};
    use strkfarm_contracts::components::swap::{AvnuMultiRouteSwap, Route};
    use strkfarm_contracts::interfaces::swapcomp::{ISwapMod,};
    use strkfarm_contracts::helpers::constants;
    use super::{EkuboSwapStruct, ekuboSwapImpl,};
    use ekubo::interfaces::core::{ICoreDispatcher};
    use super::{IRouterDispatcher};
    use snforge_std::{start_cheat_caller_address, stop_cheat_caller_address};
    use strkfarm_contracts::helpers::ERC20Helper;

    fn getEkuboStruct() -> EkuboSwapStruct {
        EkuboSwapStruct {
            core: ICoreDispatcher { contract_address: constants::EKUBO_CORE(), },
            router: IRouterDispatcher { contract_address: constants::EKUBO_ROUTER(), }
        }
    }

    fn getUSDCUSDTRoute() -> Route {
        Route {
            token_from: constants::USDC_ADDRESS(),
            token_to: constants::USDT_ADDRESS(),
            exchange_address: constants::EKUBO_CORE(),
            percent: 0,
            additional_swap_params: array![
                constants::USDC_ADDRESS().into(), // token0
                constants::USDT_ADDRESS().into(), // token1
                6805647338418769825990228293189632, // fee
                20, // tick space
                0, // extension
                0, // sqrt limit
            ]
        }
    }

    fn load_usdc() {
        start_cheat_caller_address(constants::USDC_ADDRESS(), constants::TestUserUSDCLarge());
        ERC20Helper::transfer(constants::USDC_ADDRESS(), get_contract_address(), 100_000_000);
        stop_cheat_caller_address(constants::USDC_ADDRESS());
    }

    #[test]
    #[fork("mainnet_usdc_large")]
    fn test_ekubo_swap_simple() {
        load_usdc();
        let ekuboStruct = getEkuboStruct();
        let route1 = getUSDCUSDTRoute();

        let swap_params = AvnuMultiRouteSwap {
            token_from_address: constants::USDC_ADDRESS(),
            token_from_amount: 100_000_000, // 100 USDC
            token_to_address: constants::USDT_ADDRESS(),
            token_to_amount: 0,
            token_to_min_amount: 0,
            beneficiary: get_contract_address(),
            integrator_fee_amount_bps: 0,
            integrator_fee_recipient: get_contract_address(),
            routes: array![route1.clone()],
        };

        let amount_out = ekuboStruct.swap(swap_params);
        let balance_this_after = ERC20Helper::balanceOf(
            constants::USDT_ADDRESS(), get_contract_address()
        );
        assert(balance_this_after == 100038039, 'EkuboSwap: balance_this_after');
        assert(balance_this_after == amount_out, 'EkuboSwap: balance_this [2]');

        let balance_this_usdc_after = ERC20Helper::balanceOf(
            constants::USDC_ADDRESS(), get_contract_address()
        );
        assert(balance_this_usdc_after == 0, 'EkuboSwap: balance_this_usdc');
    }

    #[test]
    #[fork("mainnet_usdc_large")]
    fn test_ekubo_swap_exact_out() {
        load_usdc();
        let ekuboStruct = getEkuboStruct();
        let route1 = getUSDCUSDTRoute();

        let swap_params = AvnuMultiRouteSwap {
            token_from_address: constants::USDC_ADDRESS(),
            token_from_amount: 100_000_000, // 100 USDC, some possible amount we can use, should be >= required to get to amount
            token_to_address: constants::USDT_ADDRESS(),
            token_to_amount: 100_000_000, // 100 USDT required exact amount
            token_to_min_amount: 0,
            beneficiary: get_contract_address(),
            integrator_fee_amount_bps: 0,
            integrator_fee_recipient: get_contract_address(),
            routes: array![route1.clone()],
        };

        let amount_out = ekuboStruct.swap(swap_params);
        let balance_this_after = ERC20Helper::balanceOf(
            constants::USDT_ADDRESS(), get_contract_address()
        );
        assert(balance_this_after == 100000000, 'EkuboSwap: balance_this_after');
        assert(balance_this_after == amount_out, 'EkuboSwap: balance_this [2]');

        let balance_this_usdc_after = ERC20Helper::balanceOf(
            constants::USDC_ADDRESS(), get_contract_address()
        );
        assert(balance_this_usdc_after == 38026, 'EkuboSwap: balance_this_usdc');
    }

    #[test]
    #[fork("mainnet_usdc_large")]
    fn test_ekubo_multihop_ekubo_swap() {
        load_usdc();
        let ekuboStruct = getEkuboStruct();

        let route1 = Route {
            token_from: constants::ETH_ADDRESS(),
            token_to: constants::USDC_ADDRESS(),
            exchange_address: constants::EKUBO_CORE(),
            percent: 0,
            additional_swap_params: array![
                constants::ETH_ADDRESS().into(), // token0
                constants::USDC_ADDRESS().into(), // token1
                170141183460469235273462165868118016, // fee
                1000, // tick space
                0, // extension
                0, // sqrt limit
            ]
        };

        let route2 = Route {
            token_from: constants::STRK_ADDRESS(),
            token_to: constants::ETH_ADDRESS(),
            exchange_address: constants::EKUBO_CORE(),
            percent: 0,
            additional_swap_params: array![
                constants::STRK_ADDRESS().into(), // token0
                constants::ETH_ADDRESS().into(), // token1
                34028236692093847977029636859101184, // fee
                200, // tick space
                0, // extension
                0, // sqrt limit
            ]
        };

        let swap_params = AvnuMultiRouteSwap {
            token_from_address: constants::USDC_ADDRESS(),
            token_from_amount: 100_000_000, // 100 USDC
            token_to_address: constants::STRK_ADDRESS(),
            token_to_amount: 0,
            token_to_min_amount: 0,
            beneficiary: get_contract_address(),
            integrator_fee_amount_bps: 0,
            integrator_fee_recipient: get_contract_address(),
            routes: array![route1, route2],
        };

        let _ = ekuboStruct.swap(swap_params);
        let balance_this_after = ERC20Helper::balanceOf(
            constants::STRK_ADDRESS(), get_contract_address()
        );
        assert(balance_this_after == 99652955612364830652, 'EkuboSwap: balance_this_after');

        let balance_this_usdc_after = ERC20Helper::balanceOf(
            constants::USDC_ADDRESS(), get_contract_address()
        );
        assert(balance_this_usdc_after == 0, 'EkuboSwap: balance_this_usdc');
    }

    #[test]
    #[fork("mainnet_usdc_large")]
    #[should_panic(expected: ('EkuboSwap: min amount out err',))]
    fn test_ekubo_swap_slippage_check() {
        load_usdc();
        let ekuboStruct = getEkuboStruct();
        let route1 = getUSDCUSDTRoute();

        let swap_params = AvnuMultiRouteSwap {
            token_from_address: constants::USDC_ADDRESS(),
            token_from_amount: 100_000_000, // 100 USDC
            token_to_address: constants::USDT_ADDRESS(),
            token_to_amount: 0,
            token_to_min_amount: 102_000_000, // 102 USDT
            beneficiary: get_contract_address(),
            integrator_fee_amount_bps: 0,
            integrator_fee_recipient: get_contract_address(),
            routes: array![route1],
        };

        ekuboStruct.swap(swap_params);
    }

    #[test]
    #[fork("mainnet_usdc_large")]
    #[should_panic(expected: ('EkuboSwap: no routes',))]
    fn test_ekubo_no_routes_err() {
        load_usdc();
        let ekuboStruct = getEkuboStruct();

        let swap_params = AvnuMultiRouteSwap {
            token_from_address: constants::USDC_ADDRESS(),
            token_from_amount: 100_000_000, // 100 USDC
            token_to_address: constants::USDT_ADDRESS(),
            token_to_amount: 0,
            token_to_min_amount: 0,
            beneficiary: get_contract_address(),
            integrator_fee_amount_bps: 0,
            integrator_fee_recipient: get_contract_address(),
            routes: array![],
        };

        ekuboStruct.swap(swap_params);
    }

    #[test]
    #[fork("mainnet_usdc_large")]
    #[should_panic(expected: ('EkuboSwap: invalid route [0]',))]
    fn test_ekubo_invalid_from_address() {
        load_usdc();
        let ekuboStruct = getEkuboStruct();
        let mut route1 = Route {
            token_from: constants::USDT_ADDRESS(),
            token_to: constants::USDT_ADDRESS(),
            exchange_address: constants::EKUBO_CORE(),
            percent: 0,
            additional_swap_params: array![
                constants::USDT_ADDRESS().into(), // token0
                constants::USDT_ADDRESS().into(), // token1
                6805647338418769825990228293189632, // fee
                20, // tick space
                0, // extension
                0, // sqrt limit
            ]
        };

        let swap_params = AvnuMultiRouteSwap {
            token_from_address: constants::USDC_ADDRESS(),
            token_from_amount: 100_000_000, // 100 USDC
            token_to_address: constants::USDC_ADDRESS(),
            token_to_amount: 0,
            token_to_min_amount: 0,
            beneficiary: get_contract_address(),
            integrator_fee_amount_bps: 0,
            integrator_fee_recipient: get_contract_address(),
            routes: array![route1],
        };

        ekuboStruct.swap(swap_params);
    }

    #[test]
    #[fork("mainnet_usdc_large")]
    #[should_panic(expected: ('EkuboSwap: invalid route [1]',))]
    fn test_ekubo_invalid_to_address() {
        load_usdc();
        let ekuboStruct = getEkuboStruct();
        let mut route1 = Route {
            token_from: constants::USDC_ADDRESS(),
            token_to: constants::USDC_ADDRESS(),
            exchange_address: constants::EKUBO_CORE(),
            percent: 0,
            additional_swap_params: array![
                constants::USDC_ADDRESS().into(), // token0
                constants::USDC_ADDRESS().into(), // token1
                6805647338418769825990228293189632, // fee
                20, // tick space
                0, // extension
                0, // sqrt limit
            ]
        };

        let swap_params = AvnuMultiRouteSwap {
            token_from_address: constants::USDC_ADDRESS(),
            token_from_amount: 100_000_000, // 100 USDC
            token_to_address: constants::USDT_ADDRESS(),
            token_to_amount: 0,
            token_to_min_amount: 0,
            beneficiary: get_contract_address(),
            integrator_fee_amount_bps: 0,
            integrator_fee_recipient: get_contract_address(),
            routes: array![route1],
        };

        ekuboStruct.swap(swap_params);
    }
}
