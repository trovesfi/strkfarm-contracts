#[cfg(test)]
pub mod test_cl_vault {
  use strkfarm_contracts::strategies::cl_vault::interface::{IClVaultDispatcher, IClVaultDispatcherTrait, FeeSettings};
  use snforge_std::{
    declare, ContractClassTrait, start_cheat_caller_address, stop_cheat_caller_address,
    stop_cheat_block_timestamp_global, CheatSpan, start_cheat_block_timestamp, 
    stop_cheat_block_timestamp, cheat_caller_address, start_cheat_block_timestamp_global,
    start_cheat_block_number_global, stop_cheat_block_number_global
  };
  use snforge_std::{BlockId, BlockTag, replace_bytecode, DeclareResultTrait};
  use starknet::{ContractAddress, get_block_timestamp, get_contract_address, class_hash::class_hash_const, SyscallResult, SyscallResultTrait};
  use strkfarm_contracts::helpers::constants;
  use strkfarm_contracts::strategies::cl_vault::interface::ClSettings;
  use strkfarm_contracts::components::ekuboSwap::{
    EkuboSwapStruct, ekuboSwapImpl
  };
  use openzeppelin::token::erc721::interface::{ERC721ABIDispatcher, ERC721ABIDispatcherTrait};
  use strkfarm_contracts::helpers::ERC20Helper;
  use strkfarm_contracts::interfaces::IEkuboCore::{IEkuboCoreDispatcher, IEkuboCoreDispatcherTrait, Bounds, PoolKey, PositionKey};
  use strkfarm_contracts::interfaces::IEkuboPositionsNFT::{IEkuboNFTDispatcher, IEkuboNFTDispatcherTrait};
  use strkfarm_contracts::interfaces::IEkuboPosition::{IEkuboDispatcher, IEkuboDispatcherTrait};
  use ekubo::interfaces::core::{ICoreDispatcher, ICoreDispatcherTrait};
  use strkfarm_contracts::components::ekuboSwap::{IRouterDispatcher, IRouterDispatcherTrait};
  use ekubo::types::i129::{i129};
  use starknet::contract_address::contract_address_const;
  use openzeppelin::utils::serde::SerializedAppend;
  use strkfarm_contracts::helpers::pow;
  use strkfarm_contracts::interfaces::ERC4626Strategy::Settings;
  use openzeppelin::access::ownable::interface::{IOwnableDispatcher, IOwnableDispatcherTrait}; 
  use strkfarm_contracts::components::swap::{AvnuMultiRouteSwap, Route};
  use strkfarm_contracts::components::swap::{get_swap_params};
  use strkfarm_contracts::interfaces::oracle::{IPriceOracle, IPriceOracleDispatcher, IPriceOracleDispatcherTrait, PriceWithUpdateTime};
  use openzeppelin::token::erc20::interface::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};
  // use avnu::exchange::IExchangeDispatcherTrait;
  use strkfarm_contracts::helpers::safe_decimal_math;

  fn get_bounds() -> Bounds {
    let bounds = Bounds {
      lower: i129 {
          mag: 160000,   
          sign: false,
      },
      upper: i129 {
          mag: 180000,   
          sign: false,        
      },
  };

    bounds
  }

  fn get_bounds_xstrk() -> Bounds {
    let bounds = Bounds {
      lower: i129 {
          mag: 16000,   
          sign: false,
      },
      upper: i129 {
          mag: 16600,
          sign: false,        
      },
  };

    bounds
  } 

  fn get_ekubo_settings() -> EkuboSwapStruct {
    let nostraSettings = EkuboSwapStruct {
      core: ICoreDispatcher {contract_address: constants::EKUBO_CORE()},
      router: IRouterDispatcher {contract_address: constants::EKUBO_ROUTER()}
    };

    nostraSettings
  }

  fn get_eth_wst_route () -> Route  {
    let sqrt_limit: felt252 = 0;
    let pool_key = get_pool_key();
    let additional: Array<felt252> = array![
      pool_key.token0.into(), // token0
      pool_key.token1.into(), // token1
      pool_key.fee.into(), // fee
      pool_key.tick_spacing.into(), // tick space
      pool_key.extension.into(), // extension
      sqrt_limit, // sqrt limit
    ];
    Route {
        token_from: constants::ETH_ADDRESS(),
        token_to: constants::WST_ADDRESS(),
        exchange_address: constants::EKUBO_CORE(),
        percent: 0, // doesnt matter
        additional_swap_params: additional
    }
  }

  fn get_wst_eth_route () -> Route  {
    let sqrt_limit: felt252 = 362433397725560428311005821073602714129;
    let pool_key = get_pool_key();
    let additional: Array<felt252> = array![
      pool_key.token0.into(), // token0
      pool_key.token1.into(), // token1
      pool_key.fee.into(), // fee
      pool_key.tick_spacing.into(), // tick space
      pool_key.extension.into(), // extension
      sqrt_limit, // sqrt limit
    ];
    Route {
        token_from: constants::WST_ADDRESS(),
        token_to: constants::ETH_ADDRESS(),
        exchange_address: constants::EKUBO_CORE(),
        percent: 0, // doesnt matter
        additional_swap_params: additional
    }
  }

  fn get_strk_xstrk_route () -> Route  {
    let sqrt_limit: felt252 = 0;

    let additional: Array<felt252> = array![
        constants::XSTRK_ADDRESS().into(), // token0
        constants::STRK_ADDRESS().into(), // token1
        34028236692093847977029636859101184, // fee
        200, // tick space
        0, // extension
        sqrt_limit, // sqrt limit
    ];
    Route {
        token_from: constants::STRK_ADDRESS(),
        token_to: constants::XSTRK_ADDRESS(),
        exchange_address: constants::EKUBO_CORE(),
        percent: 0, // doesnt matter
        additional_swap_params: additional
    }
  }

  fn get_xstrk_strk_route () -> Route  {
    let sqrt_limit: felt252 = 0;

    let additional: Array<felt252> = array![
        constants::XSTRK_ADDRESS().into(), // token0
        constants::STRK_ADDRESS().into(), // token1
        34028236692093847977029636859101184, // fee
        200, // tick space
        0, // extension
        sqrt_limit, // sqrt limit
    ];
    Route {
        token_from: constants::XSTRK_ADDRESS(),
        token_to: constants::STRK_ADDRESS(),
        exchange_address: constants::EKUBO_CORE(),
        percent: 0, // doesnt matter
        additional_swap_params: additional
    }
  }

  fn get_harvest_settings() -> Settings {
    let settings = Settings {
      rewardsContract: contract_address_const::<0x00>(),
      lendClassHash: class_hash_const::<0x00>(),
      swapClassHash: class_hash_const::<0x00>()
    };

    settings
  }

  fn get_pool_key_xstrk() -> PoolKey{
    let poolkey = PoolKey {
      token0: constants::XSTRK_ADDRESS(),
      token1: constants::STRK_ADDRESS(),
      fee: 34028236692093847977029636859101184,
      tick_spacing: 200,
      extension: contract_address_const::<0x00>()
    };

    poolkey
  }

  fn get_pool_key() -> PoolKey {
    let poolkey = PoolKey {
      token0: constants::WST_ADDRESS(),
      token1: constants::ETH_ADDRESS(),
      fee: 34028236692093847977029636859101184,
      tick_spacing: 200,
      extension: contract_address_const::<0x00>()
    };

    poolkey
  }

  // fn deploy_avnu() {
  //   let avnu = declare("Exchange").unwrap().contract_class();
  //   let this = get_contract_address();
  //   let mut calldata: Array<felt252> = array![this.into(), this.into()];
  //   let (address, _) = avnu.deploy_at(@calldata, strkfarm::helpers::constants::AVNU_EX()).expect('Avnu deploy failed');
    
  //   let ekubo_ch = declare("EkuboAdapter").unwrap().contract_class();
  //   avnu::exchange::IExchangeDispatcher {
  //     contract_address: address
  //   }.set_adapter_class_hash(constants::EKUBO_CORE(), *ekubo_ch.class_hash);
  // }

  fn ekubo_swap(route: Route, from_token: ContractAddress, to_token: ContractAddress, from_amount: u256) {
    let ekubo = get_ekubo_settings();
    let mut route_array = ArrayTrait::<Route>::new();
    route_array.append(route); 
    let swap_params = get_swap_params(
      from_token: from_token,
      from_amount: from_amount,
      to_token: to_token,
      to_amount: 0,
      to_min_amount: 0,
      routes: route_array
    );
    ekubo.swap(
      swap_params
    );
  } 

  fn deploy_cl_vault() -> ( IClVaultDispatcher, ERC20ABIDispatcher ) {
    let clVault = declare("ConcLiquidityVault").unwrap().contract_class();
    let admin = get_contract_address();
    let poolkey = get_pool_key();
    let bounds = get_bounds();
    let fee_bps = 1000;
    let name: ByteArray = "uCL_token";
    let symbol: ByteArray = "UCL";
    let mut calldata: Array<felt252> = array![];
    calldata.append_serde(name);
    calldata.append_serde(symbol);
    calldata.append(admin.into());
    calldata.append(constants::EKUBO_POSITIONS().into());
    calldata.append_serde(bounds);
    calldata.append_serde(poolkey);
    calldata.append(constants::EKUBO_POSITIONS_NFT().into());
    calldata.append(constants::EKUBO_CORE().into());
    calldata.append(constants::ORACLE_OURS().into());
    let fee_settings = FeeSettings {
      fee_bps: fee_bps,
      fee_collector: contract_address_const::<0x123>()
    };
    fee_settings.serialize(ref calldata);
    let (address, _) = clVault.deploy(@calldata).expect('ClVault deploy failed');
    
    return (
      IClVaultDispatcher {contract_address: address}, 
      ERC20ABIDispatcher {contract_address: address}, 
    );
  }

  fn deploy_cl_vault_xstrk() -> ( IClVaultDispatcher, ERC20ABIDispatcher ) {
    let clVault = declare("ConcLiquidityVault").unwrap().contract_class();
    let admin = get_contract_address();
    let poolkey = get_pool_key_xstrk();
    let bounds = get_bounds_xstrk();
    let strk_xstrk_route = get_strk_xstrk_route();
    let xstrk_strk_route = get_xstrk_strk_route();
    let mut strk_xstrk_routeArray = ArrayTrait::<Route>::new();
    let mut xstrk_strk_routeArray = ArrayTrait::<Route>::new();
    strk_xstrk_routeArray.append(strk_xstrk_route);
    xstrk_strk_routeArray.append(xstrk_strk_route);
    let fee_bps = 1000;
    let name: ByteArray = "uCL_token";
    let symbol: ByteArray = "UCL";
    let mut calldata: Array<felt252> = array![];
    calldata.append_serde(name);
    calldata.append_serde(symbol);
    calldata.append(admin.into());
    calldata.append(constants::EKUBO_POSITIONS().into());
    calldata.append_serde(bounds);
    calldata.append_serde(poolkey);
    calldata.append(constants::EKUBO_POSITIONS_NFT().into());
    calldata.append(constants::EKUBO_CORE().into());
    calldata.append(constants::ORACLE_OURS().into());
    let fee_settings = FeeSettings {
      fee_bps: fee_bps,
      fee_collector: contract_address_const::<0x123>()
    };
    fee_settings.serialize(ref calldata);
    let (address, _) = clVault.deploy(@calldata).expect('ClVault deploy failed');
    
    return (
      IClVaultDispatcher {contract_address: address}, 
      ERC20ABIDispatcher {contract_address: address}, 
    );
  }

  fn vault_init(amount: u256) {
    let ekubo_user = constants::EKUBO_USER_ADDRESS();
    let this: ContractAddress = get_contract_address();
    println!("vault_init:this: {:?}", this);
    start_cheat_caller_address(constants::ETH_ADDRESS(), ekubo_user);
    ERC20Helper::transfer(constants::ETH_ADDRESS(), this, amount);
    stop_cheat_caller_address(constants::ETH_ADDRESS());
    let bal = ERC20Helper::balanceOf(constants::ETH_ADDRESS(), this);
    println!("1balance {:?}", bal);
    println!("amount {:?}", amount);

    start_cheat_caller_address(constants::WST_ADDRESS(), ekubo_user);
    ERC20Helper::transfer(constants::WST_ADDRESS(), this, amount);
    stop_cheat_caller_address(constants::WST_ADDRESS());
    let bal = ERC20Helper::balanceOf(constants::WST_ADDRESS(), this);
    println!("2balance {:?}", bal);
    println!("amount {:?}", amount);
  }

  fn vault_init_xstrk_pool(amount: u256) {
    let ekubo_user = constants::VESU_SINGLETON_ADDRESS();
    let this: ContractAddress = get_contract_address();

    start_cheat_caller_address(constants::STRK_ADDRESS(), ekubo_user);
    ERC20Helper::transfer(constants::STRK_ADDRESS(), this, amount);
    stop_cheat_caller_address(constants::STRK_ADDRESS());
    start_cheat_caller_address(constants::XSTRK_ADDRESS(), ekubo_user);
    ERC20Helper::transfer(constants::XSTRK_ADDRESS(), this, amount);
    stop_cheat_caller_address(constants::XSTRK_ADDRESS());
  }

  #[test]
  #[fork("mainnet_1134787")]
  fn test_clVault_constructer() {
    let (clVault, erc20Disp) = deploy_cl_vault();
    let settings: ClSettings = clVault.get_settings();
    assert(settings.ekubo_positions_contract == constants::EKUBO_POSITIONS(), 'invalid ekubo positions');
    assert(settings.ekubo_positions_nft == constants::EKUBO_POSITIONS_NFT(), 'invalid ekubo positions nft');
    assert(settings.ekubo_core == constants::EKUBO_CORE(), 'invalid ekubo core');
    assert(settings.oracle == constants::ORACLE_OURS(), 'invalid pragma oracle');
    assert(clVault.total_liquidity() == 0, 'invalid total supply');

    assert(erc20Disp.name() == "uCL_token", 'invalid name');
    assert(erc20Disp.symbol() == "UCL", 'invalid symbol');
    assert(erc20Disp.decimals() == 18, 'invalid decimals');
    assert(erc20Disp.total_supply() == 0, 'invalid total supply');
  }

  // PASSED
  #[test]
  #[fork("mainnet_1134787")]
  fn test_ekubo_deposit() {
    let amount = 10 * pow::ten_pow(18);
    let this = get_contract_address();
    println!("this: {:?}", this);

    // approve the necessary tokens linked with liquidity to be created 
    let (clVault, _) = deploy_cl_vault();
    assert(clVault.get_settings().contract_nft_id == 0, 'nft id not zero on deploy');
    vault_init(amount);
    ERC20Helper::approve(constants::ETH_ADDRESS(), clVault.contract_address, amount * 2);
    ERC20Helper::approve(constants::WST_ADDRESS(), clVault.contract_address, amount * 2);
    println!("clVault.contract_address: {:?}", clVault.contract_address);

    // deposit once
    let shares1 = clVault.deposit(amount, amount, this);
    assert(shares1 > 0, 'invalid shares minted');
    let settings: ClSettings = clVault.get_settings();
    let nft_id: u64 = settings.contract_nft_id;
    let nft_id_u256: u256 = nft_id.into();
    let nft_disp = IEkuboNFTDispatcher{contract_address: settings.ekubo_positions_nft};
    println!("nft_id: {:?}", nft_id);

    // assert correct NFT ID, and ensure all balance is used
    assert(nft_disp.ownerOf(nft_id_u256) == clVault.contract_address, 'invalid owner');
    assert(ERC20Helper::balanceOf(constants::ETH_ADDRESS(), clVault.contract_address) == 0, 'invalid ETH amount');
    assert(ERC20Helper::balanceOf(constants::WST_ADDRESS(), clVault.contract_address) == 0, 'invalid WST amount');
    println!("checked balances");

    // assert for near equal values
    let cl_shares_bal = ERC20Helper::balanceOf(clVault.contract_address, this);
    let total_liquidity: u256 = clVault.get_position().liquidity.into();
    println!("cl_shares_bal: {:?}", cl_shares_bal);
    println!("total_liquidity: {:?}", total_liquidity);
    assert((cl_shares_bal) == (total_liquidity), 'invalid shares minted');
    
    // deposit again
    vault_init(amount);
    let shares2 = clVault.deposit(amount, amount, this);
    assert(shares2 > 0, 'invalid shares minted');
    let settings: ClSettings = clVault.get_settings();
    assert(nft_id == settings.contract_nft_id, 'nft id not constant');
    assert(ERC20Helper::balanceOf(constants::ETH_ADDRESS(), clVault.contract_address) == 0, 'invalid ETH amount');
    assert(ERC20Helper::balanceOf(constants::WST_ADDRESS(), clVault.contract_address) == 0, 'invalid WST amount');
    
    // assert for near equal values
    let cl_shares_bal = ERC20Helper::balanceOf(clVault.contract_address, this);
    let total_liquidity: u256 = clVault.get_position().liquidity.into();
    println!("cl_shares_bal: {:?}", cl_shares_bal);
    println!("total_liquidity: {:?}", total_liquidity);
    assert((cl_shares_bal / pow::ten_pow(3)) == (total_liquidity / pow::ten_pow(3)), 'invalid shares minted');
  } 

  //WITHDRAW TESTS 
  // PASSED
  #[test]
  #[fork("mainnet_1134787")]
  fn test_ekubo_withdraw() {
    let assets: u256 = 100000000000000000000;
    let amount = 10 * pow::ten_pow(18);
    
    let this = get_contract_address();
    let (clVault, _) = deploy_cl_vault();
    ERC20Helper::approve(constants::ETH_ADDRESS(), clVault.contract_address, amount * 2);
    ERC20Helper::approve(constants::WST_ADDRESS(), clVault.contract_address, amount * 2);
    vault_init(amount);

    //deposit
    let shares = clVault.deposit(amount, amount, this);
    assert(shares > 0, 'invalid shares minted');
    let position = clVault.get_position();
    let liquidity_256: u256 = position.liquidity.into();
    let vault_shares = ERC20Helper::balanceOf(clVault.contract_address, this);
    assert(liquidity_256 == vault_shares, 'invalid liquidity');
    assert(shares == vault_shares, 'invalid liquidity');

    let eth_before_withdraw = ERC20Helper::balanceOf(constants::ETH_ADDRESS(), this);
    let wst_before_withdraw = ERC20Helper::balanceOf(constants::WST_ADDRESS(), this);

    //withdraw partial 
    assert(ERC20Helper::balanceOf(constants::ETH_ADDRESS(), clVault.contract_address) == 0, 'invalid token bal');
    assert(ERC20Helper::balanceOf(constants::WST_ADDRESS(), clVault.contract_address) == 0, 'invalid token bal');
    let withdraw_amount = liquidity_256 / 2;
    clVault.withdraw(withdraw_amount, this);

    let shares_bal = ERC20Helper::balanceOf(clVault.contract_address, this);
    assert(shares_bal == (shares - withdraw_amount), 'invalid shares minted');
    let partial_eth_bal = ERC20Helper::balanceOf(constants::ETH_ADDRESS(), this);
    let partial_wst_bal = ERC20Helper::balanceOf(constants::WST_ADDRESS(), this);
    assert(partial_eth_bal > eth_before_withdraw, 'eth not withdrawn');
    assert(partial_wst_bal > wst_before_withdraw, 'wst not withdrawn');
    let liquidity_256_after_withdraw: u256 = clVault.get_position().liquidity.into();
    assert(liquidity_256_after_withdraw == (liquidity_256 - withdraw_amount), 'invalid liquidity removed');
    assert(ERC20Helper::balanceOf(constants::ETH_ADDRESS(), clVault.contract_address) == 0, 'invalid token bal');
    assert(ERC20Helper::balanceOf(constants::WST_ADDRESS(), clVault.contract_address) == 0, 'invalid token bal');

    //withdraw full
    let shares_left = ERC20Helper::balanceOf(clVault.contract_address, this);
    clVault.withdraw(shares_left, this);
    let liquidity_left = clVault.get_position().liquidity;
    let neg_liq = liquidity_left / 1000;
    assert(neg_liq == 0, 'liquidity not 0');
    assert(clVault.get_settings().contract_nft_id == 0, 'nft id not 0');
    let total_eth_bal = ERC20Helper::balanceOf(constants::ETH_ADDRESS(), this);
    let total_wst_bal = ERC20Helper::balanceOf(constants::WST_ADDRESS(), this);
    assert(total_eth_bal > partial_eth_bal, 'total eth not withdrawn');
    assert(total_wst_bal > partial_wst_bal, 'total wst eth not withdrawn');
    assert(ERC20Helper::balanceOf(constants::ETH_ADDRESS(), clVault.contract_address) == 0, 'invalid token bal');
    assert(ERC20Helper::balanceOf(constants::WST_ADDRESS(), clVault.contract_address) == 0, 'invalid token bal');
  
    let shares_bal = ERC20Helper::balanceOf(clVault.contract_address, this);
    assert(shares_bal == 0, 'invalid shares minted');
  }

  #[test]
  #[fork("mainnet_1134787")]
  fn test_handle_fees() {
    let amount = 10 * pow::ten_pow(18);
    vault_init(amount * 2);
    
    let this = get_contract_address();
    let (clVault, _) = deploy_cl_vault();
    ERC20Helper::approve(constants::ETH_ADDRESS(), clVault.contract_address, amount);
    ERC20Helper::approve(constants::WST_ADDRESS(), clVault.contract_address, amount);

    //deposit
    let _ = clVault.deposit(amount, amount, this);

    // check if function works with 0 fees
    let liquidity_before_fees = clVault.get_position().liquidity;
    clVault.handle_fees();
    let liquidity_after_fees = clVault.get_position().liquidity;
    assert(liquidity_after_fees == liquidity_before_fees, 'invalid liquidity');    
    println!("first handle fee passed");

    let pool_price_before = IEkuboDispatcher {contract_address: constants::EKUBO_POSITIONS()}.
    get_pool_price(get_pool_key()).tick.mag;

    let eth_route = get_eth_wst_route();   
    ekubo_swap(eth_route, constants::ETH_ADDRESS(), constants::WST_ADDRESS(), 1000000000000000000);
    println!("first swap passed");

    let wst_route = get_wst_eth_route();
    ekubo_swap(wst_route, constants::WST_ADDRESS(), constants::ETH_ADDRESS(), 400000000000000000);
    println!("second swap passed");

    let wst_route = get_wst_eth_route();
    ekubo_swap(wst_route, constants::WST_ADDRESS(), constants::ETH_ADDRESS(), 300000000000000000);
    println!("third swap passed");

    let eth_route = get_eth_wst_route();   
    ekubo_swap(eth_route, constants::ETH_ADDRESS(), constants::WST_ADDRESS(), 100000000000000000);
    println!("fourth swap passed");

    let eth_route = get_eth_wst_route();   
    ekubo_swap(eth_route, constants::ETH_ADDRESS(), constants::WST_ADDRESS(), 200000000000000000);
    println!("fifth swap passed");

    let pool_price_after = IEkuboDispatcher {contract_address: constants::EKUBO_POSITIONS()}.
    get_pool_price(get_pool_key()).tick.mag;

    println!("pool price before: {:?}", pool_price_before);
    println!("pool price after: {:?}", pool_price_after);
    assert(pool_price_before != pool_price_after, 'invalid swap pool');

    //call handle fees and check how much fees was generated from collect fees
    let liquidity_before_fees = clVault.get_position().liquidity;
    clVault.handle_fees();
    let liquidity_after_fees = clVault.get_position().liquidity;

    assert(liquidity_after_fees > liquidity_before_fees, 'invalid liquidity');

    let bal0 = ERC20Helper::balanceOf(constants::ETH_ADDRESS(), clVault.contract_address);
    let bal1 = ERC20Helper::balanceOf(constants::WST_ADDRESS(), clVault.contract_address);
    println!("bal0: {:?}", bal0);
    println!("bal1: {:?}", bal1);
  }

  #[test]
  #[fork("mainnet_1134787")]
  fn test_ekubo_rebalance() {
    let amount = 10 * pow::ten_pow(18);
    // deploy_avnu();
    vault_init(amount);
    
    let this = get_contract_address();
    let (clVault, _) = deploy_cl_vault();
    ERC20Helper::approve(constants::ETH_ADDRESS(), clVault.contract_address, amount);
    ERC20Helper::approve(constants::WST_ADDRESS(), clVault.contract_address, amount);

    let _ = clVault.deposit(amount, amount, this);
    println!("deposit passed");
    let old_bounds = clVault.get_settings().bounds_settings;

    // new bounds
    let new_lower_bound: u128 = 169000;
    let new_upper_bound: u128 = 180000;
    let bounds = Bounds {
      lower: i129 {
        mag: new_lower_bound,
        sign: false
      },
      upper: i129 {
        mag: new_upper_bound,
        sign: false
      }
    };
    println!("new bounds ready");

    // compute total dollar value before rebalance
    let token_info_before_rebal = IEkuboDispatcher {contract_address: constants::EKUBO_POSITIONS()}.get_token_info(
      clVault.get_settings().contract_nft_id,
      get_pool_key(),
      get_bounds()
    );
    let oracle_disp = IPriceOracleDispatcher {contract_address: constants::ORACLE_OURS()};
    println!("token0_price:");
    let token0_price: u128 = oracle_disp.get_price(constants::WST_ADDRESS()).try_into().unwrap();
    println!("token0_price: {:?}", token0_price);
    let token1_price: u128 = oracle_disp.get_price(constants::ETH_ADDRESS()).try_into().unwrap();
    let total_dollar = (token0_price * token_info_before_rebal.amount0) + (token1_price * token_info_before_rebal.amount1);
    println!("dollar val before rebal {:?}", total_dollar);

    // rebalance
    println!("cl vault: {:?}", clVault.contract_address);
    let mut eth_route = get_eth_wst_route();
    eth_route.percent = 1000000000000;
    let pool_key = get_pool_key();
    let additional: Array<felt252> = array![
      pool_key.token0.into(), // token0
      pool_key.token1.into(), // token1
      pool_key.fee.into(), // fee
      pool_key.tick_spacing.into(), // tick space
      pool_key.extension.into(), // extension
      pow::ten_pow(70).try_into().unwrap(), // sqrt limit
    ];
    eth_route.additional_swap_params = additional;
    let routes: Array<Route> = array![eth_route.clone()];
    let swap_params = AvnuMultiRouteSwap {
        token_from_address: eth_route.clone().token_from,
        // got amont from trail and error 
        token_from_amount: 1701 * pow::ten_pow(18) / 1000,
        token_to_address: eth_route.token_to,
        token_to_amount: 0,
        token_to_min_amount: 0,
        beneficiary: clVault.contract_address,
        integrator_fee_amount_bps: 0,
        integrator_fee_recipient: contract_address_const::<0x00>(),
        routes
    };
    clVault.rebalance(bounds, swap_params);

    // assert total usd value is roughly same after rebalance
    let token_info_after_rebal = IEkuboDispatcher {contract_address: constants::EKUBO_POSITIONS()}.get_token_info(
      clVault.get_settings().contract_nft_id,
      get_pool_key(),
      bounds
    );
    println!("token 0 in info {:?}", token_info_after_rebal.amount0);
    println!("token 1 in info {:?}", token_info_after_rebal.amount1);
    let token0_price: u128 = oracle_disp.get_price(constants::WST_ADDRESS()).try_into().unwrap();
    let token1_price: u128 = oracle_disp.get_price(constants::ETH_ADDRESS()).try_into().unwrap();
    let total_dollar2 = (token0_price * token_info_after_rebal.amount0) + (token1_price * token_info_after_rebal.amount1);
    println!("dollar val after rebal {:?}", total_dollar2);
    
    // assert bounds are updated and current liquidity > 0
    let liquidity_after_rebalance = clVault.get_position().liquidity;
    assert(liquidity_after_rebalance > 0, 'invalid liquidity');
    let bounds = clVault.get_settings().bounds_settings;
    assert(bounds.lower.mag == new_lower_bound, 'invalid bound written');
    assert(bounds.upper.mag == new_upper_bound, 'invalid bound written');


    // assert that old bounds have 0 liquidity
    let position_key = PositionKey {
      salt: clVault.get_settings().contract_nft_id,
      owner: constants::EKUBO_POSITIONS(),
      bounds: old_bounds
    };
    let pos_old_bounds = IEkuboCoreDispatcher {contract_address: constants::EKUBO_CORE()}
    .get_position(
      clVault.get_settings().pool_key,
      position_key
    );
    assert(pos_old_bounds.liquidity == 0, 'Invalid liquidity rebalanced');
  }

  #[test]
  #[fork("mainnet_1134787")]
  fn test_strk_xstrk_pool() {
    let assets: u256 = 100000000000000000000;
    let amount = 500000 * pow::ten_pow(18);
    vault_init_xstrk_pool(amount * 3);

    let this = get_contract_address();
    let (clVault, _) = deploy_cl_vault_xstrk();
    ERC20Helper::approve(constants::STRK_ADDRESS(), clVault.contract_address, amount);
    ERC20Helper::approve(constants::XSTRK_ADDRESS(), clVault.contract_address, amount);

    let _ = clVault.deposit(amount, amount, this);
    let settings: ClSettings = clVault.get_settings();
    let nft_id: u64 = settings.contract_nft_id;
    let nft_id_u256: u256 = nft_id.into();
    let nft_disp = IEkuboNFTDispatcher{contract_address: settings.ekubo_positions_nft};
    
    // assert correct NFT ID, and ensure all balance is used
    assert(nft_disp.ownerOf(nft_id_u256) == clVault.contract_address, 'invalid owner');
    assert(ERC20Helper::balanceOf(constants::STRK_ADDRESS(), clVault.contract_address) == 0, 'invalid ETH amount');
    assert(ERC20Helper::balanceOf(constants::XSTRK_ADDRESS(), clVault.contract_address) == 0, 'invalid WST amount');

    let strk_bal = ERC20Helper::balanceOf(constants::STRK_ADDRESS(), this);
    let xstrk_bal = ERC20Helper::balanceOf(constants::XSTRK_ADDRESS(), this);
    println!("strk bal before swap {:?}", strk_bal);
    println!("xstrk bal before swap {:?}", xstrk_bal);

    let pool_price_before = IEkuboDispatcher {contract_address: constants::EKUBO_POSITIONS()}.
    get_pool_price(get_pool_key_xstrk()).tick.mag;

    let mut x = 1;
    loop {
      x += 1;
      let eth_route = get_strk_xstrk_route();   
      ekubo_swap(eth_route, constants::STRK_ADDRESS(), constants::XSTRK_ADDRESS(), 5000000000000000000000);

      let wst_route = get_xstrk_strk_route();
      ekubo_swap(wst_route, constants::XSTRK_ADDRESS(), constants::STRK_ADDRESS(), 500000000000000000000);
      if x == 50 {
        break;
      }
    };

    let strk_bal = ERC20Helper::balanceOf(constants::STRK_ADDRESS(), this);
    let xstrk_bal = ERC20Helper::balanceOf(constants::XSTRK_ADDRESS(), this);
    println!("strk bal before swap {:?}", strk_bal);
    println!("xstrk bal before swap {:?}", xstrk_bal);

    let pool_price_after = IEkuboDispatcher {contract_address: constants::EKUBO_POSITIONS()}.
    get_pool_price(get_pool_key_xstrk()).tick.mag;

    assert(pool_price_before != pool_price_after, 'invalid swap pool');

    //call handle fees and check how much fees was generated from collect fees
    let liquidity_before_fees = clVault.get_position().liquidity;
    clVault.handle_fees();
    let liquidity_after_fees = clVault.get_position().liquidity;

    assert(liquidity_after_fees >= liquidity_before_fees, 'invalid liquidity');

    let strk_before_withdraw = ERC20Helper::balanceOf(constants::STRK_ADDRESS(), this);
    let xstrk_before_withdraw = ERC20Helper::balanceOf(constants::XSTRK_ADDRESS(), this);
    println!("strk bal before withdraw {:?}", strk_before_withdraw);
    println!("xstrk bal before withdraw {:?}", xstrk_before_withdraw);

    //withdraw partial 
    println!("withdraw partial");
    let all_shares = ERC20Helper::balanceOf(clVault.contract_address, this);
    println!("all shares {:?}", all_shares);
    let withdraw_amount: u256 = all_shares / 2;
    clVault.withdraw(withdraw_amount, this);

    let partial_strk_bal = ERC20Helper::balanceOf(constants::STRK_ADDRESS(), this);
    let partial_xstrk_bal = ERC20Helper::balanceOf(constants::XSTRK_ADDRESS(), this);
    println!("partial strk bal after withdraw {:?}", partial_strk_bal);
    println!("partial xstrk bal after withdraw {:?}", partial_xstrk_bal);
    assert(partial_strk_bal > strk_before_withdraw, 'strk not withdrawn');
    assert(partial_xstrk_bal > xstrk_before_withdraw, 'xstrk not withdrawn');
    let vault_bal0 = ERC20Helper::balanceOf(constants::STRK_ADDRESS(), clVault.contract_address);
    let vault_bal1 = ERC20Helper::balanceOf(constants::XSTRK_ADDRESS(), clVault.contract_address);
    println!("vault bal0: {:?}", vault_bal0);
    println!("vault bal1: {:?}", vault_bal1);
    assert(safe_decimal_math::is_under_by_percent_bps(vault_bal0, amount, 1), 'invalid token bal');
    assert(safe_decimal_math::is_under_by_percent_bps(vault_bal1, amount, 1), 'invalid token bal');

    //withdraw full
    println!("withdraw full");
    let shares_left = ERC20Helper::balanceOf(clVault.contract_address, this);
    clVault.withdraw(shares_left, this);
    let total_strk_bal = ERC20Helper::balanceOf(constants::STRK_ADDRESS(), this);
    let total_xstrk_bal = ERC20Helper::balanceOf(constants::XSTRK_ADDRESS(), this);
    assert(total_strk_bal > partial_strk_bal, 'total eth not withdrawn');
    assert(total_xstrk_bal > partial_xstrk_bal, 'total wst eth not withdrawn');
    let vault_bal0 = ERC20Helper::balanceOf(constants::STRK_ADDRESS(), clVault.contract_address);
    let vault_bal1 = ERC20Helper::balanceOf(constants::XSTRK_ADDRESS(), clVault.contract_address);
    println!("vault bal0: {:?}", vault_bal0);
    println!("vault bal1: {:?}", vault_bal1);
    assert(safe_decimal_math::is_under_by_percent_bps(vault_bal0, amount, 1), 'invalid token bal');
    assert(safe_decimal_math::is_under_by_percent_bps(vault_bal1, amount, 1), 'invalid token bal');
  }
}