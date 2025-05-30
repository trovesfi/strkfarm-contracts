#[cfg(test)]
pub mod test_vesu_rebalance {
    use snforge_std::{
        declare, ContractClassTrait, start_cheat_caller_address, stop_cheat_caller_address,
        start_cheat_block_number_global, start_cheat_block_timestamp_global,
    };
    use starknet::contract_address::contract_address_const;
    use snforge_std::{DeclareResultTrait, replace_bytecode};
    use starknet::{ContractAddress, get_contract_address, get_block_timestamp};
    use strkfarm_contracts::helpers::constants;
    use strkfarm_contracts::components::ekuboSwap::{ekuboSwapImpl};
    use strkfarm_contracts::tests::utils as test_utils;
    use strkfarm_contracts::helpers::ERC20Helper;
    use strkfarm_contracts::components::swap::{AvnuMultiRouteSwap, Route};
    use strkfarm_contracts::helpers::pow;
    use strkfarm_contracts::strategies::vesu_rebalance::interface::{
        PoolProps, Settings, Action, Feature
    };
    use strkfarm_contracts::components::vesu::{vesuStruct, vesuSettingsImpl};
    use strkfarm_contracts::interfaces::IVesu::{IStonDispatcher};
    use openzeppelin::token::erc20::interface::{IERC20MixinDispatcher, IERC20MixinDispatcherTrait};
    use strkfarm_contracts::strategies::vesu_rebalance::interface::{
        IVesuRebalDispatcher, IVesuRebalDispatcherTrait, IVesuMigrateDispatcher, IVesuMigrateDispatcherTrait
    };
    use strkfarm_contracts::interfaces::IERC4626::{IERC4626Dispatcher, IERC4626DispatcherTrait};
    use strkfarm_contracts::interfaces::IEkuboDistributor::{Claim};
    use strkfarm_contracts::components::harvester::reward_shares::{
        IRewardShareDispatcher, IRewardShareDispatcherTrait
    };
    use openzeppelin::utils::serde::SerializedAppend;

    fn get_allowed_pools() -> Array<PoolProps> {
        let mut allowed_pools = ArrayTrait::<PoolProps>::new();
        allowed_pools
            .append(
                PoolProps {
                    pool_id: constants::VESU_GENESIS_POOL().into(),
                    max_weight: 5000,
                    v_token: contract_address_const::<
                        0x37ae3f583c8d644b7556c93a04b83b52fa96159b2b0cbd83c14d3122aef80a2
                    >()
                }
            );
        allowed_pools
            .append(
                PoolProps {
                    pool_id: constants::RE7_XSTRK_POOL().into(),
                    max_weight: 4000,
                    v_token: contract_address_const::<
                        0x1f876e2da54266911d8a7409cba487414d318a2b6540149520bf7e2af56b93c
                    >()
                }
            );
        allowed_pools
            .append(
                PoolProps {
                    pool_id: constants::RE7_SSTRK_POOL().into(),
                    max_weight: 3000,
                    v_token: contract_address_const::<
                        0x5afdf4d18501d1d9d4664390df8c0786a6db8f28e66caa8800f1c2f51396492
                    >()
                }
            );
        allowed_pools
            .append(
                PoolProps {
                    pool_id: constants::RE7_USDC_POOL().into(),
                    max_weight: 1000,
                    v_token: contract_address_const::<
                        0xb5581d0bc94bc984cf79017d0f4b079c7e926af3d79bd92ff66fb451b340df
                    >()
                }
            );

        allowed_pools
    }

    fn get_settings() -> Settings {
        Settings {
            default_pool_index: 0, fee_bps: 1000, fee_receiver: constants::NOSTRA_USDC_DEBT(),
        }
    }

    fn get_vesu_settings() -> vesuStruct {
        vesuStruct {
            singleton: IStonDispatcher { contract_address: constants::VESU_SINGLETON_ADDRESS(), },
            pool_id: contract_address_const::<0x00>().into(),
            debt: contract_address_const::<0x00>(),
            col: constants::STRK_ADDRESS(),
            oracle: constants::ORACLE_OURS()
        }
    }

    fn VAULT_NAME() -> ByteArray {
        "VesuRebalance"
    }
    fn VAULT_SYMBOL() -> ByteArray {
        "VS"
    }

    fn deploy_vesu_vault() -> (ContractAddress, IVesuRebalDispatcher, IERC4626Dispatcher) {
        let allowed_pools = get_allowed_pools();
        return _deploy_vesu_vault(constants::STRK_ADDRESS(), allowed_pools);
    }

    fn USDC_VTOKEN_GENESIS() -> ContractAddress {
        return contract_address_const::<
            0x1610abab2ff987cdfb5e73cccbf7069cbb1a02bbfa5ee31d97cc30e29d89090
        >();
    }

