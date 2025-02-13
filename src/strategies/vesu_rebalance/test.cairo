#[cfg(test)]
pub mod test_vesu_rebalance {
  use snforge_std::{
    declare, ContractClassTrait, start_cheat_caller_address, stop_cheat_caller_address,
    stop_cheat_block_timestamp_global, CheatSpan, start_cheat_block_timestamp, 
    stop_cheat_block_timestamp, cheat_caller_address, start_cheat_block_timestamp_global,
    start_cheat_block_number_global, stop_cheat_block_number_global
  };
  use starknet::contract_address::contract_address_const;
  use snforge_std::{BlockId, BlockTag, replace_bytecode, DeclareResultTrait};
  use starknet::{ContractAddress, get_block_timestamp, get_contract_address, class_hash::class_hash_const, SyscallResult, SyscallResultTrait};
  use strkfarm_contracts::helpers::constants;
  use strkfarm_contracts::components::ekuboSwap::{
    EkuboSwapStruct, ekuboSwapImpl
  };
  use strkfarm_contracts::helpers::ERC20Helper;
  use strkfarm_contracts::helpers::pow;
  use strkfarm_contracts::strategies::vesu_rebalance::interface::{PoolProps, Settings, BorrowSettings, Action, Feature};
  use strkfarm_contracts::components::vesu::{vesuStruct, vesuToken, vesuSettingsImpl};
  use strkfarm_contracts::interfaces::IVesu::{IStonDispatcher, IStonDispatcherTrait};
  use strkfarm_contracts::strategies::vesu_rebalance::interface::{IVesuRebalDispatcher, IVesuRebalDispatcherTrait};
  use strkfarm_contracts::interfaces::IERC4626::{IERC4626, IERC4626Dispatcher, IERC4626DispatcherTrait};
  use openzeppelin::utils::serde::SerializedAppend;

  fn get_allowed_pools() -> Array<PoolProps>{
    let mut allowed_pools = ArrayTrait::<PoolProps>::new();
    allowed_pools.append(PoolProps {
      pool_id: constants::VESU_GENESIS_POOL().into(),
      max_weight: 5000,
      v_token: contract_address_const::<0x37ae3f583c8d644b7556c93a04b83b52fa96159b2b0cbd83c14d3122aef80a2>()
    });
    allowed_pools.append(PoolProps {
      pool_id: constants::RE7_XSTRK_POOL().into(),
      max_weight: 4000,
      v_token: contract_address_const::<0x1f876e2da54266911d8a7409cba487414d318a2b6540149520bf7e2af56b93c>()
    });
    allowed_pools.append(PoolProps {
      pool_id: constants::RE7_SSTRK_POOL().into(),
      max_weight: 3000,
      v_token: contract_address_const::<0x5afdf4d18501d1d9d4664390df8c0786a6db8f28e66caa8800f1c2f51396492>()
    });
    allowed_pools.append(PoolProps {
      pool_id: constants::RE7_USDC_POOL().into(),
      max_weight: 1000,
      v_token: contract_address_const::<0xb5581d0bc94bc984cf79017d0f4b079c7e926af3d79bd92ff66fb451b340df>()
    });

    allowed_pools
  }

  fn get_settings() -> Settings {
    Settings {
      default_pool_index: 0,
      fee_percent: 1000,
      fee_receiver: constants::NOSTRA_USDC_DEBT(),
    }
  }

  fn get_borrow_settings() -> BorrowSettings {
    BorrowSettings {
      is_borrowing_allowed: false,
      min_health_factor: 10,
      target_health_factor: 20
    }
  }

  fn get_vesu_settings() -> vesuStruct {
    vesuStruct {
      singleton: IStonDispatcher{
        contract_address: constants::VESU_SINGLETON_ADDRESS(),
      },
      pool_id: contract_address_const::<0x00>().into(),
      debt: contract_address_const::<0x00>(), 
      col: constants::STRK_ADDRESS(),
      oracle: constants::ORACLE_OURS()
    }
  }

