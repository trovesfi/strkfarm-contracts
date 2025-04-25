use alexandria_math::i257::i257;
use starknet::ContractAddress;
use vesu::{
    data_model::{AssetParams, LTVParams, LTVConfig, DebtCapParams},
    extension::components::{
        interest_rate_model::InterestRateConfig,
        position_hooks::{ShutdownMode, ShutdownStatus, ShutdownConfig, LiquidationConfig, Pair}, fee_model::FeeConfig,
        pragma_oracle::OracleConfig,
    },
    vendor::pragma::{AggregationMode}
};

#[derive(PartialEq, Copy, Drop, Serde)]
struct VTokenParams {
    v_token_name: felt252,
    v_token_symbol: felt252
}

#[derive(PartialEq, Copy, Drop, Serde)]
struct PragmaOracleParams {
    pragma_key: felt252,
    timeout: u64, // [seconds]
    number_of_sources: u32,
    start_time_offset: u64, // [seconds]
    time_window: u64, // [seconds]
    aggregation_mode: AggregationMode
}

#[derive(PartialEq, Copy, Drop, Serde)]
struct ShutdownParams {
    recovery_period: u64, // [seconds]
    subscription_period: u64, // [seconds]
    ltv_params: Span<LTVParams>,
}

#[derive(PartialEq, Copy, Drop, Serde)]
struct LiquidationParams {
    collateral_asset_index: usize,
    debt_asset_index: usize,
    liquidation_factor: u64 // [SCALE]
}

#[derive(PartialEq, Copy, Drop, Serde)]
struct FeeParams {
    fee_recipient: ContractAddress
}

#[starknet::interface]
trait IDefaultExtensionCallback<TContractState> {
    fn singleton(self: @TContractState) -> ContractAddress;
}

#[starknet::interface]
trait ITimestampManagerCallback<TContractState> {
    fn contains(self: @TContractState, pool_id: felt252, item: u64) -> bool;
    fn push_front(ref self: TContractState, pool_id: felt252, item: u64);
    fn remove(ref self: TContractState, pool_id: felt252, item: u64);
    fn first(self: @TContractState, pool_id: felt252) -> u64;
    fn last(self: @TContractState, pool_id: felt252) -> u64;
    fn previous(self: @TContractState, pool_id: felt252, item: u64) -> u64;
    fn all(self: @TContractState, pool_id: felt252) -> Array<u64>;
}

#[starknet::interface]
trait ITokenizationCallback<TContractState> {
    fn v_token_for_collateral_asset(
        self: @TContractState, pool_id: felt252, collateral_asset: ContractAddress
    ) -> ContractAddress;
    fn mint_or_burn_v_token(
        ref self: TContractState,
        pool_id: felt252,
        collateral_asset: ContractAddress,
        user: ContractAddress,
        amount: i257
    );
}