    fn deploy_usdc_vesu_vault() -> (ContractAddress, IVesuRebalDispatcher, IERC4626Dispatcher) {
        let mut allowed_pools = get_allowed_pools();
        let mut pool1 = allowed_pools[0];
        let pool1 = PoolProps {
            pool_id: *pool1.pool_id, max_weight: 5000, v_token: USDC_VTOKEN_GENESIS()
        };
        let allowed_pools: Array<PoolProps> = array![pool1];
        return _deploy_vesu_vault(constants::USDC_ADDRESS(), allowed_pools);
    }

    fn _deploy_vesu_vault(
        asset: ContractAddress, allowed_pools: Array<PoolProps>
    ) -> (ContractAddress, IVesuRebalDispatcher, IERC4626Dispatcher) {
        let accessControl = test_utils::deploy_access_control();
        let vesu_rebal = declare("VesuRebalance").unwrap().contract_class();
        let settings = get_settings();
        let mut vesu_settings = get_vesu_settings();
        vesu_settings.col = asset;
        let mut calldata: Array<felt252> = array![];
        calldata.append_serde(VAULT_NAME());
        calldata.append_serde(VAULT_SYMBOL());
        calldata.append(asset.into());
        calldata.append(accessControl.into());
        allowed_pools.serialize(ref calldata);
        settings.serialize(ref calldata);
        vesu_settings.serialize(ref calldata);

        let (address, _) = vesu_rebal.deploy(@calldata).expect('Vesu vault deploy failed');

        (
            address,
            IVesuRebalDispatcher { contract_address: address },
            IERC4626Dispatcher { contract_address: address }
        )
    }

    fn vault_init(amount: u256) {
        let vesu_user = constants::TestUserStrk3();
        let this = get_contract_address();
        start_cheat_caller_address(constants::STRK_ADDRESS(), vesu_user);
        ERC20Helper::transfer(constants::STRK_ADDRESS(), this, amount);
        stop_cheat_caller_address(constants::STRK_ADDRESS());
    }

    fn get_prev_const() -> u128 {
        1000_000_000_000_000_000
    }

    #[test]
    #[fork("mainnet_latest")]
    fn test_vesu_constructor() {
        let (_, vesu_disp, vesu_erc4626) = deploy_vesu_vault();
        assert(vesu_erc4626.asset() == constants::STRK_ADDRESS(), 'invalid asset');
        assert(vesu_disp.get_previous_index() == get_prev_const(), 'invalid prev val');

        let erc20Disp = IERC20MixinDispatcher { contract_address: vesu_disp.contract_address };
        assert(erc20Disp.name() == VAULT_NAME(), 'invalid name');
        assert(erc20Disp.symbol() == VAULT_SYMBOL(), 'invalid symbol');
        assert(erc20Disp.decimals() == 18, 'invalid decimals');
    }

    #[test]
    #[fork("mainnet_latest")]
    fn test_vesu_constructor_usdc() {
        let accessControl = test_utils::deploy_access_control();
        let vesu_rebal = declare("VesuRebalance").unwrap().contract_class();
        let allowed_pools = get_allowed_pools();
        let settings = get_settings();
        let vesu_settings = get_vesu_settings();
        let mut calldata: Array<felt252> = array![];
        calldata.append_serde(VAULT_NAME());
        calldata.append_serde(VAULT_SYMBOL());
        calldata.append(constants::USDC_ADDRESS().into());
        calldata.append(accessControl.into());
        allowed_pools.serialize(ref calldata);
        settings.serialize(ref calldata);
        vesu_settings.serialize(ref calldata);

        let (address, _) = vesu_rebal.deploy(@calldata).expect('Vesu vault deploy failed');

        let erc20Disp = IERC20MixinDispatcher { contract_address: address };
        assert(erc20Disp.name() == VAULT_NAME(), 'invalid name');
        assert(erc20Disp.symbol() == VAULT_SYMBOL(), 'invalid symbol');
        assert(erc20Disp.decimals() == 6, 'invalid decimals');
    }