  fn deploy_vesu_vault() -> (ContractAddress, IVesuRebalDispatcher, IERC4626Dispatcher) {
    let vesu_rebal = declare("VesuRebalance").unwrap().contract_class();
    let admin = get_contract_address();
    let allowed_pools = get_allowed_pools();
    let settings = get_settings();
    let borrow_settings = get_borrow_settings();
    let vesu_settings = get_vesu_settings();
    let mut calldata: Array<felt252> = array![constants::STRK_ADDRESS().into()];
    calldata.append(admin.into());
    allowed_pools.serialize(ref calldata);
    settings.serialize(ref calldata);
    borrow_settings.serialize(ref calldata);
    vesu_settings.serialize(ref calldata);

    let (address, _) = vesu_rebal.deploy(@calldata).expect('Vesu vault deploy failed');

    (address, IVesuRebalDispatcher {contract_address: address}, IERC4626Dispatcher {contract_address: address} )
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
    let (vesu_address, vesu_disp, vesu_erc4626) = deploy_vesu_vault();
    assert(vesu_erc4626.asset() == constants::STRK_ADDRESS(), 'invalid asset');
    assert(vesu_disp.get_previous_index() == get_prev_const(), 'invalid prev val');
  }

  #[test]
  #[fork("mainnet_latest")]
  fn test_vesu_deposit() {
    let amount = 1000 * pow::ten_pow(18);
    let this = get_contract_address();
    let mut vesu_settings = get_vesu_settings(); 
    vault_init(amount * 100);

    let (vesu_address, vesu_vault, vesu_erc4626) = deploy_vesu_vault();
    ERC20Helper::approve(constants::STRK_ADDRESS(), vesu_address, amount);

    // first deposit
    let prev_index_before = vesu_vault.get_previous_index();
    let shares = vesu_erc4626.deposit(amount, this);
    let default_id = vesu_vault.get_settings().default_pool_index;
    let allowed_pools = vesu_vault.get_allowed_pools();
    let v_token = *allowed_pools.at(default_id.into()).v_token;
    let v_token_bal = ERC20Helper::balanceOf(v_token, vesu_address);
    let pool_assets = IERC4626Dispatcher {contract_address: v_token}
    .convert_to_assets(v_token_bal);
    assert(pool_assets == 999999999999999999999, 'invalid asset deposited');
    let prev_index_after = vesu_vault.get_previous_index();
    // assert(prev_index_after != prev_index_before, 'index not updated');
    
    // second deposit
    let amount = 500 * pow::ten_pow(18);
    ERC20Helper::approve(constants::STRK_ADDRESS(), vesu_address, amount);
    let prev_index_before = vesu_vault.get_previous_index();
    let shares = vesu_erc4626.deposit(amount, this);
    let allowed_pools = vesu_vault.get_allowed_pools();
    let v_token = *allowed_pools.at(default_id.into()).v_token;
    let v_token_bal = ERC20Helper::balanceOf(v_token, vesu_address);
    let pool_assets = IERC4626Dispatcher {contract_address: v_token}
    .convert_to_assets(v_token_bal);
    println!("pool_assets {:?}", pool_assets);
    // assert(pool_assets == 1499999999999999999998, 'invalid asset deposited');
    let prev_index_after = vesu_vault.get_previous_index();
    // assert(prev_index_after != prev_index_before, 'index not updated');
  } 