#[starknet::interface]
trait IDefaultExtension<TContractState> {
    fn pool_name(self: @TContractState, pool_id: felt252) -> felt252;
    fn pool_owner(self: @TContractState, pool_id: felt252) -> ContractAddress;
    fn pragma_oracle(self: @TContractState) -> ContractAddress;
    fn pragma_summary(self: @TContractState) -> ContractAddress;
    fn oracle_config(self: @TContractState, pool_id: felt252, asset: ContractAddress) -> OracleConfig;
    fn fee_config(self: @TContractState, pool_id: felt252) -> FeeConfig;
    fn debt_caps(
        self: @TContractState, pool_id: felt252, collateral_asset: ContractAddress, debt_asset: ContractAddress
    ) -> u256;
    fn interest_rate_config(self: @TContractState, pool_id: felt252, asset: ContractAddress) -> InterestRateConfig;
    fn liquidation_config(
        self: @TContractState, pool_id: felt252, collateral_asset: ContractAddress, debt_asset: ContractAddress
    ) -> LiquidationConfig;
    fn shutdown_config(self: @TContractState, pool_id: felt252) -> ShutdownConfig;
    fn shutdown_ltv_config(
        self: @TContractState, pool_id: felt252, collateral_asset: ContractAddress, debt_asset: ContractAddress
    ) -> LTVConfig;
    fn shutdown_status(
        self: @TContractState, pool_id: felt252, collateral_asset: ContractAddress, debt_asset: ContractAddress
    ) -> ShutdownStatus;
    fn pairs(
        self: @TContractState, pool_id: felt252, collateral_asset: ContractAddress, debt_asset: ContractAddress
    ) -> Pair;
    fn violation_timestamp_for_pair(
        self: @TContractState, pool_id: felt252, collateral_asset: ContractAddress, debt_asset: ContractAddress
    ) -> u64;
    fn violation_timestamp_count(self: @TContractState, pool_id: felt252, violation_timestamp: u64) -> u128;
    fn oldest_violation_timestamp(self: @TContractState, pool_id: felt252) -> u64;
    fn next_violation_timestamp(self: @TContractState, pool_id: felt252, violation_timestamp: u64) -> u64;
    fn v_token_for_collateral_asset(
        self: @TContractState, pool_id: felt252, collateral_asset: ContractAddress
    ) -> ContractAddress;
    fn collateral_asset_for_v_token(
        self: @TContractState, pool_id: felt252, v_token: ContractAddress
    ) -> ContractAddress;
    fn create_pool(
        ref self: TContractState,
        name: felt252,
        asset_params: Span<AssetParams>,
        v_token_params: Span<VTokenParams>,
        ltv_params: Span<LTVParams>,
        interest_rate_configs: Span<InterestRateConfig>,
        pragma_oracle_params: Span<PragmaOracleParams>,
        liquidation_params: Span<LiquidationParams>,
        debt_caps: Span<DebtCapParams>,
        shutdown_params: ShutdownParams,
        fee_params: FeeParams,
        owner: ContractAddress
    ) -> felt252;
    fn add_asset(
        ref self: TContractState,
        pool_id: felt252,
        asset_params: AssetParams,
        v_token_params: VTokenParams,
        interest_rate_config: InterestRateConfig,
        pragma_oracle_params: PragmaOracleParams
    );
    fn set_asset_parameter(
        ref self: TContractState, pool_id: felt252, asset: ContractAddress, parameter: felt252, value: u256
    );
    fn set_debt_cap(
        ref self: TContractState,
        pool_id: felt252,
        collateral_asset: ContractAddress,
        debt_asset: ContractAddress,
        debt_cap: u256
    );
    fn set_interest_rate_parameter(
        ref self: TContractState, pool_id: felt252, asset: ContractAddress, parameter: felt252, value: u256
    );
    fn set_oracle_parameter(
        ref self: TContractState, pool_id: felt252, asset: ContractAddress, parameter: felt252, value: felt252
    );
    fn set_liquidation_config(
        ref self: TContractState,
        pool_id: felt252,
        collateral_asset: ContractAddress,
        debt_asset: ContractAddress,
        liquidation_config: LiquidationConfig
    );
    fn set_ltv_config(
        ref self: TContractState,
        pool_id: felt252,
        collateral_asset: ContractAddress,
        debt_asset: ContractAddress,
        ltv_config: LTVConfig
    );
    fn set_shutdown_config(ref self: TContractState, pool_id: felt252, shutdown_config: ShutdownConfig);
    fn set_shutdown_ltv_config(
        ref self: TContractState,
        pool_id: felt252,
        collateral_asset: ContractAddress,
        debt_asset: ContractAddress,
        shutdown_ltv_config: LTVConfig
    );
    fn set_shutdown_mode(ref self: TContractState, pool_id: felt252, shutdown_mode: ShutdownMode);
    fn set_extension(ref self: TContractState, pool_id: felt252, extension: ContractAddress);
    fn set_pool_owner(ref self: TContractState, pool_id: felt252, owner: ContractAddress);
    fn update_shutdown_status(
        ref self: TContractState, pool_id: felt252, collateral_asset: ContractAddress, debt_asset: ContractAddress
    ) -> ShutdownMode;
    fn set_fee_config(ref self: TContractState, pool_id: felt252, fee_config: FeeConfig);
    fn claim_fees(ref self: TContractState, pool_id: felt252, collateral_asset: ContractAddress);
}