    #[test]
    #[fork("mainnet_1134787")]
    fn test_vesu_deposit() {
        let amount = 1000 * pow::ten_pow(18);
        let this = get_contract_address();
        vault_init(amount * 100);

        let (vesu_address, vesu_vault, vesu_erc4626) = deploy_vesu_vault();
        ERC20Helper::approve(constants::STRK_ADDRESS(), vesu_address, amount);

        // first deposit
        let prev_index_before = vesu_vault.get_previous_index();
        let _ = vesu_erc4626.deposit(amount, this);
        let default_id = vesu_vault.get_settings().default_pool_index;
        let allowed_pools = vesu_vault.get_allowed_pools();
        let v_token = *allowed_pools.at(default_id.into()).v_token;
        let v_token_bal = ERC20Helper::balanceOf(v_token, vesu_address);
        let pool_assets = IERC4626Dispatcher { contract_address: v_token }
            .convert_to_assets(v_token_bal);
        assert(pool_assets == 999999999999999999999, 'invalid asset deposited');
        let prev_index_after = vesu_vault.get_previous_index();
        /// println!("prev index before {:?}", prev_index_before);
        /// println!("prev index after {:?}", prev_index_after);
        assert(
            prev_index_before - 1 <= prev_index_after && prev_index_after <= prev_index_before + 1,
            'index not updated'
        );

        // second deposit
        let amount = 500 * pow::ten_pow(18);
        ERC20Helper::approve(constants::STRK_ADDRESS(), vesu_address, amount);
        let prev_index_before = vesu_vault.get_previous_index();
        let _ = vesu_erc4626.deposit(amount, this);
        let allowed_pools = vesu_vault.get_allowed_pools();
        let v_token = *allowed_pools.at(default_id.into()).v_token;
        let v_token_bal = ERC20Helper::balanceOf(v_token, vesu_address);
        let pool_assets = IERC4626Dispatcher { contract_address: v_token }
            .convert_to_assets(v_token_bal);
        /// println!("pool assets {:?}", pool_assets);
        assert(pool_assets == 1499999999999999999999, 'invalid asset deposited');
        let prev_index_after = vesu_vault.get_previous_index();
        assert(
            prev_index_after <= prev_index_before + 1 && prev_index_after >= prev_index_before - 1,
            'index not updated[2]'
        );
    }

    #[test]
    #[fork("mainnet_1134787")]
    fn test_vesu_withdraw() {
        let amount = 1000 * pow::ten_pow(18);
        let this = get_contract_address();
        vault_init(amount * 100);

        let (vesu_address, vesu_vault, vesu_erc4626) = deploy_vesu_vault();
        ERC20Helper::approve(constants::STRK_ADDRESS(), vesu_address, amount);

        // genesis as default pool
        let _ = vesu_erc4626.deposit(amount, this);
        // change default pool
        let new_settings = Settings {
            default_pool_index: 1, fee_bps: 1000, fee_receiver: constants::NOSTRA_USDC_DEBT(),
        };
        vesu_vault.set_settings(new_settings);
        assert(vesu_vault.get_settings().default_pool_index == 1, 'invalid index set');

        // deposit to new default pool
        let amount = 500 * pow::ten_pow(18);
        ERC20Helper::approve(constants::STRK_ADDRESS(), vesu_address, amount);
        let _ = vesu_erc4626.deposit(amount, this);

        let default_pool_index = vesu_vault.get_settings().default_pool_index;
        let default_pool_token = *vesu_vault
            .get_allowed_pools()
            .at(default_pool_index.into())
            .v_token;
        let assets = vesu_erc4626.convert_to_shares(amount);
        let assets_vesu = IERC4626Dispatcher { contract_address: default_pool_token }
            .convert_to_shares(assets);
        assert(
            ERC20Helper::balanceOf(default_pool_token, vesu_address) == assets_vesu,
            'invalid balance before'
        );
        // try and withdraw 1400 strk...should withdraw from default pool and remaining from other
        // pools
        let withdraw_amount = 1400 * pow::ten_pow(18);
        let strk_amount_before = ERC20Helper::balanceOf(vesu_erc4626.asset(), this);
        let _ = vesu_erc4626.withdraw(withdraw_amount, this, this);
        let strk_amount_after = ERC20Helper::balanceOf(vesu_erc4626.asset(), this);

        // curr default pool is allowed_pools_array[1] with bal -> 499999999999999999999
        // then flow moves to index 0 with bal -> 999999999999999999999
        let vBal = ERC20Helper::balanceOf(default_pool_token, vesu_address);
        let assets = IERC4626Dispatcher { contract_address: default_pool_token }
            .convert_to_assets(vBal);
        // ~100 strk left in vault
        /// println!("assets {:?}", assets);
        assert(assets == 99999999999999999997, 'invalid balance after');

        assert(strk_amount_after - strk_amount_before == withdraw_amount, 'invalid asset');
    }