  #[test]
  #[fork("mainnet_latest")]
  fn test_vesu_withdraw() {
    let amount = 1000 * pow::ten_pow(18);
    let this = get_contract_address();
    let vesu_settings = get_vesu_settings(); 
    vault_init(amount * 100);

    let (vesu_address, vesu_vault, vesu_erc4626) = deploy_vesu_vault();
    ERC20Helper::approve(constants::STRK_ADDRESS(), vesu_address, amount);

    // genesis as default pool
    let _ = vesu_erc4626.deposit(amount, this);
    // change default pool 
    let new_settings = Settings {
      default_pool_index: 1,
      fee_percent: 1000,
      fee_receiver: constants::NOSTRA_USDC_DEBT(),
    };
    vesu_vault.set_settings(new_settings);
    assert(vesu_vault.get_settings().default_pool_index == 1, 'invalid index set');

    // deposit to new default pool
    let amount = 500 * pow::ten_pow(18);
    ERC20Helper::approve(constants::STRK_ADDRESS(), vesu_address, amount);
    let _ = vesu_erc4626.deposit(amount, this);

    let default_pool_index = vesu_vault.get_settings().default_pool_index;
    let default_pool_token = *vesu_vault.get_allowed_pools().at(default_pool_index.into()).v_token;
    let assets = vesu_erc4626.convert_to_shares(amount);
    let assets_vesu = IERC4626Dispatcher {contract_address: default_pool_token}
    .convert_to_shares(assets);
    assert(ERC20Helper::balanceOf(default_pool_token, vesu_address) == assets_vesu, 'invalid balance before');
    // try and withdraw 1400 strk...should withdraw from default pool and remaining from other pools
    let withdraw_amount = 1400 * pow::ten_pow(18);
    let strk_amount_before = ERC20Helper::balanceOf(vesu_erc4626.asset(), this);
    let _ = vesu_erc4626.withdraw(withdraw_amount , this, this);
    let strk_amount_after = ERC20Helper::balanceOf(vesu_erc4626.asset(), this);

    // curr default pool is allowed_pools_array[1] with bal -> 499999999999999999999
    // then flow moves to index 0 with bal -> 999999999999999999999
    // so bal of default pool should be 0 to withdraw 1400 tokens
    
    assert(ERC20Helper::balanceOf(default_pool_token, vesu_address) == 0, 'invalid balance after');

    // 0th pool in allowed_pools_array[0] with bal 999999999999999999999 should now 
    // have 10000000000000000000 bal 

    let remaining_assets = 1500 * pow::ten_pow(18) - withdraw_amount;
    let zeroth_pool_token = *vesu_vault.get_allowed_pools().at(0).v_token;
    let assets = vesu_erc4626.convert_to_shares(remaining_assets);
    let assets_vesu = IERC4626Dispatcher {contract_address: zeroth_pool_token}
    .convert_to_shares(assets);
    let adjust_pow = pow::ten_pow(4); 
    let comparable_bal = ERC20Helper::balanceOf(zeroth_pool_token, vesu_address) / adjust_pow;
    let comparable_shares = assets_vesu / adjust_pow;
    assert(comparable_bal == comparable_shares, 'invalid balance ');
    assert(strk_amount_after - strk_amount_before == withdraw_amount, 'invalid asset');
  }

  #[test]
  #[fork("mainnet_latest")]
  fn test_vesu_rebalance_action() {
    let amount = 5000 * pow::ten_pow(18);
    let this = get_contract_address();
    let vesu_settings = get_vesu_settings(); 
    vault_init(amount * 100);

    let (vesu_address, vesu_vault, vesu_erc4626) = deploy_vesu_vault();
    ERC20Helper::approve(constants::STRK_ADDRESS(), vesu_address, amount);
    let allowed_pools = get_allowed_pools();

    // genesis as default pool
    println!("DEPOSIT TO GENESIS POOL");
    println!("");
    let _ = vesu_erc4626.deposit(amount, this);
    // change default pool 
    let new_settings = Settings {
      default_pool_index: 3,
      fee_percent: 1000,
      fee_receiver: constants::NOSTRA_USDC_DEBT(),
    };
    vesu_vault.set_settings(new_settings);
    assert(vesu_vault.get_settings().default_pool_index == 3, 'invalid index set');

    // deposit to new default pool
    println!("DEPOSIT TO RE7 USDC POOL");
    println!("");
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
    println!("REBALANCE START");
    println!("");

    vesu_vault.rebalance(actions);

    let allowed_pools = get_allowed_pools();
    let mut i = 0;
    loop {
      if i == allowed_pools.len() {
        break;
      }
      let v_token_bal = ERC20Helper::balanceOf(*allowed_pools.at(i).v_token, vesu_address);
      let assets = IERC4626Dispatcher {contract_address: *allowed_pools.at(i).v_token}
      .convert_to_assets(v_token_bal);
      println!("strk per pool {:?}", assets);
      i += 1;
    }
  }

