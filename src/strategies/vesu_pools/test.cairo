#[cfg(test)]
pub mod test_vesu_pools {
    use snforge_std::{
        declare, ContractClassTrait, start_cheat_caller_address, stop_cheat_caller_address,
        start_cheat_block_number_global, start_cheat_block_timestamp_global,
        stop_cheat_block_number_global, DeclareResultTrait
    };
    use starknet::{
        contract_address::{contract_address_const, ContractAddress},
        {get_contract_address, get_caller_address}
    };
    use strkfarm_contracts::helpers::{constants, ERC20Helper, pow};
    use strkfarm_contracts::strategies::vesu_pools::interface::
    {
        ICustomAssetsDispatcher,
        ICustomAssetsDispatcherTrait,
        UnderlyingTokens,
        VTokenParams,
        PragmaOracleParams,
        LiquidationParams,
        ShutdownParams,
        FeeParams,
        IDefaultExtensionDispatcher, 
        IDefaultExtensionDispatcherTrait, 
        IDefaultExtensionCallbackDispatcher, 
        IDefaultExtensionCallbackDispatcherTrait
    }; 
    use vesu::{
        data_model::{
            Amount, UnsignedAmount, AssetParams, AssetPrice, LTVParams, Context, LTVConfig, ModifyPositionParams,
            AmountDenomination, AmountType, DebtCapParams
        },
        extension::{
            interface::{
                IExtensionDispatcher, IExtensionDispatcherTrait
            },
            components::{
                interest_rate_model::InterestRateConfig,
            },
        },
        singleton::{ISingletonDispatcher, ISingletonDispatcherTrait},
        vendor::pragma::AggregationMode
    };
    use openzeppelin::utils::serde::SerializedAppend;
    use alexandria_math::i257::{i257, I257Trait};

    fn deploy_vesu_extension() -> (ContractAddress, IDefaultExtensionDispatcher) {
        let vesu_extension = declare("DefaultExtensionPO").unwrap().contract_class();
        let v_token_hash = *declare("VToken").unwrap().contract_class().class_hash;
        let mut calldata: Array<felt252> = array![];
        calldata.append(constants::VESU_SINGLETON_ADDRESS().into());
        calldata.append(constants::PRAGMA_ORACLE().into());
        calldata.append(constants::PRAGMA_SUMMARY().into());
        calldata.append(v_token_hash.into());
        // let mut custom_assets: Array<ContractAddress> = array![];
        // custom_assets.append(constants::EKUBO_STRK_XSTRK_ADDRESS());
        // custom_assets.serialize(ref calldata);
        // let mut underlying_assets: Array<UnderlyingTokens> = array![];
        // let assets = UnderlyingTokens {
        //     asset1: constants::STRK_ADDRESS(),
        //     asset2: constants::XSTRK_ADDRESS()
        // };
        // underlying_assets.append(assets);
        // underlying_assets.serialize(ref calldata);
        let (address, _) = vesu_extension.deploy(@calldata).expect('vesu extension fail');

        return (
            address,
            IDefaultExtensionDispatcher {contract_address: address}
        );
    }

    fn get_pool_name() -> felt252 {
        'strkfarm pool'
    }

    fn get_asset() -> AssetParams {
        AssetParams {
            asset: contract_address_const::<0x00>(),
            floor: 0,
            initial_rate_accumulator: 0, 
            initial_full_utilization_rate: 0, 
            max_utilization: 0, 
            is_legacy: false,
            fee_rate: 0
        }
    }

    fn get_v_token() -> VTokenParams {
        VTokenParams {
            v_token_name: 'test1name',
            v_token_symbol: 'test1symbol'
        }
    }

    fn get_ltv() -> LTVParams {
        LTVParams {
            collateral_asset_index: 0,
            debt_asset_index: 0,
            max_ltv: 1
        }
    }

    fn get_interest_rate() -> InterestRateConfig {
        InterestRateConfig {
            min_target_utilization: 0, 
            max_target_utilization: 0, // [utilization-scale]
            target_utilization: 0, // [utilization-scale]
            min_full_utilization_rate: 0, // [SCALE]
            max_full_utilization_rate: 0, // [SCALE]
            zero_utilization_rate: 0, // [SCALE]
            rate_half_life: 0, // [seconds]
            target_rate_percent: 0, // [SCALE]
        }
    }