    #[test]
    #[fork("mainnet_latest")]
    fn test_vesu_rebalance_action() {
        let amount = 5000 * pow::ten_pow(18);
        let this = get_contract_address();
        vault_init(amount * 100);

        let (vesu_address, vesu_vault, vesu_erc4626) = deploy_vesu_vault();
        ERC20Helper::approve(constants::STRK_ADDRESS(), vesu_address, amount);

        // genesis as default pool
        let _ = vesu_erc4626.deposit(amount, this);
        // change default pool
        let new_settings = Settings {
            default_pool_index: 3, fee_bps: 1000, fee_receiver: constants::NOSTRA_USDC_DEBT(),
        };
        vesu_vault.set_settings(new_settings);
        assert(vesu_vault.get_settings().default_pool_index == 3, 'invalid index set');

        // deposit to new default pool
        let amount = 1000 * pow::ten_pow(18);
        ERC20Helper::approve(constants::STRK_ADDRESS(), vesu_address, amount);
        let _ = vesu_erc4626.deposit(amount, this);

        // current average yield of vault is 4%
        // REBALANCE
        // action 1 : withdraw 2500 strk from genesis pool
        // action 2 : withdraw 1000 strk from RE7 USDC pool
        // action 3 : deposit 2000 strk to RE7 XSTRK pool
        // action 3 : deposit 1500 strk to RE7 SSTRK pool
        // current average yield of vault becomes ~10%

        let mut actions: Array<Action> = array![];
        // Action 1
        let action1 = Action {
            pool_id: constants::VESU_GENESIS_POOL().into(),
            feature: Feature::WITHDRAW,
            token: constants::STRK_ADDRESS(),
            amount: 2500 * pow::ten_pow(18)
        };
        actions.append(action1);

        // Action 2
        let action2 = Action {
            pool_id: constants::RE7_USDC_POOL().into(),
            feature: Feature::WITHDRAW,
            token: constants::STRK_ADDRESS(),
            amount: 1000 * pow::ten_pow(18)
        };
        actions.append(action2);

        // Action 3
        let action3 = Action {
            pool_id: constants::RE7_XSTRK_POOL().into(),
            feature: Feature::DEPOSIT,
            token: constants::STRK_ADDRESS(),
            amount: 2000 * pow::ten_pow(18)
        };
        actions.append(action3);

        // Action 4
        let action4 = Action {
            pool_id: constants::RE7_SSTRK_POOL().into(),
            feature: Feature::DEPOSIT,
            token: constants::STRK_ADDRESS(),
            amount: 1500 * pow::ten_pow(18)
        };
        actions.append(action4);

        // REBALANCE START
        vesu_vault.rebalance(actions);

        let allowed_pools = get_allowed_pools();
        let mut i = 0;
        loop {
            if i == allowed_pools.len() {
                break;
            }
            let v_token_bal = ERC20Helper::balanceOf(*allowed_pools.at(i).v_token, vesu_address);
            let _ = IERC4626Dispatcher { contract_address: *allowed_pools.at(i).v_token }
                .convert_to_assets(v_token_bal);
            i += 1;
        }
    }

    #[test]
    #[should_panic(expected: ('Insufficient yield',))]
    #[fork("mainnet_latest")]
    fn test_vesu_rebalance_should_fail() {
        let amount = 1000 * pow::ten_pow(18);
        let this = get_contract_address();
        vault_init(amount * 100);

        let (vesu_address, vesu_vault, vesu_erc4626) = deploy_vesu_vault();
        ERC20Helper::approve(constants::STRK_ADDRESS(), vesu_address, amount);

        // genesis as default pool
        let _ = vesu_erc4626.deposit(amount, this);

        // change default pool
        let new_settings = Settings {
            default_pool_index: 1, fee_bps: 1000, fee_receiver: constants::NOSTRA_USDC_DEBT(),
        };
        vesu_vault.set_settings(new_settings);
        assert(vesu_vault.get_settings().default_pool_index == 1, 'invalid index set');

        // deposit to new default pool
        let amount = 2000 * pow::ten_pow(18);
        ERC20Helper::approve(constants::STRK_ADDRESS(), vesu_address, amount);
        let _ = vesu_erc4626.deposit(amount, this);

        // change default pool
        let new_settings = Settings {
            default_pool_index: 2, fee_bps: 1000, fee_receiver: constants::NOSTRA_USDC_DEBT(),
        };
        vesu_vault.set_settings(new_settings);
        assert(vesu_vault.get_settings().default_pool_index == 2, 'invalid index set');

        // deposit to new default pool
        let amount = 1000 * pow::ten_pow(18);
        ERC20Helper::approve(constants::STRK_ADDRESS(), vesu_address, amount);
        let _ = vesu_erc4626.deposit(amount, this);

        let mut actions: Array<Action> = array![];
        // Action 1
        let action1 = Action {
            pool_id: constants::RE7_XSTRK_POOL().into(),
            feature: Feature::WITHDRAW,
            token: constants::STRK_ADDRESS(),
            amount: 800 * pow::ten_pow(18)
        };
        actions.append(action1);

        let action2 = Action {
            pool_id: constants::VESU_GENESIS_POOL().into(),
            feature: Feature::DEPOSIT,
            token: constants::STRK_ADDRESS(),
            amount: 800 * pow::ten_pow(18)
        };
        actions.append(action2);

        // REBALANCE START
        vesu_vault.rebalance(actions);
    }

