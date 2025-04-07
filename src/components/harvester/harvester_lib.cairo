use strkfarm_contracts::interfaces::IEkuboDistributor::{Claim};
use strkfarm_contracts::components::swap::{AvnuMultiRouteSwap, AvnuMultiRouteSwapImpl};
use strkfarm_contracts::components::harvester::interface::{IClaimTrait};
use starknet::{ContractAddress};
use strkfarm_contracts::interfaces::oracle::{IPriceOracleDispatcher};

#[starknet::interface]
pub trait ISimpleHarvest<TState> {
    fn harvest(ref self: TState, claim: Claim, proof: Span<felt252>, swapInfo: AvnuMultiRouteSwap);
}

pub struct HarvestBeforeHookResult {
    pub baseToken: ContractAddress,
}

#[derive(Drop, Copy, starknet::Event)]
pub struct HarvestEvent {
    #[key]
    pub rewardToken: ContractAddress,
    pub rewardAmount: u256,
    #[key]
    pub baseToken: ContractAddress,
    pub baseAmount: u256,
}

/// empty for now, but can be used to add more fields in future
#[derive(Drop, Copy)]
pub struct HarvestConfig {}

pub trait HarvestHooksTrait<TContractState> {
    fn before_update(ref self: TContractState) -> HarvestBeforeHookResult;

    // @param token - token address of the reward received
    // @param amount - amount of the reward received
    fn after_update(ref self: TContractState, token: ContractAddress, amount: u256);
}

pub trait HarvestConfigTrait<T, TContractState, TSettings1, TSettings2> {
    fn simple_harvest(
        self: @T,
        ref state: TContractState,
        settings: TSettings1,
        claim: Claim,
        proof: Span<felt252>,
        // just dummy arg, not actually used. Required for build
        // Required for build as HarvestConfigTrait requires TSettings2
        settings2: TSettings2,
        swapInfo: AvnuMultiRouteSwap,
        oracle: IPriceOracleDispatcher
    );
    fn double_harvest(
        self: @T,
        ref state: TContractState,
        settings1: TSettings1,
        claim1: Claim,
        proof1: Span<felt252>,
        settings2: TSettings2,
        claim2: Claim,
        proof2: Span<felt252>,
        swapInfo: AvnuMultiRouteSwap,
        oracle: IPriceOracleDispatcher
    );
}

pub impl HarvestConfigImpl<
    TContractState,
    TSettings1,
    TSettings2,
    +HarvestHooksTrait<TContractState>,
    +IClaimTrait<TSettings1>,
    +IClaimTrait<TSettings2>,
    +Drop<TContractState>,
    +Drop<TSettings1>,
    +Drop<TSettings2>
> of HarvestConfigTrait<HarvestConfig, TContractState, TSettings1, TSettings2> {
    fn simple_harvest(
        self: @HarvestConfig,
        ref state: TContractState,
        settings: TSettings1,
        claim: Claim,
        proof: Span<felt252>,
        // just dummy arg, not actually used. Required for build
        // Required for build as HarvestConfigTrait requires TSettings2
        settings2: TSettings2,
        swapInfo: AvnuMultiRouteSwap,
        oracle: IPriceOracleDispatcher
    ) {
        assert(claim.amount != 0, 'Invalid claim amount');

        // calls hooks implemented by contract. e.g. get base token address
        let beforeHookResult = HarvestHooksTrait::before_update(ref state);
        let baseTokenAddress = beforeHookResult.baseToken;

        // claim with proofs
        let claimResult = settings.claim_with_proofs(claim, proof);
        let mut depositAmount = claimResult.amount;

        // swap if token is not base token
        depositAmount =
            check_and_swap_harvest(
                claimResult.token, baseTokenAddress, depositAmount, swapInfo, oracle
            );

        // calls hooks implemented by contract. e.g. deposit this harvest amount back in contract
        HarvestHooksTrait::after_update(ref state, baseTokenAddress, depositAmount);
    }

    fn double_harvest(
        self: @HarvestConfig,
        ref state: TContractState,
        settings1: TSettings1,
        claim1: Claim,
        proof1: Span<felt252>,
        settings2: TSettings2,
        claim2: Claim,
        proof2: Span<felt252>,
        swapInfo: AvnuMultiRouteSwap,
        oracle: IPriceOracleDispatcher
    ) {
        assert(claim1.amount != 0, 'Invalid claim1 amount');
        assert(claim2.amount != 0, 'Invalid claim2 amount');

        // calls hooks implemented by contract. e.g. get base token address
        let beforeHookResult = HarvestHooksTrait::before_update(ref state);
        let baseTokenAddress = beforeHookResult.baseToken;

        // claim with proofs
        let claimResult1 = settings1.claim_with_proofs(claim1, proof1);
        let claimResult2 = settings2.claim_with_proofs(claim2, proof2);
        assert(claimResult1.token == claimResult2.token, 'Hrvt: invld rwd token');
        let depositAmount1 = claimResult1.amount;
        let depositAmount2 = claimResult2.amount;
        let mut depositAmount = depositAmount1 + depositAmount2;

        // swap if token is not base token
        assert(swapInfo.token_from_amount == depositAmount, 'Invalid token from amount');
        depositAmount =
            check_and_swap_harvest(
                claimResult1.token, baseTokenAddress, depositAmount, swapInfo, oracle
            );

        // calls hooks implemented by contract. e.g. deposit this harvest amount back in contract
        /// println!("after hook");
        HarvestHooksTrait::after_update(ref state, baseTokenAddress, depositAmount);
    }
}

fn check_and_swap_harvest(
    rewardToken: ContractAddress,
    baseTokenAddress: ContractAddress,
    amount: u256,
    swapInfo: AvnuMultiRouteSwap,
    oracle: IPriceOracleDispatcher
) -> u256 {
    // swap if token is not base token
    if (rewardToken != baseTokenAddress) {
        // swap to base token to deposit again
        assert(swapInfo.token_from_address == rewardToken, 'Invalid token from address');
        assert(swapInfo.token_to_address == baseTokenAddress, 'Invalid token to address');
        assert(swapInfo.token_from_amount == amount, 'Invalid token from amount');

        return swapInfo.swap(oracle);
    }

    return amount;
}