    fn get_pragma_oracle_params() -> PragmaOracleParams {
        PragmaOracleParams {
            pragma_key: '0x00',
            timeout: 0, // [seconds]
            number_of_sources: 1,
            start_time_offset: 1, // [seconds]
            time_window: 1, // [seconds]
            aggregation_mode: AggregationMode::Mean // [seconds]
        }
    }

    fn get_liquidation_params() -> LiquidationParams {
        LiquidationParams {
            collateral_asset_index: 0,
            debt_asset_index: 0,
            liquidation_factor: 1 // [SCALE]
        }
    }

    fn get_debt_cap_params() -> DebtCapParams {
        DebtCapParams {
            collateral_asset_index: 0,
            debt_asset_index: 0,
            debt_cap: 0, // [SCALE]
        }
    }

    fn get_asset_params() -> Span<AssetParams> {
        let mut asset_params: Array<AssetParams> = array![];
        let mut param1 = get_asset();
        // make changes to param1
        param1.asset = constants::STRK_ADDRESS();
        param1.floor = 100000000000000000000;
        param1.initial_rate_accumulator = 1000000000000000000;
        param1.initial_full_utilization_rate = 5861675589;
        param1.max_utilization = 920000000000000000;
        param1.fee_rate = 0;
        asset_params.append(param1);

        let mut param2 = get_asset();
        //make changes to param
        param2.asset = constants::XSTRK_ADDRESS();
        param2.floor = 100000000000000000000;
        param2.initial_rate_accumulator = 1000000000000000000;
        param2.initial_full_utilization_rate = 5861675589;
        param2.max_utilization = 920000000000000000;
        param2.fee_rate = 0;
        asset_params.append(param2);

        let mut param3 = get_asset();
        //make changes to param
        param3.asset = constants::EKUBO_STRK_XSTRK_ADDRESS();
        param3.floor = 100000000000000000000;
        param3.initial_rate_accumulator = 1000000000000000000;
        param3.initial_full_utilization_rate = 5861675589;
        param3.max_utilization = 920000000000000000;
        param3.fee_rate = 0;
        asset_params.append(param3);

        asset_params.span()
    }

    fn get_v_token_params() -> Span<VTokenParams> {
        let mut v_token_params: Array<VTokenParams> = array![];
        let mut param1 = get_v_token();
        // make changes to param1
        param1.v_token_name = 'vesuFarmSTRK';
        param1.v_token_symbol = 'vsSTRK';
        v_token_params.append(param1);

        let mut param2 = get_v_token();
        //make changes to param2
        param2.v_token_name = 'vesuFarmxSTRK';
        param2.v_token_symbol = 'vsxSTRK';
        v_token_params.append(param2);

        let mut param3 = get_v_token();
        //make changes to param
        param3.v_token_name = 'vesuFarmEkuboxSTRK';
        param3.v_token_symbol = 'vsExSTRK';
        v_token_params.append(param3);

        v_token_params.span()
    }

    fn get_ltv_params() -> Span<LTVParams> {
        let mut ltv_params: Array<LTVParams> = array![];
        let mut param1 = get_ltv();
        //make changes to param1
        param1.collateral_asset_index = 0;
        param1.debt_asset_index = 1;
        param1.max_ltv = 870000000000000000;
        ltv_params.append(param1);

        let mut param2 = get_ltv();
        //make changes to param2
        param2.collateral_asset_index = 1;
        param2.debt_asset_index = 0;
        param2.max_ltv = 800000000000000000;
        ltv_params.append(param2);

        let mut param3 = get_ltv();
        //make changes to param3
        param3.collateral_asset_index = 2;
        param3.debt_asset_index = 0;
        param3.max_ltv = 850000000000000000;
        ltv_params.append(param3);

        let mut param4 = get_ltv();
        //make changes to param4
        param4.collateral_asset_index = 2;
        param4.debt_asset_index = 1;
        param4.max_ltv = 850000000000000000;
        ltv_params.append(param4);

        let mut param5 = get_ltv();
        //make changes to param5
        param5.collateral_asset_index = 0;
        param5.debt_asset_index = 2;
        param5.max_ltv = 0;
        ltv_params.append(param5);

        let mut param6 = get_ltv();
        //make changes to param5
        param6.collateral_asset_index = 1;
        param6.debt_asset_index = 2;
        param6.max_ltv = 0;
        ltv_params.append(param6);

        ltv_params.span()
    }