    #[test]
    #[should_panic(expected: ('Access: Missing relayer role',))]
    #[fork("mainnet_latest")]
    fn test_vesu_rebalance_should_fail_relayer_role() {
        let amount = 5000 * pow::ten_pow(18);
        let this = get_contract_address();
        vault_init(amount * 100);

        let (vesu_address, vesu_vault, vesu_erc4626) = deploy_vesu_vault();
        ERC20Helper::approve(constants::STRK_ADDRESS(), vesu_address, amount);

        // genesis as default pool
        let _ = vesu_erc4626.deposit(amount, this);
        // change default pool
        let new_settings = Settings {
            default_pool_index: 3, fee_bps: 1000, fee_receiver: constants::NOSTRA_USDC_DEBT(),
        };
        vesu_vault.set_settings(new_settings);
        assert(vesu_vault.get_settings().default_pool_index == 3, 'invalid index set');

        // deposit to new default pool
        let amount = 1000 * pow::ten_pow(18);
        ERC20Helper::approve(constants::STRK_ADDRESS(), vesu_address, amount);
        let _ = vesu_erc4626.deposit(amount, this);

        // current average yield of vault is 4%
        // REBALANCE
        // action 1 : withdraw 2500 strk from genesis pool
        // action 2 : withdraw 1000 strk from RE7 USDC pool
        // action 3 : deposit 2000 strk to RE7 XSTRK pool
        // action 3 : deposit 1500 strk to RE7 SSTRK pool
        // current average yield of vault becomes ~10%

        let mut actions: Array<Action> = array![];
        // Action 1
        let action1 = Action {
            pool_id: constants::VESU_GENESIS_POOL().into(),
            feature: Feature::WITHDRAW,
            token: constants::STRK_ADDRESS(),
            amount: 2500 * pow::ten_pow(18)
        };
        actions.append(action1);

        // Action 2
        let action2 = Action {
            pool_id: constants::RE7_USDC_POOL().into(),
            feature: Feature::WITHDRAW,
            token: constants::STRK_ADDRESS(),
            amount: 1000 * pow::ten_pow(18)
        };
        actions.append(action2);

        // Action 3
        let action3 = Action {
            pool_id: constants::RE7_XSTRK_POOL().into(),
            feature: Feature::DEPOSIT,
            token: constants::STRK_ADDRESS(),
            amount: 2000 * pow::ten_pow(18)
        };
        actions.append(action3);

        // Action 4
        let action4 = Action {
            pool_id: constants::RE7_SSTRK_POOL().into(),
            feature: Feature::DEPOSIT,
            token: constants::STRK_ADDRESS(),
            amount: 1500 * pow::ten_pow(18)
        };
        actions.append(action4);

        // REBALANCE START
        start_cheat_caller_address(vesu_address, constants::USER2_ADDRESS());
        vesu_vault.rebalance_weights(actions);
        stop_cheat_caller_address(vesu_address);
    }

