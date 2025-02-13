#[starknet::contract]
mod VesuRebalance {
  use starknet::{ContractAddress, get_contract_address};
  use strkfarm_contracts::helpers::ERC20Helper;
  use strkfarm_contracts::components::common::CommonComp;
  use strkfarm_contracts::components::vesu::{vesuStruct, vesuToken, vesuSettingsImpl};
  use strkfarm_contracts::interfaces::IVesu::{
    IStonDispatcher, IStonDispatcherTrait,
    IVesuExtensionDispatcher, IVesuExtensionDispatcherTrait
  };
  use strkfarm_contracts::helpers::pow;
  use strkfarm_contracts::interfaces::IERC4626::{IERC4626, IERC4626Dispatcher, IERC4626DispatcherTrait};
  use openzeppelin::security::pausable::{PausableComponent};
  use openzeppelin::upgrades::upgradeable::UpgradeableComponent;
  use openzeppelin::security::reentrancyguard::{ReentrancyGuardComponent};
  use openzeppelin::access::ownable::ownable::OwnableComponent;
  use openzeppelin::introspection::src5::SRC5Component;
  use openzeppelin::token::erc20::{
    ERC20Component,
    ERC20HooksEmptyImpl
  };
  use strkfarm_contracts::components::erc4626::{ERC4626Component};
  use strkfarm_contracts::components::erc4626::ERC4626Component::{FeeConfigTrait, LimitConfigTrait, ERC4626HooksTrait, ImmutableConfig};
  use alexandria_storage::list::{List, ListTrait};