    fn get_interest_rate_config() -> Span<InterestRateConfig> {
        let mut interest_rate_config: Array<InterestRateConfig> = array![];
        let mut param1 = get_interest_rate();
        // make changes to param1 [STRK]
        param1.min_target_utilization = 88000; 
        param1.max_target_utilization = 92000; 
        param1.target_utilization = 90000; 
        param1.min_full_utilization_rate = 13035786672; 
        param1.max_full_utilization_rate = 44569649971; 
        param1.zero_utilization_rate = 32134073; 
        param1.rate_half_life = 432000; 
        param1.target_rate_percent = 200000000000000000; 
        interest_rate_config.append(param1);

        let mut param2 = get_interest_rate();
        //make changes to param2 [xSTRK]
        param2.min_target_utilization = 88000; 
        param2.max_target_utilization = 92000; 
        param2.target_utilization = 90000; 
        param2.min_full_utilization_rate = 13035786672; 
        param2.max_full_utilization_rate = 44569649971; 
        param2.zero_utilization_rate = 32134073; 
        param2.rate_half_life = 432000; 
        param2.target_rate_percent = 200000000000000000;
        interest_rate_config.append(param2);

        let mut param3 = get_interest_rate();
        //make changes to param3 [Ekubo xSTRK/STRK]
        param3.min_target_utilization = 88000; 
        param3.max_target_utilization = 92000; 
        param3.target_utilization = 90000; 
        param3.min_full_utilization_rate = 13035786672; 
        param3.max_full_utilization_rate = 44569649971; 
        param3.zero_utilization_rate = 32134073; 
        param3.rate_half_life = 432000; 
        param3.target_rate_percent = 200000000000000000;
        interest_rate_config.append(param3);

        interest_rate_config.span()
    }

    fn get_pragma_oracle_params_config() -> Span<PragmaOracleParams> {
        let mut pragma_oracle_params: Array<PragmaOracleParams> = array![];
        let mut param1 = get_pragma_oracle_params();
        // make changes to param1
        param1.pragma_key = 6004514686061859652;
        param1.timeout = 0;
        param1.number_of_sources = 1;
        param1.start_time_offset = 0;
        param1.time_window = 0;
        param1.aggregation_mode = AggregationMode::Mean;
        pragma_oracle_params.append(param1);
    
        let mut param2 = get_pragma_oracle_params();
        // make changes to param2 
        param2.pragma_key = 6004514686061859652;
        param2.timeout = 0;
        param2.number_of_sources = 1;
        param2.start_time_offset = 0;
        param2.time_window = 0;
        param2.aggregation_mode = AggregationMode::Median;
        pragma_oracle_params.append(param2);
    
        let mut param3 = get_pragma_oracle_params();
        // make changes to param3 
        param3.pragma_key = 6004514686061859652;
        param3.timeout = 0;
        param3.number_of_sources = 1;
        param3.start_time_offset = 0;
        param3.time_window = 0;
        param3.aggregation_mode = AggregationMode::Median;
        pragma_oracle_params.append(param3);
    
        pragma_oracle_params.span()
    }

    fn get_liquidation_params_config() -> Span<LiquidationParams> {
        let mut liquidation_params: Array<LiquidationParams> = array![];
        let mut param1 = get_liquidation_params();
        // make changes to param1
        param1.collateral_asset_index = 1;
        param1.debt_asset_index = 0;
        param1.liquidation_factor = 900000000000000000;
        liquidation_params.append(param1);
    
        let mut param2 = get_liquidation_params();
        // make changes to param2 if needed
        param2.collateral_asset_index = 2;
        param2.debt_asset_index = 0;
        param2.liquidation_factor = 900000000000000000;
        liquidation_params.append(param2);
    
        liquidation_params.span()
    }