    #[test]
    #[fork("mainnet_1134787")]
    fn test_vesu_harvest_and_withdraw() {
        let block = 100;
        start_cheat_block_number_global(block);

        // Deploy the mock DefiSpringSNF contract
        let snf_defi_spring = test_utils::deploy_snf_spring_ekubo();
        let amount = 1000 * pow::ten_pow(18);

        let (vesu_address, vesu_vault, vesu_erc4626) = deploy_vesu_vault();

        // User 1 deposits
        let user1 = constants::TestUserStrk();
        start_cheat_caller_address(constants::STRK_ADDRESS(), user1);
        ERC20Helper::approve(constants::STRK_ADDRESS(), vesu_address, amount);
        stop_cheat_caller_address(constants::STRK_ADDRESS());
        start_cheat_caller_address(vesu_address, user1);
        let _ = vesu_erc4626.deposit(amount, user1);
        let reward_disp = IRewardShareDispatcher { contract_address: vesu_address };
        let (additional, last_block, pending_round_points) = reward_disp
            .get_additional_shares(get_contract_address());
        assert(additional == 0, 'invalid additional shares');
        assert(last_block == block, 'invalid last block');
        assert(pending_round_points == 0, 'invalid pending round points');
        stop_cheat_caller_address(vesu_address);
        /// println!("user 1 deposit");

        // Advance time by 100 blocks
        // User 2 deposits
        let block = block + 100;
        start_cheat_block_number_global(block);
        let user2 = constants::TestUserStrk3();

        start_cheat_caller_address(constants::STRK_ADDRESS(), user2);
        ERC20Helper::approve(constants::STRK_ADDRESS(), vesu_address, amount);
        stop_cheat_caller_address(constants::STRK_ADDRESS());

        start_cheat_caller_address(vesu_address, user2);
        let _ = vesu_erc4626.deposit(amount, user2);

        let (additional, last_block, _) = reward_disp.get_additional_shares(get_contract_address());
        assert(additional == 0, 'invalid additional shares');
        assert(last_block == block, 'invalid last block');
        stop_cheat_caller_address(vesu_address);
        /// println!("user 2 deposit");

        // Advance time by another 100 block
        // Harvest rewards from the mock DefiSpringSNF contract
        let block = block + 100;
        start_cheat_block_number_global(block);
        let claim = Claim {
            id: 0, amount: pow::ten_pow(18).try_into().unwrap(), claimee: vesu_address
        };
        let mut swap_params = STRKETHAvnuSwapInfo(claim.amount.into(), vesu_address);
        swap_params.token_to_address = constants::STRK_ADDRESS();
        let proofs: Array<felt252> = array![1];
        vesu_vault.harvest(snf_defi_spring.contract_address, claim, proofs.span(), swap_params);
        /// println!("harvest done");

        // Check total shares and rewards
        let erc20_disp = IERC20MixinDispatcher { contract_address: vesu_address };
        let total_shares = erc20_disp.total_supply();
        let user1_shares = erc20_disp.balance_of(user1);
        let user2_shares = erc20_disp.balance_of(user2);

        /// println!("total shares {:?}", total_shares);
        /// println!("user1 shares {:?}", user1_shares);
        /// println!("user2 shares {:?}", user2_shares);

        assert(total_shares > (amount * 2), 'shares should include rewards');
        assert(user1_shares > user2_shares, 'must have more shares');

        // Withdraw 100% from User 1
        start_cheat_caller_address(vesu_address, user1);
        let user1_assets = vesu_erc4626.convert_to_assets(user1_shares);
        let _ = vesu_erc4626.withdraw(user1_assets - 1, user1, user1);
        stop_cheat_caller_address(vesu_address);
        /// println!("user 1 withdraw");

        // Check User 1 balance after withdrawal
        let user1_balance = ERC20Helper::balanceOf(constants::STRK_ADDRESS(), user1);
        assert(user1_balance > amount, 'deposit should include rewards');
        /// println!("user 1 balance {:?}", user1_balance);

        // Withdraw 100% from User 2
        start_cheat_caller_address(vesu_address, user2);
        let user2_assets = vesu_erc4626.convert_to_assets(user2_shares);
        let withdraw_amt = user2_assets - (user2_assets / 10);
        let _ = vesu_erc4626.withdraw(withdraw_amt, user2, user2);
        stop_cheat_caller_address(vesu_address);
        /// println!("user 2 withdraw");

        // Check User 2 balance after withdrawal
        let user2_balance = ERC20Helper::balanceOf(constants::STRK_ADDRESS(), user2);
        assert(user2_balance > amount, 'deposit should include rewards');
    }