  component!(path: ERC4626Component, storage: erc4626, event: ERC4626Event);
  component!(path: ERC20Component, storage: erc20, event: ERC20Event);
  component!(path: SRC5Component, storage: src5, event: SRC5Event);
  component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);
  component!(path: ReentrancyGuardComponent, storage: reng, event: ReentrancyGuardEvent);
  component!(path: UpgradeableComponent, storage: upgradeable, event: UpgradeableEvent);
  component!(path: PausableComponent, storage: pausable, event: PausableEvent);
  component!(path: CommonComp, storage: common, event: CommonCompEvent);

  // #[abi(embed_v0)]
  // impl ERC4626Impl = ERC4626Component::ERC4626Impl<ContractState>;
  // #[abi(embed_v0)]
  // impl ERC4626DefaultNoFees = ERC4626Component::FeeConfigTrait<ContractState>;
  // #[abi(embed_v0)]
  // impl ERC4626DefaultLimits = ERC4626Component::LimitConfigTrait<ContractState>;
  #[abi(embed_v0)]
  impl ERC20Impl = ERC20Component::ERC20Impl<ContractState>;
  #[abi(embed_v0)]
  impl CommonCompImpl = CommonComp::CommonImpl<ContractState>;

  impl CommonInternalImpl = CommonComp::InternalImpl<ContractState>;
  impl ERC4626InternalImpl = ERC4626Component::InternalImpl<ContractState>;
  impl ERC20InternalImpl = ERC20Component::InternalImpl<ContractState>;
  impl ReentrancyGuardInternalImpl = ReentrancyGuardComponent::InternalImpl<ContractState>;

  use strkfarm_contracts::strategies::vesu_rebalance::interface::{IVesuRebal, Action, Feature, BorrowSettings, PoolProps, Settings};

  pub mod Errors {
    pub const INVALID_YIELD: felt252 = 'Insufficient yield';
    pub const UNUTILIZED_ASSET: felt252 = 'Unutilized asset in vault';
    pub const MAX_WEIGHT_EXCEEDED: felt252 = 'Max weight exceeded';
    pub const BORROWING_ENABLED: felt252 = 'Borrowing is enabled';
    pub const V_TOKEN_BAL_ZERO: felt252 = 'Vault vToken bal zero';
    pub const FEE_CANNOT_BE_ZERO: felt252 = 'Fee cannot be zero';
    pub const INVALID_POOL_LENGTH: felt252 = 'Invalid pool length';
  }

  #[storage]
  struct Storage {
    #[substorage(v0)]
    reng: ReentrancyGuardComponent::Storage,
    #[substorage(v0)] 
    erc4626: ERC4626Component::Storage,
    #[substorage(v0)]
    erc20: ERC20Component::Storage,
    #[substorage(v0)]
    src5: SRC5Component::Storage,
    #[substorage(v0)]
    ownable: OwnableComponent::Storage,
    #[substorage(v0)]
    upgradeable: UpgradeableComponent::Storage,
    #[substorage(v0)]
    pausable: PausableComponent::Storage,
    #[substorage(v0)]
    common: CommonComp::Storage,

    allowed_pools: List<PoolProps>,
    settings: Settings,
    previous_index: u128,
    borrow_settings: BorrowSettings,
    vesu_settings: vesuStruct,
  }

  #[event]
  #[derive(Drop, starknet::Event)]
  enum Event {
    #[flat]
    ReentrancyGuardEvent: ReentrancyGuardComponent::Event,
    #[flat]
    ERC4626Event: ERC4626Component::Event,
    #[flat]
    ERC20Event: ERC20Component::Event,
    #[flat]
    SRC5Event: SRC5Component::Event,
    #[flat]
    OwnableEvent: OwnableComponent::Event,
    #[flat]
    UpgradeableEvent: UpgradeableComponent::Event,
    #[flat]
    PausableEvent: PausableComponent::Event,
    #[flat]
    CommonCompEvent: CommonComp::Event,
    Rebalance: Rebalance,
    CollectFees: CollectFees
  }
  
  // @audit these all u32 (all yield values u32)
  #[derive(Drop, starknet::Event)]
  pub struct Rebalance {
    yield_before: u256,
    yield_after: u256, 
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
    asset: ContractAddress,
    owner: ContractAddress,
    allowed_pools: Array<PoolProps>,
    settings: Settings,
    borrow_settings: BorrowSettings,
    vesu_settings: vesuStruct,
  ) {
    self.erc4626.initializer(asset);
    self.common.initializer(owner);   
    self.set_allowed_pools(allowed_pools);
    // @audit modified constructor to directly take Settings struct
    self.set_settings(settings);
    self.set_borrow_settings(borrow_settings);
    self.vesu_settings.write(vesu_settings);

    // default index 10**18 (i.e. 1)
    self.previous_index.write(DEFAULT_INDEX);
  }

  //task at hand 
  //write asserts 
  //fix akira audit issues

  #[abi(embed_v0)]
  impl ExternalImpl of IVesuRebal<ContractState> {
    /// @notice Rebalances users position in vesu to optimize yield 
    /// @dev This function computes the yield before and after rebalancing, collects fees, 
    /// executes rebalancing actions, and performs post-rebalance validations.
    /// @param actions Array of actions to be performed for rebalancing
    fn rebalance(ref self: ContractState, actions: Array<Action>) {
      // perform rebalance
      let (yield_before_rebalance, _ ) = self.compute_yield();
      self._collect_fees();
      self._rebal_loop(actions);
      let (yield_after_rebalance, total_amount) = self.compute_yield();

      // post rebalance validations
      let this = get_contract_address();
      assert(yield_after_rebalance > yield_before_rebalance, Errors::INVALID_YIELD);
      assert(ERC20Helper::balanceOf(self.asset(), this) == 0, Errors::UNUTILIZED_ASSET);
      self._assert_hf();
      self._assert_max_weights(total_amount);

      self.emit(
        Rebalance {
          yield_before: yield_before_rebalance,
          yield_after: yield_after_rebalance
        }
      );
    }

    // @notice computes overall yeild across all allowed pools
    // @dev Iterates through allowed pools, calculates yield per pool, and aggregates.
    // @return (u256, u256) - The weighted average yield and the total amount across pools. 
    fn compute_yield(self: @ContractState) -> (u256, u256) {
      let allowed_pools = self._get_pool_data();
      let mut i = 0;
      let mut yield_sum = 0;
      let mut amount_sum = 0;
      loop {
        if(i == allowed_pools.len()) {
          break;
        }
        let pool = *allowed_pools.at(i);
        let interest_curr_pool = self._interest_rate_per_pool(pool.pool_id);
        let amount_in_pool = self._calculate_amount_in_pool(pool.v_token);
        yield_sum += (interest_curr_pool * amount_in_pool);
        amount_sum += amount_in_pool;
        i += 1;
      };
      
      assert(self.borrow_settings.read().is_borrowing_allowed == false, Errors::BORROWING_ENABLED);
      // handle borrow yeild 
      
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

    /// @notice Retrieves the borrow settings of the contract.
    /// @dev Reads and returns the borrow settings stored in the contract state.
    /// @return borrow_settings The current borrow configuration settings.
    fn get_borrow_settings(self: @ContractState) -> BorrowSettings {
      self.borrow_settings.read()
    }

    /// @notice Retrieves the previous index of the contract.
    /// @dev Reads and returns the previous index stored in the contract state.
    /// @return previous_index The current borrow configuration settings.
    fn get_previous_index(self: @ContractState) -> u128 {
      self.previous_index.read()
    }

    /// @notice Updates the contract settings.
    /// @dev Only the contract owner can call this function to modify the settings.
    /// @param settings The new settings to be stored in the contract.
    fn set_settings(
      ref self: ContractState, 
      settings: Settings
     ) {
      self.common.assert_only_owner();
      self.settings.write(settings);
    }

    /// @notice Updates the contract settings.
    /// @dev Only the contract owner can call this function to modify allowed pools.
    /// @param pools The new allowed pools to be stored in the contract.
    fn set_allowed_pools(ref self: ContractState, pools: Array<PoolProps>) {
      self.common.assert_only_owner();
      self._set_pool_settings(pools);
    }

    /// @notice Updates the contract's borrow settings.
    /// @dev Only the contract owner can call this function to modify the borrow settings.
    /// @param borrow_settings The new borrow settings to be stored in the contract.
    fn set_borrow_settings(ref self: ContractState, borrow_settings: BorrowSettings) {
      self.common.assert_only_owner();
      self.borrow_settings.write(borrow_settings);
    }
  }

  #[generate_trait]
  pub impl InternalImpl of InternalTrait {
    fn _assert_max_weights(self: @ContractState, total_amount: u256) {
      let allowed_pools = self._get_pool_data();
      let mut i = 0;
      loop {
        if(i == allowed_pools.len()) {
          break;
        }
        let pool = *allowed_pools.at(i);
        let asset_in_pool = self._calculate_amount_in_pool(pool.v_token);
        let asset_basis: u32 = ((asset_in_pool * 10000) / total_amount).try_into().unwrap();
        assert(asset_basis <= pool.max_weight, Errors::MAX_WEIGHT_EXCEEDED);
        i += 1;
      }
    }

    fn _assert_hf(self: @ContractState) {
      //have some doubts here
    }

    fn _calculate_amount_in_pool(self: @ContractState, v_token: ContractAddress) -> u256 {
      let this = get_contract_address();
      let v_token_bal = ERC20Helper::balanceOf(v_token, this);
      IERC4626Dispatcher {contract_address: v_token}.convert_to_assets(v_token_bal)
    }

    fn _interest_rate_per_pool(self: @ContractState, pool_id: felt252) -> u256 {
      let singleton = self.vesu_settings.read().singleton;
      let asset = self.asset();
      // get utilization for asset
      let utilization = singleton.utilization(
        pool_id,
        asset
      );

      // get asset info
      let (asset_info, _ )  = singleton.asset_config(
        pool_id,
        asset
      );

      let extension = singleton.extension(
        pool_id,
      );
      let interest_rate = IVesuExtensionDispatcher {contract_address: extension}.
      interest_rate(
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

    fn _set_pool_settings(
      ref self: ContractState, 
      allowed_pools: Array<PoolProps>, 
     ) {
      // set pools
      assert(allowed_pools.len() > 0, Errors::INVALID_POOL_LENGTH);
      let mut pools_str = self.allowed_pools.read();
      pools_str.clean();
      pools_str.append_span(allowed_pools.span()).unwrap(); // @audit add a unwrap here ig
      assert(self.allowed_pools.read().len() == allowed_pools.len(), Errors::INVALID_POOL_LENGTH);
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

    // @audit where are u overwriting total_assets fn logic?

    // @audit compute fee first, then loop across pools to withdraw till u get the 
    // required fee
    fn _collect_fees(ref self: ContractState) {
      let this = get_contract_address();
      let prev_index = self.previous_index.read();
      let assets = self.total_assets(); // @audit use total_assets() instead
      // @audit u need to multiple numerator with 10**18 here (Solution implemented using DEFAULT_INDEX)
      let total_supply = self.erc20.total_supply();
      let curr_index = (assets * DEFAULT_INDEX.into()) / total_supply;
      if curr_index < prev_index.into() {
        let new_index = ((assets - 1) * DEFAULT_INDEX.into()) / total_supply;
        self.previous_index.write(new_index.try_into().unwrap());
        return;
      }
      let index_diff = curr_index.try_into().unwrap() - prev_index;
      // compute fee in asset()
      let fee = (index_diff * self.settings.fee_percent.read().into()) / 10000;
      if fee == 0 { // no point of transfer logic if fee = 0
        return;
      }
      // @audit Fee can be zero if fee setting is 0
      // @audit Fee can be zero if someone doesnt multiple
      // transactions in same block, where index did not
      // enough time to change
      // assert(fee > 0, 'fee cannot be zero');

      let mut fee_loop = fee; 
      let allowed_pools = self._get_pool_data();
      let fee_receiver = self.settings.fee_receiver.read();
      let mut i = 0;
      loop {
        if i == allowed_pools.len() {
          break;
        }
        let v_token = *allowed_pools.at(i).v_token;
        let vault_disp = IERC4626Dispatcher {contract_address: v_token};
        let v_shares_required = vault_disp
        .convert_to_shares(fee_loop.into());
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

      self.emit(
        CollectFees {
          fee_collected: fee,
          fee_collector: fee_receiver
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

    fn _calculate_max_withdraw(self: @ContractState, v_token: ContractAddress) -> u256 {
      let this = get_contract_address();
      let v_token_bal = ERC20Helper::balanceOf(v_token, this);

      IERC4626Dispatcher {contract_address: v_token}.convert_to_assets(v_token_bal)
    }

    fn _calculate_max_withdraw_pool(self: @ContractState, pool_id: felt252, asset: ContractAddress) -> u256 {
      let singleton_disp = self.vesu_settings.read().singleton;
      let (asset_config, _) = singleton_disp.asset_config(
        pool_id,
        asset
      );
      let total_debt = asset_config.total_nominal_debt * asset_config.last_rate_accumulator;
      let max_withdraw = (total_debt + asset_config.reserve) - (total_debt / asset_config.max_utilization) - 1 ;

      max_withdraw
    }

    fn _action(ref self: ContractState, action: Action) {
      let this = get_contract_address();
      let token = self.asset();
      // if borrowing is not enabled, token is always asset()
      if (!self.borrow_settings.read().is_borrowing_allowed) {
        assert(action.token == token, 'token should be asset');
      }

      let allowed_pools = self.get_allowed_pools();
      let mut i = 0;
      let mut v_token = allowed_pools.at(i).v_token;
      loop {
        assert(i != allowed_pools.len(), 'invalid pool id passed');
        if *allowed_pools.at(i).pool_id == action.pool_id {
          v_token = allowed_pools.at(i).v_token;
          break;
        }
        i += 1;
      };

      match action.feature {
        Feature::DEPOSIT => {
          ERC20Helper::approve(self.asset(), *v_token, action.amount);
          IERC4626Dispatcher {contract_address: *v_token}.deposit(action.amount, this);
        },
        Feature::WITHDRAW => {
          let max_withdraw_vault = self._calculate_max_withdraw(*v_token);
          let max_withdraw_pool = self._calculate_max_withdraw_pool(action.pool_id, action.token);
          assert(action.amount <= max_withdraw_vault, 'not enoungh v_tokens');
          assert(action.amount < max_withdraw_pool, 'pool limit exceded');
          IERC4626Dispatcher {contract_address: *v_token}.withdraw(
            action.amount,
            this,
            this
          );
        },
      };
    }

    fn _perform_withdraw_max_possible(ref self: ContractState, pool_id: felt252, v_token: ContractAddress, amount: u256) -> u256 {
      let this = get_contract_address();
      let max_withdraw_vault = self._calculate_max_withdraw(v_token);
      let max_withdraw_pool = self._calculate_max_withdraw_pool(pool_id, self.asset());
      let withdraw_amount = if max_withdraw_pool >= amount {
        if max_withdraw_vault > amount {
          amount
        } else {
          max_withdraw_vault 
        }
      } else {
        if max_withdraw_vault > max_withdraw_pool {
          max_withdraw_pool
        } else {
          max_withdraw_vault 
        }
      };
      if (withdraw_amount == 0) {
        return 0;
      }

      IERC4626Dispatcher {contract_address: v_token}.withdraw(
        withdraw_amount,
        this,
        this
      );

      return withdraw_amount;
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

    fn deposit(ref self: ContractState, assets: u256, receiver: starknet::ContractAddress) -> u256 {
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

    fn mint(ref self: ContractState, shares: u256, receiver: starknet::ContractAddress) -> u256 {
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
      self._compute_assets()
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

  impl ERC4626DefaultNoFees of ERC4626Component::FeeConfigTrait<ContractState> {}

  impl ERC4626DefaultLimits<
    ContractState
  > of ERC4626Component::LimitConfigTrait<ContractState> {}

  impl DefaultConfig of ERC4626Component::ImmutableConfig {
    const UNDERLYING_DECIMALS: u8 = ERC4626Component::DEFAULT_UNDERLYING_DECIMALS;
    const DECIMALS_OFFSET: u8 = ERC4626Component::DEFAULT_DECIMALS_OFFSET;
  }
  
  impl HooksImpl of ERC4626Component::ERC4626HooksTrait<ContractState> {
    /// @notice Handles post-deposit operations for ERC-4626 vault deposits.
    /// @dev This function approves asset transfers, deposits assets into the default pool,
    /// and collects fees after the deposit.
    /// @param assets The amount of assets deposited.
    /// @param shares The number of shares minted in exchange for the deposited assets.
    fn after_deposit(
      ref self:  ERC4626Component::ComponentState<ContractState>,
      assets: u256,
      shares: u256,
     ) {
      let mut contract_state = self.get_contract_mut();
      let pool_ids_array = contract_state._get_pool_data();
      let this = get_contract_address();
      // deposit normally 
      let default_pool_index = contract_state.settings.default_pool_index.read();
      let v_token = *pool_ids_array.at(default_pool_index.into()).v_token;
      ERC20Helper::approve(self.asset(), v_token, assets);
      IERC4626Dispatcher {contract_address: v_token}.deposit(assets, this);
      contract_state._collect_fees();
    }

    /// @notice Handles pre-withdrawal operations to ensure liquidity availability.
    /// @dev This function first attempts to withdraw from the default pool.
    /// If the full amount cannot be withdrawn, it asserts that borrowing is disabled
    /// and withdraws the remaining amount from other pools.
    /// @param assets The amount of assets to withdraw.
    /// @param shares The number of shares to redeem.
    fn before_withdraw(
      ref self: ERC4626Component::ComponentState<ContractState>,
      assets: u256,
      shares: u256
     ) {
      let mut contract_state = self.get_contract_mut();
      contract_state._collect_fees();
      let mut pool_ids_array = contract_state._get_pool_data();
      let default_id = contract_state.settings.read().default_pool_index;
      let default_pool_info = pool_ids_array.at(default_id.into());

      //case 1: if amount exists in default pool 
      let default_pool_withdrawn = contract_state._perform_withdraw_max_possible(
        *default_pool_info.pool_id,
        *default_pool_info.v_token,
        assets
      );


      if (default_pool_withdrawn == assets) {
        return;
      }
      
      // till we impl a proper logic
      let borrow_settings = contract_state.borrow_settings.read();
      assert(!borrow_settings.is_borrowing_allowed, 'borrowing is enabled');

      // case 2: withdraw remaining from other pools
      let mut remaining_amount = assets - default_pool_withdrawn;
      let mut i = 0;
      loop {
        if i == pool_ids_array.len() {
          break;
        }
        if i == default_id.into() {
          continue;
        }
        let withdrawn_amount = contract_state._perform_withdraw_max_possible(
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

      assert(remaining_amount == 0, 'remaining amount should be zero');
    }
  }
}

// @audit add test to check constructor args too (name, symbol, decimals, owner, etc)
// @audit Did we discuss about auto harvesting? This contract will have to import our harvesting and reward share component also i think. 