    fn get_debt_cap_params_config() -> Span<DebtCapParams> {
        let mut debt_cap_params: Array<DebtCapParams> = array![];
        let mut param1 = get_debt_cap_params();
        // make changes to param1 
        param1.collateral_asset_index = 1;
        param1.debt_asset_index = 0;
        param1.debt_cap = 10000000000000000000000000;
        debt_cap_params.append(param1);
    
        let mut param2 = get_debt_cap_params();
        // make changes to param2 
        param2.collateral_asset_index = 2;
        param2.debt_asset_index = 0;
        param2.debt_cap = 10000000000000000000000000;
        debt_cap_params.append(param2);
    
        debt_cap_params.span()
    }

    fn get_params() -> ModifyPositionParams {
        let this = get_contract_address();
        ModifyPositionParams {
            pool_id: 'test_pool_id',
            collateral_asset: contract_address_const::<0x00>(),
            debt_asset: contract_address_const::<0x00>(),
            user: this,
            collateral: Amount {
                amount_type: AmountType::Delta,
                denomination: AmountDenomination::Assets,
                value: I257Trait::new(0, is_negative: false)
            },
            debt: Amount {
                amount_type: AmountType::Delta,
                denomination: AmountDenomination::Assets,
                value: I257Trait::new(0, is_negative: false)
            },
            data: array![0].span()
        }
    }

    fn fund_contract() {
        let strk_user = constants::VESU_SINGLETON_ADDRESS();
        let ekubo_strk_xstrk_user = constants::EKUBO_STRK_XSTRK_USER();
        let ekubo_amount = 7000000 * pow::ten_pow(18);
        let amount = 10000 * pow::ten_pow(18);
        let this = get_contract_address();
        // fund strk
        start_cheat_caller_address(constants::STRK_ADDRESS(), strk_user);
        ERC20Helper::transfer(constants::STRK_ADDRESS(), this, amount);
        stop_cheat_caller_address(constants::STRK_ADDRESS());
        // fund xstrk
        start_cheat_caller_address(constants::XSTRK_ADDRESS(), strk_user);
        ERC20Helper::transfer(constants::XSTRK_ADDRESS(), this, amount);
        stop_cheat_caller_address(constants::XSTRK_ADDRESS());
        // fund ekubo strk xstrk
        start_cheat_caller_address(constants::EKUBO_STRK_XSTRK_ADDRESS(), ekubo_strk_xstrk_user);
        ERC20Helper::transfer(constants::EKUBO_STRK_XSTRK_ADDRESS(), this, ekubo_amount);
        stop_cheat_caller_address(constants::EKUBO_STRK_XSTRK_ADDRESS());
    }

    fn create_pool(extension_address: ContractAddress, extension_disp: IDefaultExtensionDispatcher) -> felt252 {
        let name = get_pool_name();
        let asset_params = get_asset_params();
        let add = asset_params.at(0).asset;
        let add1 = asset_params.at(1).asset;
        let add2 = asset_params.at(2).asset;
        let v_token_params = get_v_token_params();
        let ltv_params = get_ltv_params();
        let interest_rate_configs = get_interest_rate_config();
        let pragma_oracle_configs = get_pragma_oracle_params_config();
        let liquidation_params = get_liquidation_params_config();
        let debt_caps = get_debt_cap_params_config();
        let shutdown_params = ShutdownParams {
            recovery_period: 0,
            subscription_period: 0, 
            ltv_params: get_ltv_params()
        };
        let fee_params = FeeParams {
            fee_recipient: get_contract_address()
        };

        fund_contract();
        
        ERC20Helper::approve(*add, extension_address, 100000000000);
        ERC20Helper::approve(*add1, extension_address, 100000000000);
        ERC20Helper::approve(*add2, extension_address, 100000000000);

        let pool_id = extension_disp
            .create_pool(
                name,
                asset_params,
                v_token_params,
                ltv_params,
                interest_rate_configs,
                pragma_oracle_configs,
                liquidation_params,
                debt_caps,
                shutdown_params,
                fee_params,
                get_contract_address()
            );

        ICustomAssetsDispatcher {contract_address: extension_address}.set_custom_asset(pool_id, constants::EKUBO_STRK_XSTRK_ADDRESS());
        assert(ICustomAssetsDispatcher {contract_address: extension_address}.is_custom_asset(constants::EKUBO_STRK_XSTRK_ADDRESS()) == true, 'invalid bool');
        ICustomAssetsDispatcher {contract_address: extension_address}.set_underlying_assets(
            pool_id,
            constants::EKUBO_STRK_XSTRK_ADDRESS(),
            constants::STRK_ADDRESS(),
            constants::XSTRK_ADDRESS()
        );

        return pool_id;
    }

