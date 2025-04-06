#[starknet::contract]
mod VesuRebalance {
    use starknet::{ContractAddress, get_contract_address, get_block_number};
    use starknet::contract_address::{contract_address_const};
    use strkfarm_contracts::helpers::ERC20Helper;
    use strkfarm_contracts::components::common::CommonComp;
    use strkfarm_contracts::components::vesu::{vesuStruct, vesuSettingsImpl};
    use strkfarm_contracts::interfaces::IVesu::{
        IStonDispatcherTrait, IVesuExtensionDispatcher, IVesuExtensionDispatcherTrait
    };
    use strkfarm_contracts::components::harvester::reward_shares::{
        RewardShareComponent, IRewardShare
    };
    use strkfarm_contracts::components::harvester::reward_shares::RewardShareComponent::{
        InternalTrait as RewardShareInternalImpl
    };
    use strkfarm_contracts::components::harvester::harvester_lib::HarvestBeforeHookResult;
    use strkfarm_contracts::interfaces::IERC4626::{
        IERC4626, IERC4626Dispatcher, IERC4626DispatcherTrait
    };
    use openzeppelin::security::pausable::{PausableComponent};
    use openzeppelin::upgrades::upgradeable::UpgradeableComponent;
    use openzeppelin::security::reentrancyguard::{ReentrancyGuardComponent};
    use openzeppelin::introspection::src5::SRC5Component;
    use openzeppelin::token::erc20::{ERC20Component,};
    use openzeppelin::token::erc20::interface::IERC20Mixin;
    use strkfarm_contracts::components::erc4626::{ERC4626Component};
    use alexandria_storage::list::{List, ListTrait};
    use strkfarm_contracts::interfaces::IEkuboDistributor::{Claim};
    use strkfarm_contracts::components::swap::{AvnuMultiRouteSwap};
    use strkfarm_contracts::components::harvester::defi_spring_default_style::{
        SNFStyleClaimSettings, ClaimImpl as DefaultClaimImpl
    };
    use strkfarm_contracts::components::harvester::harvester_lib::{
        HarvestConfig, HarvestConfigImpl, HarvestHooksTrait, HarvestEvent
    };
    use strkfarm_contracts::interfaces::oracle::{IPriceOracleDispatcher};
    use core::num::traits::Zero;