  #[test]
  #[should_panic(expected: ('Insufficient yield',))]
  #[fork("mainnet_latest")]
  fn test_vesu_rebalance_should_fail() {
    let amount = 1000 * pow::ten_pow(18);
    let this = get_contract_address();
    let vesu_settings = get_vesu_settings(); 
    vault_init(amount * 100);

    let (vesu_address, vesu_vault, vesu_erc4626) = deploy_vesu_vault();
    ERC20Helper::approve(constants::STRK_ADDRESS(), vesu_address, amount);
    let allowed_pools = get_allowed_pools();

    // genesis as default pool
    println!("DEPOSIT TO GENESIS POOL");
    println!("");
    let _ = vesu_erc4626.deposit(amount, this);

    // change default pool 
    let new_settings = Settings {
      default_pool_index: 1,
      fee_percent: 1000,
      fee_receiver: constants::NOSTRA_USDC_DEBT(),
    };
    vesu_vault.set_settings(new_settings);
    assert(vesu_vault.get_settings().default_pool_index == 1, 'invalid index set');

    // deposit to new default pool
    println!("DEPOSIT TO RE7 XSTRK POOL");
    println!("");
    let amount = 2000 * pow::ten_pow(18);
    ERC20Helper::approve(constants::STRK_ADDRESS(), vesu_address, amount);
    let _ = vesu_erc4626.deposit(amount, this);

    // change default pool 
    let new_settings = Settings {
      default_pool_index: 2,
      fee_percent: 1000,
      fee_receiver: constants::NOSTRA_USDC_DEBT(),
    };
    vesu_vault.set_settings(new_settings);
    assert(vesu_vault.get_settings().default_pool_index == 2, 'invalid index set');

    // deposit to new default pool
    println!("DEPOSIT TO RE7 SSTRK POOL");
    println!("");
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
    println!("REBALANCE START");
    println!("");
 
    vesu_vault.rebalance(actions);
  }

  #[test]
  #[should_panic(expected: ('Max weight exceede',))]
  #[fork("mainnet_latest")]
  fn test_vesu_rebalance_should_fail_weights() {
    let amount = 5000 * pow::ten_pow(18);
    let this = get_contract_address();
    let vesu_settings = get_vesu_settings(); 
    vault_init(amount * 100);

    let (vesu_address, vesu_vault, vesu_erc4626) = deploy_vesu_vault();
    ERC20Helper::approve(constants::STRK_ADDRESS(), vesu_address, amount);
    let allowed_pools = get_allowed_pools();

    // genesis as default pool
    println!("DEPOSIT TO GENESIS POOL");
    println!("");
    let _ = vesu_erc4626.deposit(amount, this);
    // change default pool 
    let new_settings = Settings {
      default_pool_index: 3,
      fee_percent: 1000,
      fee_receiver: constants::NOSTRA_USDC_DEBT(),
    };
    vesu_vault.set_settings(new_settings);
    assert(vesu_vault.get_settings().default_pool_index == 3, 'invalid index set');

    // deposit to new default pool
    println!("DEPOSIT TO RE7 USDC POOL");
    println!("");
    let amount = 1000 * pow::ten_pow(18);
    ERC20Helper::approve(constants::STRK_ADDRESS(), vesu_address, amount);
    let _ = vesu_erc4626.deposit(amount, this);

    let mut actions: Array<Action> = array![]; 
    // Action 1 
    let action1 = Action {
      pool_id: constants::VESU_GENESIS_POOL().into(),
      feature: Feature::WITHDRAW,
      token: constants::STRK_ADDRESS(),
      amount: 1500 * pow::ten_pow(18)
    };
    actions.append(action1);

    let action2 = Action {
      pool_id: constants::RE7_SSTRK_POOL().into(),
      feature: Feature::WITHDRAW,
      token: constants::STRK_ADDRESS(),
      amount: 1500 * pow::ten_pow(18)
    };
    actions.append(action2);

    let action3 = Action {
      pool_id: constants::RE7_XSTRK_POOL().into(),
      feature: Feature::DEPOSIT,
      token: constants::STRK_ADDRESS(),
      amount: 3000 * pow::ten_pow(18)
    };
    actions.append(action3);

    let allowed_pools = get_allowed_pools();
    let mut i = 0;
    loop {
      if i == allowed_pools.len() {
        break;
      }
      let v_token_bal = ERC20Helper::balanceOf(*allowed_pools.at(i).v_token, vesu_address);
      let assets = IERC4626Dispatcher {contract_address: *allowed_pools.at(i).v_token}
      .convert_to_assets(v_token_bal);
      println!("strk per pool {:?}", assets);
      i += 1;
    };

    // REBALANCE START
    println!("REBALANCE START");
    println!("");
 
    vesu_vault.rebalance(actions);

  }
}