    #[test]
    #[fork("mainnet_1256209")]
    fn test_usdc_deposit() {
        // non-18 decimals test
        let amount = 1000 * pow::ten_pow(6);
        let this = get_contract_address();
        let time = get_block_timestamp();
        let block = 1255994;
        start_cheat_block_timestamp_global(time);
        start_cheat_block_number_global(block);

        // load USDC
        let source = contract_address_const::<
            0x00000005dd3d2f4429af886cd1a3b08289dbcea99a294197e9eb43b0e0325b4b
        >();
        start_cheat_caller_address(constants::USDC_ADDRESS(), source);
        ERC20Helper::transfer(constants::USDC_ADDRESS(), this, amount * 2);
        stop_cheat_caller_address(constants::USDC_ADDRESS());

        let (vesu_address, vesu_vault, vesu_erc4626) = deploy_usdc_vesu_vault();

        ERC20Helper::approve(constants::USDC_ADDRESS(), vesu_address, amount);

        // first deposit
        let prev_index_before = vesu_vault.get_previous_index();
        assert(prev_index_before == 1000000000000000000, 'invalid prev val');
        let _ = vesu_erc4626.deposit(amount, this);
        let default_id = vesu_vault.get_settings().default_pool_index;
        let allowed_pools = vesu_vault.get_allowed_pools();
        let v_token = *allowed_pools.at(default_id.into()).v_token;
        let v_token_bal = ERC20Helper::balanceOf(v_token, vesu_address);
        let pool_assets = IERC4626Dispatcher { contract_address: v_token }
            .convert_to_assets(v_token_bal);
        assert(pool_assets == 999999999, 'invalid asset deposited');
        let prev_index_after = vesu_vault.get_previous_index();
        assert(prev_index_after == 999999998000000000, 'index not updated');

        start_cheat_block_number_global(block + 100000);
        start_cheat_block_timestamp_global(time + 100000);

        // second deposit
        let amount = 500 * pow::ten_pow(6);
        let fee_receiver = get_settings().fee_receiver;
        let bal_before = ERC20Helper::balanceOf(USDC_VTOKEN_GENESIS(), fee_receiver);
        assert(bal_before == 0, 'invalid fee [1]');
        ERC20Helper::approve(constants::USDC_ADDRESS(), vesu_address, amount);
        let _ = vesu_erc4626.deposit(amount, this);
        let allowed_pools = vesu_vault.get_allowed_pools();
        let v_token = *allowed_pools.at(default_id.into()).v_token;
        let v_token_bal = ERC20Helper::balanceOf(v_token, vesu_address);
        let pool_assets = IERC4626Dispatcher { contract_address: v_token }
            .convert_to_assets(v_token_bal);
        assert(pool_assets == 1500003445, 'invalid asset deposited');
        let fee_after = ERC20Helper::balanceOf(USDC_VTOKEN_GENESIS(), fee_receiver);
        assert(fee_after == 377943322642573, 'invalid fee [2]');
        let prev_index_after = vesu_vault.get_previous_index();
        assert(prev_index_after == 1000003572004557877, 'index not updated[2]');
    }

    #[test]
    #[should_panic(expected: ('Access: Missing relayer role',))]
    #[fork("mainnet_1134787")]
    fn test_vesu_harvest_no_auth() {
        let block = 100;
        start_cheat_block_number_global(block);

        let snf_defi_spring = test_utils::deploy_snf_spring_ekubo();
        let _amount = 1000 * pow::ten_pow(18);

        // Deploy the mock DefiSpringSNF contract
        let (vesu_address, vesu_vault, _) = deploy_vesu_vault();
        let claim = Claim {
            id: 0, amount: pow::ten_pow(18).try_into().unwrap(), claimee: vesu_address
        };
        let swap_params = STRKETHAvnuSwapInfo(claim.amount.into(), vesu_address);
        let proofs: Array<felt252> = array![1];
        start_cheat_caller_address(vesu_address, constants::USER2_ADDRESS());
        vesu_vault.harvest(snf_defi_spring.contract_address, claim, proofs.span(), swap_params);
        stop_cheat_caller_address(vesu_address);
    }