    component!(path: ERC4626Component, storage: erc4626, event: ERC4626Event);
    component!(path: RewardShareComponent, storage: reward_share, event: RewardShareEvent);
    component!(path: ERC20Component, storage: erc20, event: ERC20Event);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);
    component!(path: ReentrancyGuardComponent, storage: reng, event: ReentrancyGuardEvent);
    component!(path: UpgradeableComponent, storage: upgradeable, event: UpgradeableEvent);
    component!(path: PausableComponent, storage: pausable, event: PausableEvent);
    component!(path: CommonComp, storage: common, event: CommonCompEvent);

    #[abi(embed_v0)]
    impl CommonCompImpl = CommonComp::CommonImpl<ContractState>;

    #[abi(embed_v0)]
    impl RewardShareImpl = RewardShareComponent::RewardShareImpl<ContractState>;
    impl RSInternalImpl = RewardShareComponent::InternalImpl<ContractState>;
    impl RSPrivateImpl = RewardShareComponent::PrivateImpl<ContractState>;

    impl CommonInternalImpl = CommonComp::InternalImpl<ContractState>;
    impl ERC4626InternalImpl = ERC4626Component::InternalImpl<ContractState>;
    impl ERC4626MetadataImpl = ERC4626Component::ERC4626MetadataImpl<ContractState>;
    impl ERC20InternalImpl = ERC20Component::InternalImpl<ContractState>;
    impl ReentrancyGuardInternalImpl = ReentrancyGuardComponent::InternalImpl<ContractState>;

    use strkfarm_contracts::strategies::vesu_rebalance::interface::{
        IVesuRebal, Action, Feature, PoolProps, Settings
    };

    pub mod Errors {
        pub const INVALID_YIELD: felt252 = 'Insufficient yield';
        pub const INVALID_POOL_ID: felt252 = 'Invalid pool id';
        pub const INVALID_BALANCE: felt252 = 'remaining amount should be zero';
        pub const UNUTILIZED_ASSET: felt252 = 'Unutilized asset in vault';
        pub const MAX_WEIGHT_EXCEEDED: felt252 = 'Max weight exceeded';
        pub const INVALID_POOL_LENGTH: felt252 = 'Invalid pool length';
        pub const INVALID_POOL_CONFIG: felt252 = 'Invalid pool config';
    }

    #[storage]
    struct Storage {
        #[substorage(v0)]
        reng: ReentrancyGuardComponent::Storage,
        #[substorage(v0)]
        reward_share: RewardShareComponent::Storage,
        #[substorage(v0)]
        erc4626: ERC4626Component::Storage,
        #[substorage(v0)]
        erc20: ERC20Component::Storage,
        #[substorage(v0)]
        src5: SRC5Component::Storage,
        #[substorage(v0)]
        upgradeable: UpgradeableComponent::Storage,
        #[substorage(v0)]
        pausable: PausableComponent::Storage,
        #[substorage(v0)]
        common: CommonComp::Storage,
        allowed_pools: List<PoolProps>,
        settings: Settings,
        previous_index: u128,
        vesu_settings: vesuStruct,
        is_incentives_on: bool,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        ReentrancyGuardEvent: ReentrancyGuardComponent::Event,
        #[flat]
        ERC4626Event: ERC4626Component::Event,
        #[flat]
        RewardShareEvent: RewardShareComponent::Event,
        #[flat]
        ERC20Event: ERC20Component::Event,
        #[flat]
        SRC5Event: SRC5Component::Event,
        #[flat]
        UpgradeableEvent: UpgradeableComponent::Event,
        #[flat]
        PausableEvent: PausableComponent::Event,
        #[flat]
        CommonCompEvent: CommonComp::Event,
        Rebalance: Rebalance,
        CollectFees: CollectFees,
        Harvest: HarvestEvent,
    }

    #[derive(Drop, starknet::Event)]
    pub struct Rebalance {
        yield_before: u128,
        yield_after: u128,
    }

    #[derive(Drop, starknet::Event)]
    pub struct CollectFees {
        fee_collected: u128,
        fee_collector: ContractAddress,
    }

    const DEFAULT_INDEX: u128 = 1000_000_000_000_000_000;

    #[constructor]
    fn constructor(
        ref self: ContractState,
        name: ByteArray,
        symbol: ByteArray,
        asset: ContractAddress,
        access_control: ContractAddress,
        allowed_pools: Array<PoolProps>,
        settings: Settings,
        vesu_settings: vesuStruct,
    ) {
        self.erc4626.initializer(asset);
        self.erc20.initializer(name, symbol);
        self.common.initializer(access_control);
        self._set_pool_settings(allowed_pools);

        self.settings.write(settings);
        self.vesu_settings.write(vesu_settings);

        // default index 10**18 (i.e. 1)
        self.previous_index.write(DEFAULT_INDEX);

        // since defi spring is active now
        self.is_incentives_on.write(true);

        self.reward_share.init(get_block_number());
    }

    #[abi(embed_v0)]
    impl ExternalImpl of IVesuRebal<ContractState> {
        /// @notice Rebalances users position in vesu to optimize yield
        /// @dev This function computes the yield before and after rebalancing, collects fees,
        /// executes rebalancing actions, and performs post-rebalance validations.
        /// @param actions Array of actions to be performed for rebalancing
        fn rebalance(ref self: ContractState, actions: Array<Action>) {
            // perform rebalance
            self.common.assert_not_paused();
            self._collect_fees(self.total_supply());

            // rebalance
            let (yield_before_rebalance, _) = self.compute_yield();
            self._rebal_loop(actions);
            let (yield_after_rebalance, _) = self.compute_yield();

            // post rebalance validations
            let this = get_contract_address();
            assert(yield_after_rebalance > yield_before_rebalance, Errors::INVALID_YIELD);
            assert(ERC20Helper::balanceOf(self.asset(), this) == 0, Errors::UNUTILIZED_ASSET);
            self._assert_max_weights();

            self
                .emit(
                    Rebalance {
                        yield_before: yield_before_rebalance.try_into().unwrap(),
                        yield_after: yield_after_rebalance.try_into().unwrap()
                    }
                );
        }

        fn emergency_withdraw(ref self: ContractState) {
            let allowed_pools = self.get_allowed_pools();
            let mut i = 0;
            loop {
                if (i == allowed_pools.len()) {
                    break;
                }

                self.emergency_withdraw_pool(i.try_into().unwrap());
                i += 1;
            };
        }

        fn emergency_withdraw_pool(ref self: ContractState, pool_index: u32) {
            self.common.assert_emergency_actor_role();
            let this = get_contract_address();
            let allowed_pools = self.get_allowed_pools();
            let pool_info = *allowed_pools.at(pool_index);
            let mut v_token = pool_info.v_token;

            let withdraw_amount = IERC4626Dispatcher { contract_address: v_token }
                .max_withdraw(this);

            if (withdraw_amount == 0) {
                return;
            }
            IERC4626Dispatcher { contract_address: v_token }.withdraw(withdraw_amount, this, this);
        }

        /// @notice Rebalances users position in vesu to balance weights
        /// @dev This function computes the yield before and after rebalancing, collects fees,
        /// executes rebalancing actions, and performs post-rebalance validations.
        /// @param actions Array of actions to be performed for rebalancing
        fn rebalance_weights(ref self: ContractState, actions: Array<Action>) {
            // perform rebalance
            self.common.assert_relayer_role();
            self.common.assert_not_paused();

            self._collect_fees(self.total_supply());
            self._rebal_loop(actions);

            // post rebalance validations
            let this = get_contract_address();
            self._assert_max_weights();
            assert(ERC20Helper::balanceOf(self.asset(), this) == 0, Errors::UNUTILIZED_ASSET);
        }

        // @notice computes overall yeild across all allowed pools. the yield computation isnt
        // exact, but more like a way to check if the yield change is positive or not. So, its
        // computed only to calculate the yield effect @dev Iterates through allowed pools,
        // calculates yield per pool, and aggregates.
        // @return (u256, u256) - The weighted average yield and the total amount across pools.
        fn compute_yield(self: @ContractState) -> (u256, u256) {
            let allowed_pools = self._get_pool_data();
            let mut i = 0;
            let mut yield_sum = 0;
            let mut amount_sum = 0;
            loop {
                if (i == allowed_pools.len()) {
                    break;
                }
                let pool = *allowed_pools.at(i);
                let interest_curr_pool = self._interest_rate_per_pool(pool.pool_id);
                let amount_in_pool = self._calculate_amount_in_pool(pool.v_token);
                yield_sum += (interest_curr_pool * amount_in_pool);
                amount_sum += amount_in_pool;
                i += 1;
            };

            ((yield_sum / amount_sum), amount_sum)
        }

        /// @notice Retrieves the contract's current settings.
        /// @dev Reads and returns the settings stored in the contract state.
        /// @return settings The current configuration settings of the contract.
        fn get_settings(self: @ContractState) -> Settings {
            self.settings.read()
        }

        /// @notice Returns the list of allowed pools.
        /// @dev Reads and returns the pool data from the contract state.
        /// @return allowed_pools An array of pool properties representing the allowed pools.
        fn get_allowed_pools(self: @ContractState) -> Array<PoolProps> {
            self._get_pool_data()
        }

        /// @notice Retrieves the previous index of the contract.
        /// @dev Reads and returns the previous index stored in the contract state.
        /// @return previous_index The current borrow configuration settings.
        fn get_previous_index(self: @ContractState) -> u128 {
            self.previous_index.read()
        }

        /// @notice Updates the contract settings.
        /// @dev Only addresses with GOVERNOR role can call this function to modify the settings.
        /// @param settings The new settings to be stored in the contract.
        fn set_settings(ref self: ContractState, settings: Settings) {
            self.common.assert_governor_role();
            self.settings.write(settings);
        }

        /// @notice Updates the contract settings.
        /// @dev Only addresses with GOVERNOR role can call this function to modify allowed pools.
        /// @param pools The new allowed pools to be stored in the contract.
        fn set_allowed_pools(ref self: ContractState, pools: Array<PoolProps>) {
            self.common.assert_governor_role();
            self._set_pool_settings(pools);
        }

        fn set_incentives_off(ref self: ContractState) {
            self.common.assert_governor_role();
            self.is_incentives_on.write(false);
        }

        fn harvest(
            ref self: ContractState,
            rewardsContract: ContractAddress,
            claim: Claim,
            proof: Span<felt252>,
            swapInfo: AvnuMultiRouteSwap
        ) {
            self.common.assert_not_paused();
            self.common.assert_relayer_role();

            let vesuSettings = SNFStyleClaimSettings { rewardsContract: rewardsContract, };
            let config = HarvestConfig {};
            // just dummy config, not used
            let snfSettings = SNFStyleClaimSettings {
                rewardsContract: contract_address_const::<0>()
            };

            let from_token = swapInfo.token_from_address;
            let to_token = swapInfo.token_to_address;
            let from_amount = swapInfo.token_from_amount;
            let pre_bal = ERC20Helper::balanceOf(
                to_token, get_contract_address()
            );
            config
                .simple_harvest(
                    ref self,
                    vesuSettings,
                    claim,
                    proof,
                    snfSettings,
                    swapInfo,
                    IPriceOracleDispatcher { contract_address: self.vesu_settings.read().oracle }
                );
            let post_bal = ERC20Helper::balanceOf(
                to_token, get_contract_address()
            );
            
            // if tokens are same, then we need to calculate the amount from diff
            let from_amount = if (from_token == to_token) {
                post_bal - pre_bal
            } else {
                // if not equal, the harvester assets the claim amount to be equal to the
                // from amount, so we can use that
                from_amount
            };
            self.emit(
                HarvestEvent {
                    rewardToken: from_token,
                    rewardAmount: from_amount,
                    baseToken: to_token,
                    baseAmount: post_bal - pre_bal,
                }
            );
        }
    }

    #[generate_trait]
    pub impl InternalImpl of InternalTrait {
        fn _handle_reward_shares(
            ref self: ContractState,
            from: ContractAddress,
            unminted_shares: u256,
            minted_shares: u256
        ) {
            if (from.is_zero()) {
                return;
            }

            let (additional_shares, last_block, pending_round_points) = self
                .reward_share
                .get_additional_shares(from);

            // settle any additional shares of the from address
            let additional_u256: u256 = additional_shares.try_into().unwrap();
            if (self.is_incentives_on.read()) {
                let user_shares = self.erc20.balance_of(from);

                // update rewards state for from address
                let mut new_shares = user_shares + additional_u256 - unminted_shares;
                let total_supply = self.total_supply() - minted_shares;
                self
                    .reward_share
                    .update_user_rewards(
                        from,
                        new_shares.try_into().unwrap(),
                        additional_shares,
                        last_block,
                        pending_round_points,
                        total_supply.try_into().unwrap()
                    );
            }

            if (additional_u256 > 0) {
                // mint after updating rewards bcz mint will recursively call this hook
                // and updating rewards will before will make additional_shares 0
                // and avoid calling mint again
                self.erc20.mint(from, additional_shares.try_into().unwrap());
            }
        }

        fn _assert_max_weights(self: @ContractState) {
            let total_amount = self.total_assets();
            let allowed_pools = self._get_pool_data();
            let mut i = 0;
            loop {
                if (i == allowed_pools.len()) {
                    break;
                }
                let pool = *allowed_pools.at(i);
                let asset_in_pool = self._calculate_amount_in_pool(pool.v_token);
                let asset_basis: u32 = ((asset_in_pool * 10000) / total_amount).try_into().unwrap();
                assert(asset_basis <= pool.max_weight, Errors::MAX_WEIGHT_EXCEEDED);
                i += 1;
            }
        }

        fn _calculate_amount_in_pool(self: @ContractState, v_token: ContractAddress) -> u256 {
            let this = get_contract_address();
            let v_token_bal = ERC20Helper::balanceOf(v_token, this);
            IERC4626Dispatcher { contract_address: v_token }.convert_to_assets(v_token_bal)
        }

        fn _interest_rate_per_pool(self: @ContractState, pool_id: felt252) -> u256 {
            let singleton = self.vesu_settings.read().singleton;
            let asset = self.asset();
            // get utilization for asset
            let utilization = singleton.utilization(pool_id, asset);

            // get asset info
            let (asset_info, _) = singleton.asset_config(pool_id, asset);

            let extension = singleton.extension(pool_id,);
            let interest_rate = IVesuExtensionDispatcher { contract_address: extension }
                .interest_rate(
                    pool_id,
                    asset,
                    utilization,
                    asset_info.last_updated,
                    asset_info.last_full_utilization_rate
                );

            // apy = utilization * ((1+interest_rate/10^18)^(360*86400) - 1)
            // return after using formula
            (interest_rate * utilization)
        }

        fn _set_pool_settings(ref self: ContractState, allowed_pools: Array<PoolProps>,) {
            let old_pools = self._get_pool_data();
            let old_default_pool_index = self.settings.read().default_pool_index;

            assert(allowed_pools.len() > 0, Errors::INVALID_POOL_LENGTH);
            let mut pools_str = self.allowed_pools.read();
            pools_str.clean();
            pools_str.append_span(allowed_pools.span()).unwrap();
            assert(
                self.allowed_pools.read().len() == allowed_pools.len(), Errors::INVALID_POOL_LENGTH
            );

            // check if any pool is removed
            let mut old_index = 0;
            loop {
                if old_index == old_pools.len() {
                    break;
                }
                let pool = *old_pools.at(old_index);
                let mut new_index = 0;
                let mut found = false;
                loop {
                    if new_index == allowed_pools.len() {
                        break;
                    }
                    let new_pool = *allowed_pools.at(new_index);
                    if pool.pool_id == new_pool.pool_id {
                        found = true;

                        // update default pool index corresponding to the pool id
                        if (old_index == (old_default_pool_index).into()) {
                            self
                                .settings
                                .write(
                                    Settings {
                                        default_pool_index: new_index.try_into().unwrap(),
                                        ..self.settings.read()
                                    }
                                );
                        }
                        break;
                    }
                    new_index += 1;
                };

                if (!found) {
                    // its ok to remove pool if its empty
                    let v_token = pool.v_token;
                    let v_token_bal = ERC20Helper::balanceOf(v_token, get_contract_address());
                    assert(v_token_bal == 0, Errors::INVALID_POOL_CONFIG);
                }
                old_index += 1;
            };
        }

        fn _get_pool_data(self: @ContractState) -> Array<PoolProps> {
            let mut pool_ids_array = self.allowed_pools.read().array().unwrap();

            pool_ids_array
        }

        fn _compute_assets(self: @ContractState) -> u256 {
            let mut assets: u256 = 0;
            let pool_ids_array = self._get_pool_data();
            //loop through all pool ids and calc token balances
            let mut i = 0;
            loop {
                if i == pool_ids_array.len() {
                    break;
                }
                let v_token = *pool_ids_array.at(i).v_token;
                let asset_conv = self._calculate_amount_in_pool(v_token);
                assets += asset_conv;
                i += 1;
            };

            assets
        }

        // required fee
        // @param previous_total_supply: The supply using which fee share is calculated
        fn _collect_fees(ref self: ContractState, previous_total_supply: u256) {
            let this = get_contract_address();
            let prev_index = self.previous_index.read();
            let assets = self.total_assets();

            // since any newly minted tokens in transaction as minted at same rate
            // as just before transaction, using total_supply now is ok bcz total_assets is
            // also as of now
            let total_supply = self.total_supply();
            let curr_index = (assets * DEFAULT_INDEX.into()) / total_supply;
            if curr_index < prev_index.into() {
                let new_index = ((assets - 1) * DEFAULT_INDEX.into()) / total_supply;
                self.previous_index.write(new_index.try_into().unwrap());
                return;
            }
            let index_diff = curr_index.try_into().unwrap() - prev_index;

            // compute fee in asset()
            let numerator: u256 = previous_total_supply
                * index_diff.into()
                * self.settings.fee_bps.read().into();
            let denominator: u256 = 10000 * DEFAULT_INDEX.into();
            let fee = if (numerator <= 1) {
                0
            } else {
                (numerator - 1) / denominator
            };
            if fee == 0 { // no point of transfer logic if fee = 0
                return;
            }

            let mut fee_loop = fee;
            let allowed_pools = self._get_pool_data();
            let fee_receiver = self.settings.fee_receiver.read();
            let mut i = 0;
            loop {
                if i == allowed_pools.len() {
                    break;
                }
                let v_token = *allowed_pools.at(i).v_token;
                let vault_disp = IERC4626Dispatcher { contract_address: v_token };
                let v_shares_required = vault_disp.convert_to_shares(fee_loop.into());
                let v_token_bal = ERC20Helper::balanceOf(v_token, this);
                if v_shares_required <= v_token_bal {
                    ERC20Helper::transfer(v_token, fee_receiver, v_shares_required);
                    break;
                } else {
                    ERC20Helper::transfer(v_token, fee_receiver, v_token_bal);
                    fee_loop -= vault_disp.convert_to_assets(v_token_bal).try_into().unwrap();
                }
                i += 1;
            };

            // adjust the fee taken and update index
            // -1 to round down
            let new_index = ((assets - fee.into() - 1) * DEFAULT_INDEX.into()) / total_supply;
            self.previous_index.write(new_index.try_into().unwrap());

            self
                .emit(
                    CollectFees {
                        fee_collected: fee.try_into().unwrap(), fee_collector: fee_receiver
                    }
                );
        }

        fn _rebal_loop(ref self: ContractState, action_array: Array<Action>) {
            let mut i = 0;
            loop {
                if i == action_array.len() {
                    break;
                }
                let mut action = action_array.at(i);
                self._action(*action);
                i += 1;
            }
        }

        fn _action(ref self: ContractState, action: Action) {
            let this = get_contract_address();
            let allowed_pools = self.get_allowed_pools();
            let mut i = 0;
            let mut v_token = allowed_pools.at(i).v_token;
            loop {
                assert(i != allowed_pools.len(), Errors::INVALID_POOL_ID);
                if *allowed_pools.at(i).pool_id == action.pool_id {
                    v_token = allowed_pools.at(i).v_token;
                    break;
                }
                i += 1;
            };

            match action.feature {
                Feature::DEPOSIT => {
                    ERC20Helper::approve(self.asset(), *v_token, action.amount);
                    IERC4626Dispatcher { contract_address: *v_token }.deposit(action.amount, this);
                },
                Feature::WITHDRAW => {
                    // Max withdraw condition not required as this is called by rebalance function
                    // which is managed by us, so we can ensure that the amount is within limits
                    IERC4626Dispatcher { contract_address: *v_token }
                        .withdraw(action.amount, this, this);
                },
            };
        }

        fn _perform_withdraw_max_possible(
            ref self: ContractState, pool_id: felt252, v_token: ContractAddress, amount: u256
        ) -> u256 {
            let this = get_contract_address();
            let max_withdraw = IERC4626Dispatcher { contract_address: v_token }.max_withdraw(this);
            let withdraw_amount = if max_withdraw >= amount {
                amount
            } else {
                max_withdraw
            };

            if (withdraw_amount == 0) {
                return 0;
            }

            IERC4626Dispatcher { contract_address: v_token }.withdraw(withdraw_amount, this, this);

            return withdraw_amount;
        }

        // When handling Defi spring harvest distribution,
        // this function returns the shares to be used to compute points
        // after each action
        fn _get_user_shares(
            self: @ContractState, action_type: Feature, owner: ContractAddress, shares: u256
        ) -> u256 {
            let bal = self.balance_of(owner);
            let _shares = match action_type {
                Feature::DEPOSIT => { bal + shares },
                Feature::WITHDRAW => { bal - shares }
            };
            return _shares;
        }
    }

    #[abi(embed_v0)]
    impl VesuERC4626Impl of IERC4626<ContractState> {
        fn asset(self: @ContractState) -> ContractAddress {
            self.erc4626.asset()
        }

        fn convert_to_assets(self: @ContractState, shares: u256) -> u256 {
            self.erc4626.convert_to_assets(shares)
        }

        fn convert_to_shares(self: @ContractState, assets: u256) -> u256 {
            self.erc4626.convert_to_shares(assets)
        }

        fn deposit(
            ref self: ContractState, assets: u256, receiver: starknet::ContractAddress
        ) -> u256 {
            self.erc4626.deposit(assets, receiver)
        }

        fn max_deposit(self: @ContractState, receiver: ContractAddress) -> u256 {
            self.erc4626.max_deposit(receiver)
        }

        fn max_mint(self: @ContractState, receiver: starknet::ContractAddress) -> u256 {
            self.erc4626.max_mint(receiver)
        }

        fn max_redeem(self: @ContractState, owner: starknet::ContractAddress) -> u256 {
            self.erc4626.max_redeem(owner)
        }

        fn max_withdraw(self: @ContractState, owner: starknet::ContractAddress) -> u256 {
            self.erc4626.max_withdraw(owner)
        }

        fn mint(
            ref self: ContractState, shares: u256, receiver: starknet::ContractAddress
        ) -> u256 {
            self.erc4626.mint(shares, receiver)
        }

        fn preview_deposit(self: @ContractState, assets: u256) -> u256 {
            self.erc4626.preview_deposit(assets)
        }

        fn preview_mint(self: @ContractState, shares: u256) -> u256 {
            self.erc4626.preview_mint(shares)
        }

        fn preview_redeem(self: @ContractState, shares: u256) -> u256 {
            self.erc4626.preview_redeem(shares)
        }

        fn preview_withdraw(self: @ContractState, assets: u256) -> u256 {
            self.erc4626.preview_withdraw(assets)
        }

        fn redeem(
            ref self: ContractState,
            shares: u256,
            receiver: starknet::ContractAddress,
            owner: starknet::ContractAddress
        ) -> u256 {
            self.erc4626.redeem(shares, receiver, owner)
        }

        fn total_assets(self: @ContractState) -> u256 {
            let bal = ERC20Helper::balanceOf(self.asset(), get_contract_address());
            self._compute_assets() + bal
        }

        fn withdraw(
            ref self: ContractState,
            assets: u256,
            receiver: starknet::ContractAddress,
            owner: starknet::ContractAddress
        ) -> u256 {
            self.erc4626.withdraw(assets, receiver, owner)
        }
    }

    #[abi(embed_v0)]
    impl VesuERC20Impl of IERC20Mixin<ContractState> {
        fn total_supply(self: @ContractState) -> u256 {
            let unminted_shares = self.reward_share.get_total_unminted_shares();
            let total_supply = self.erc20.total_supply();
            let total_supply: u256 = total_supply + unminted_shares.try_into().unwrap();

            total_supply
        }

        fn balance_of(self: @ContractState, account: ContractAddress) -> u256 {
            let (additional_shares, _, _) = self.reward_share.get_additional_shares(account);
            self.erc20.balance_of(account) + additional_shares.into()
        }

        fn allowance(
            self: @ContractState, owner: ContractAddress, spender: ContractAddress
        ) -> u256 {
            self.erc20.allowance(owner, spender)
        }
        fn transfer(ref self: ContractState, recipient: ContractAddress, amount: u256) -> bool {
            self.erc20.transfer(recipient, amount)
        }
        fn transfer_from(
            ref self: ContractState,
            sender: ContractAddress,
            recipient: ContractAddress,
            amount: u256,
        ) -> bool {
            self.erc20.transfer_from(sender, recipient, amount)
        }
        fn approve(ref self: ContractState, spender: ContractAddress, amount: u256) -> bool {
            self.erc20.approve(spender, amount)
        }

        fn name(self: @ContractState) -> ByteArray {
            self.erc4626.name()
        }

        fn symbol(self: @ContractState) -> ByteArray {
            self.erc4626.symbol()
        }

        fn decimals(self: @ContractState) -> u8 {
            ERC20Helper::decimals(self.asset())
        }

        fn totalSupply(self: @ContractState) -> u256 {
            self.total_supply()
        }

        fn balanceOf(self: @ContractState, account: ContractAddress) -> u256 {
            self.balance_of(account)
        }

        fn transferFrom(
            ref self: ContractState,
            sender: ContractAddress,
            recipient: ContractAddress,
            amount: u256,
        ) -> bool {
            self.transfer_from(sender, recipient, amount)
        }
    }

    impl ERC4626DefaultNoFees of ERC4626Component::FeeConfigTrait<ContractState> {}

    impl ERC4626DefaultLimits<ContractState> of ERC4626Component::LimitConfigTrait<ContractState> {}

    impl DefaultConfig of ERC4626Component::ImmutableConfig {
        const UNDERLYING_DECIMALS: u8 =
            0; // Technically not used, as fn decimals() is self.assets().decimals()
        const DECIMALS_OFFSET: u8 = 0;
    }

    impl HooksImpl of ERC4626Component::ERC4626HooksTrait<ContractState> {
        /// @notice Handles post-deposit operations for ERC-4626 vault deposits.
        /// @dev This function approves asset transfers, deposits assets into the default pool,
        /// and collects fees after the deposit.
        /// @param assets The amount of assets deposited.
        /// @param shares The number of shares minted in exchange for the deposited assets.
        fn after_deposit(
            ref self: ERC4626Component::ComponentState<ContractState>, assets: u256, shares: u256,
        ) {
            let mut contract_state = self.get_contract_mut();
            contract_state.common.assert_not_paused();

            let pool_ids_array = contract_state._get_pool_data();
            let this = get_contract_address();
            // deposit normally
            let default_pool_index = contract_state.settings.default_pool_index.read();
            let v_token = *pool_ids_array.at(default_pool_index.into()).v_token;
            ERC20Helper::approve(self.asset(), v_token, assets);
            IERC4626Dispatcher { contract_address: v_token }.deposit(assets, this);
            contract_state._collect_fees(contract_state.total_supply() - shares);
        }

        /// @notice Handles pre-withdrawal operations to ensure liquidity availability.
        /// @dev This function first attempts to withdraw from the default pool.
        /// If the full amount cannot be withdrawn, it asserts that borrowing is disabled
        /// and withdraws the remaining amount from other pools.
        /// @param assets The amount of assets to withdraw.
        /// @param shares The number of shares to redeem.
        fn before_withdraw(
            ref self: ERC4626Component::ComponentState<ContractState>, assets: u256, shares: u256
        ) {
            let mut contract_state = self.get_contract_mut();
            contract_state.common.assert_not_paused();
            contract_state._collect_fees(contract_state.total_supply());
            let mut pool_ids_array = contract_state._get_pool_data();

            // loop through all pools and withdraw max possible from each pool
            let mut remaining_amount = assets;
            let mut i = 0;
            loop {
                if i == pool_ids_array.len() {
                    break;
                }
                let withdrawn_amount = contract_state
                    ._perform_withdraw_max_possible(
                        *pool_ids_array.at(i).pool_id,
                        *pool_ids_array.at(i).v_token,
                        remaining_amount
                    );
                remaining_amount -= withdrawn_amount;
                if (remaining_amount == 0) {
                    break;
                }
                i += 1;
            };
            assert(remaining_amount == 0, Errors::INVALID_BALANCE);
        }
    }

    impl ERC20HooksImpl of ERC20Component::ERC20HooksTrait<ContractState> {
        fn before_update(
            ref self: ERC20Component::ComponentState<ContractState>,
            from: ContractAddress,
            recipient: ContractAddress,
            amount: u256,
        ) {
            let mut state = self.get_contract_mut();
            state._handle_reward_shares(from, amount, 0);
        }

        fn after_update(
            ref self: ERC20Component::ComponentState<ContractState>,
            from: ContractAddress,
            recipient: ContractAddress,
            amount: u256,
        ) {
            let mut state = self.get_contract_mut();
            state._handle_reward_shares(recipient, 0, amount);
        }
    }

    /// hooks defining before and after actions for the harvest function
    impl HarvestHooksImpl of HarvestHooksTrait<ContractState> {
        fn before_update(ref self: ContractState) -> HarvestBeforeHookResult {
            self._collect_fees(self.total_supply());
            HarvestBeforeHookResult { baseToken: self.asset() }
        }

        fn after_update(ref self: ContractState, token: ContractAddress, amount: u256) {
            let fee = (amount * self.settings.fee_bps.read().into()) / 10000;
            if (fee > 0) {
                let fee_receiver = self.settings.fee_receiver.read();
                ERC20Helper::transfer(token, fee_receiver, fee);
            }
            let amt = amount - fee;
            let shares = self.convert_to_shares(amt);

            // deposit normally
            let pool_ids_array = self._get_pool_data();
            let default_pool_index = self.settings.default_pool_index.read();
            let v_token = *pool_ids_array.at(default_pool_index.into()).v_token;
            ERC20Helper::approve(self.asset(), v_token, amt);
            IERC4626Dispatcher { contract_address: v_token }.deposit(amt, get_contract_address());

            let total_shares = self.total_supply();
            self
                .reward_share
                .update_harvesting_rewards(
                    amt.try_into().unwrap(),
                    shares.try_into().unwrap(),
                    total_shares.try_into().unwrap()
                );
        }
    }
}