    fn deposit(
        col_asset: ContractAddress,
        debt_asset: ContractAddress,
        amount: u256,
        pool_id: felt252,
        singleton: ContractAddress
    ) {
        let mut deposit_params = get_params();
        deposit_params.pool_id = pool_id;
        deposit_params.collateral_asset = col_asset;
        deposit_params.debt_asset = debt_asset;
        let collateral = I257Trait::new(amount, is_negative: false);
        deposit_params.collateral.value = collateral;
        ERC20Helper::approve(col_asset, singleton, amount);
        ISingletonDispatcher{contract_address: singleton}.
            modify_position(deposit_params);
    }

    fn borrow(
        col_asset: ContractAddress,
        debt_asset: ContractAddress,
        amount: u256,
        pool_id: felt252,
        singleton: ContractAddress
    ) {
        let mut borrow_params = get_params();
        borrow_params.pool_id = pool_id;
        borrow_params.collateral_asset = col_asset;
        borrow_params.debt_asset = debt_asset;
        let debt = I257Trait::new(amount, is_negative: false);
        borrow_params.debt.value = debt;
        ISingletonDispatcher{contract_address: singleton}.
            modify_position(borrow_params);
    }

    #[test]
    #[fork("mainnet_latest")]
    fn test_vesu_pools_constructor() {
        let (extension_address, extension_disp) = deploy_vesu_extension();
        let singleton = IDefaultExtensionCallbackDispatcher {contract_address: extension_address}.
            singleton();
        assert(singleton == constants::VESU_SINGLETON_ADDRESS(), 'invalid singleton');
        let oracle = extension_disp.pragma_oracle();
        assert(oracle == constants::PRAGMA_ORACLE(), 'invalid oracle address');
        let summary = extension_disp.pragma_summary();
        assert(summary == constants::PRAGMA_SUMMARY(), 'invalid summary address');
    }

    #[test]
    #[fork("mainnet_latest")]
    fn test_vesu_strk_borrow_xstrk_col() {
        let (extension_address, extension_disp) = deploy_vesu_extension();
        let pool_id = create_pool(extension_address, extension_disp);   

        println!("pool id {:?}", pool_id);

        let singleton = IDefaultExtensionCallbackDispatcher {contract_address: extension_address}.
            singleton();

        // deposit xSTRK
        let amount = 5000 * pow::ten_pow(18);
        deposit(
            constants::XSTRK_ADDRESS(),
            constants::STRK_ADDRESS(),
            amount,
            pool_id,
            singleton
        );
        println!("DEPOSITED XSTRK");

        // deposit STRK
        let amount = 5000 * pow::ten_pow(18);
        deposit(
            constants::STRK_ADDRESS(),
            constants::XSTRK_ADDRESS(),
            amount,
            pool_id,
            singleton
        );
        println!("DEPOSITED STRK");

        // borrow STRK
        let amount = 800 * pow::ten_pow(18);
        borrow(
            constants::XSTRK_ADDRESS(),
            constants::STRK_ADDRESS(),
            amount,
            pool_id,
            singleton
        );
        println!("BORROWED STRK");
    }

    #[test]
    #[fork("mainnet_latest")]
    fn test_vesu_ekubo_strk_xstrk_borrow_xstrk_col() {
        let (extension_address, extension_disp) = deploy_vesu_extension();
        let pool_id = create_pool(extension_address, extension_disp);   

        println!("pool id {:?}", pool_id);

        let singleton = IDefaultExtensionCallbackDispatcher {contract_address: extension_address}.
            singleton();
        
        // deposit ekuboSTRKxSTRK
        let amount = 6000000 * pow::ten_pow(18);   
        deposit(
            constants::EKUBO_STRK_XSTRK_ADDRESS(),
            constants::STRK_ADDRESS(),
            amount,
            pool_id,
            singleton
        );
        println!("DEPOSITED EKUBO STRK XSTRK");

        // deposit STRK
        let amount = 5000 * pow::ten_pow(18);
        deposit(
            constants::STRK_ADDRESS(),
            constants::XSTRK_ADDRESS(),
            amount,
            pool_id,
            singleton
        );
        println!("DEPOSITED STRK");

        // borrow STRK
        let amount = 800 * pow::ten_pow(18);
        borrow(
            constants::EKUBO_STRK_XSTRK_ADDRESS(),
            constants::STRK_ADDRESS(),
            amount,
            pool_id,
            singleton
        );
        println!("BORROWED STRK");
    }