    #[test]
    #[fork("mainnet_1446151")]
    fn test_v2_migration() {
        let vault = contract_address_const::<0x00a858c97e9454f407d1bd7c57472fc8d8d8449a777c822b41d18e387816f29c>();
        let vesu_vault = IERC4626Dispatcher { contract_address: vault };

        // config
        let total_assets_pre = vesu_vault.total_assets();
        let total_supply_pre = ERC20Helper::total_supply(vault);
        println!("Total assets before migration: {:?}", total_assets_pre);
        println!("Total supply before migration: {:?}", total_supply_pre);
        
        let user = contract_address_const::<0x0790C2340c4CB61AeA6c253Dc8Fcd115196d5bCdC35aF0260e0d6A727a474ff6>();
        let user_shares = ERC20Helper::balanceOf(vault, user);
        println!("User shares before migration: {:?}", user_shares);

        // upgrade
        let cls = declare("VesuRebalance").unwrap().contract_class();
        replace_bytecode(vault, *cls.class_hash).unwrap();

        let timelock = contract_address_const::<0x0613a26e199f9bafa9418567f4ef0d78e9496a8d6aab15fba718a2ec7f2f2f69>();
        let new_singleton = contract_address_const::<0x000d8d6dfec4d33bfb6895de9f3852143a17c6f92fd2a21da3d6924d34870160>();
        let old_v_tokens: Array<ContractAddress> = array![
            contract_address_const::<0x1610abab2ff987cdfb5e73cccbf7069cbb1a02bbfa5ee31d97cc30e29d89090>(),
            contract_address_const::<0x28795e04b2abaf61266faa81cc02d4d1a6ef8574fef383cdf6185ca580648aa>(),
            contract_address_const::<0x17f19582c61479f2fe0b6606300e975c0a8f439102f43eeecc1d0e9b3d84350>(),
            contract_address_const::<0x383c278dac0a6f2dae49960dfd189af5ded9a42b4a1f7c2b00b8d11ff82ff5d>(),
            contract_address_const::<0x7b207a4f928f1b729c9ad26da5e99d6a13b3a23216c597ad545390048cd051f>(),
            contract_address_const::<0x4d6cb9637b9af77fa7bfe4336777279eb8766ba30652e5186edc681effc0601>(),
            contract_address_const::<0x13ff7f2ad3e9ae7c94391b8271d5ab84f0ba7d59e33f781f3202829e41a028b>(),
            contract_address_const::<0x7d7b4fa4701a6e065e9bb1a6dc927b1513cea42dbdafd0168ed64070d136fc6>(),
        ];
        let new_v_tokens: Array<ContractAddress> = array![
            contract_address_const::<0x0227942991ea19a1843ed6d28af9458cf2566a3c2d6fccb2fd28f0424fce44b4>(),
            contract_address_const::<0x079824ac0f81aa0e4483628c3365c09fa74d86650fadccb2a733284d3a0a8b85>(),
            contract_address_const::<0x048f4e75c12ca9d35d6172b1cb5f1f70b094888003f9c94fe19f12a67947fd6d>(),
            contract_address_const::<0x02814990be52a1f8532d100f22cb26ad6aeda2928abc18480e409ef75df8ce84>(),
            contract_address_const::<0x01273cb69dbd8f0329533bcefc09391baff9ef88d31efce36bbb024cb0c0e0cc>(),
            contract_address_const::<0x030902db47321a71202d4473a59b54db2b1ad11897a0328ead363db7e9dce4c8>(),
            contract_address_const::<0x072803e813eb69d9aaea1c458ed779569c81bde0a2fc03ea2869876d13fa08d4>(),
            contract_address_const::<0x0150a0af5a972d0d0b4e6a87c21afe68f12dd4abcd7bc6f67cb49dbbec518238>(),
        ];
        start_cheat_caller_address(vault, timelock);
        IVesuMigrateDispatcher {
            contract_address: vault
        }.vesu_migrate(
            new_singleton,
            old_v_tokens, new_v_tokens
        );
        stop_cheat_caller_address(vault);
        println!("Vesu vault migration completed");

        // post config
        let total_assets_post = vesu_vault.total_assets();
        let total_supply_post = ERC20Helper::total_supply(vault);
        println!("Total assets after migration: {:?}", total_assets_post);
        println!("Total supply after migration: {:?}", total_supply_post);

        let user_shares_post = ERC20Helper::balanceOf(vault, user);
        println!("User shares after migration: {:?}", user_shares_post);

        // approve and deposit
        start_cheat_caller_address(constants::USDC_ADDRESS(), user);
        ERC20Helper::approve(
            constants::USDC_ADDRESS(), vault, 1000 * pow::ten_pow(6)
        );
        stop_cheat_caller_address(constants::USDC_ADDRESS());

        // deposit 1000 USDC
        start_cheat_caller_address(vault, user);
        vesu_vault.deposit(1000 * pow::ten_pow(6), user);
        stop_cheat_caller_address(vault);
    }
    

    fn STRKETHAvnuSwapInfo(amount: u256, beneficiary: ContractAddress) -> AvnuMultiRouteSwap {
        let additional1: Array<felt252> = array![
            constants::STRK_ADDRESS().into(),
            constants::ETH_ADDRESS().into(),
            34028236692093847977029636859101184,
            200,
            0,
            10000000000000000000000000000000000000000000000000000000000000000000000
        ];

        let additional2: Array<felt252> = array![
            constants::WST_ADDRESS().into(),
            constants::ETH_ADDRESS().into(),
            34028236692093847977029636859101184,
            200,
            0,
            10000000000000000000000000000000000000000000000000000000000000000000000
        ];
        let route = Route {
            token_from: constants::STRK_ADDRESS(),
            token_to: constants::ETH_ADDRESS(),
            exchange_address: constants::EKUBO_CORE(),
            percent: 1000000000000,
            additional_swap_params: additional1.clone(),
        };
        let route2 = Route {
            token_from: constants::ETH_ADDRESS(),
            token_to: constants::WST_ADDRESS(),
            exchange_address: constants::EKUBO_CORE(),
            percent: 1000000000000,
            additional_swap_params: additional2,
        };
        let routes: Array<Route> = array![route, route2];
        let admin = get_contract_address();
        AvnuMultiRouteSwap {
            token_from_address: constants::STRK_ADDRESS(),
            token_from_amount: amount, // claim amount
            token_to_address: constants::WST_ADDRESS(),
            token_to_amount: 0,
            token_to_min_amount: 0,
            beneficiary: beneficiary,
            integrator_fee_amount_bps: 0,
            integrator_fee_recipient: admin,
            routes
        }
    }
}