    #[test]
    #[fork("mainnet_latest")]
    #[should_panic(expected: "not-collateralized")]
    fn test_vesu_strk_borrow_ekubo_strk_xstrk_col() {
        let (extension_address, extension_disp) = deploy_vesu_extension();
        let pool_id = create_pool(extension_address, extension_disp);   

        println!("pool id {:?}", pool_id);

        let singleton = IDefaultExtensionCallbackDispatcher {contract_address: extension_address}.
            singleton();

        // deposit strk
        let amount = 5000 * pow::ten_pow(18);
        deposit(
            constants::STRK_ADDRESS(),
            constants::XSTRK_ADDRESS(),
            amount,
            pool_id,
            singleton
        );
        println!("DEPOSITED STRK");
        println!("");

        // deposit ekuboSTRKxSTRK
        let amount = 6000000 * pow::ten_pow(18);
        deposit(
            constants::EKUBO_STRK_XSTRK_ADDRESS(),
            constants::STRK_ADDRESS(),
            amount,
            pool_id,
            singleton
        );
        println!("DEPOSITED EKUBO STRK XSTRK");
        println!("");

        // borrow ekuboSTRKxSTRK
        let amount = 500000 * pow::ten_pow(18);
        borrow(
            constants::STRK_ADDRESS(),
            constants::EKUBO_STRK_XSTRK_ADDRESS(),
            amount,
            pool_id,
            singleton
        );
    }

    #[test]
    #[fork("mainnet_latest")]
    #[should_panic(expected: "caller-not-owner")]
    fn test_vesu_pools_non_admin() {
        let (extension_address, extension_disp) = deploy_vesu_extension();
        let pool_id = create_pool(extension_address, extension_disp);   

        println!("pool id {:?}", pool_id);

        let strk_user = constants::VESU_SINGLETON_ADDRESS();
        start_cheat_caller_address(extension_address, strk_user);
        ICustomAssetsDispatcher {contract_address: extension_address}
            .set_custom_asset(pool_id, constants::EKUBO_STRK_XSTRK_ADDRESS());
        stop_cheat_caller_address(extension_address);
    }

    #[test]
    #[fork("mainnet_latest")]
    #[should_panic(expected: "caller-not-owner")]
    fn test_vesu_pools_custom_non_admin_() {
        let (extension_address, extension_disp) = deploy_vesu_extension();
        let pool_id = create_pool(extension_address, extension_disp);   

        println!("pool id {:?}", pool_id);

        let strk_user = constants::VESU_SINGLETON_ADDRESS();
        start_cheat_caller_address(extension_address, strk_user);
        ICustomAssetsDispatcher {contract_address: extension_address}.set_underlying_assets(
            pool_id,
            constants::EKUBO_STRK_XSTRK_ADDRESS(),
            constants::STRK_ADDRESS(),
            constants::XSTRK_ADDRESS()
        );
        stop_cheat_caller_address(extension_address);
    }

    #[test]
    #[fork("mainnet_latest")]
    fn test_vesu_pools_dollar_value() {
        let (extension_address, extension_disp) = deploy_vesu_extension();
        let pool_id = create_pool(extension_address, extension_disp);   

        println!("pool id {:?}", pool_id);

        let price = IExtensionDispatcher {contract_address: extension_address}
            .price(pool_id, constants::EKUBO_STRK_XSTRK_ADDRESS());
        println!("price {:?}", price.value);

        let price = IExtensionDispatcher {contract_address: extension_address}
            .price(pool_id, constants::STRK_ADDRESS());
        println!("price {:?}", price.value);
    }    
}

// 2295700246362289402516800
// 156524170000000000
