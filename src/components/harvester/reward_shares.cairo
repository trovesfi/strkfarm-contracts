// Since starknet rewards are distributed every 2 weeks and there is deterministic way to calculate
// the exact rewards, this module computes unique shares of user for each round, computing their
// total new shares of underlying contract

use starknet::{ContractAddress};

#[derive(Drop, Copy, Serde, starknet::Store, starknet::Event)]
pub struct RewardsInfo {
    pub amount: u128, // (e.g. STRK for Auto STRK, USDC for Auto USDC)
    pub shares: u128, // shares of underlying contract (e.g. frmzSTRK)
    pub total_round_points: u128, // total points of round which is compared with user shares round to compute user shares
    pub block_number: u64, // When rewards were harvested
}

#[derive(Drop, Copy, Serde, starknet::Store, starknet::Event)]
pub struct UserRewardsInfo {
    pub pending_round_points: u128, // pending points of user in current round
    pub shares_owned: u128, // total shares of user in underlying contract used to compute harvest shares
    pub block_number: u64, // last updated time
    pub index: u32, // index of rewardsInfo
}


#[starknet::interface]
pub trait IRewardShare<TState> {
    fn get_user_reward_info(self: @TState, user: ContractAddress) -> UserRewardsInfo;
    fn get_rewards_info(self: @TState, index: u32) -> RewardsInfo;
    fn get_total_rewards(self: @TState) -> u32;
    fn get_total_unminted_shares(self: @TState) -> u128;
    fn get_additional_shares(self: @TState, user: ContractAddress,) -> (u128, u64, u128);
}

#[starknet::component]
pub mod RewardShareComponent {
    use starknet::{ContractAddress, get_block_timestamp, get_block_number};
    use strkfarm_contracts::helpers::safe_decimal_math;
    use super::{RewardsInfo, UserRewardsInfo, IRewardShare};

    /// Terminology
    /// 1. shares: underlying shares of contract which is minted to represent user's share in
    /// contract (e.g. frmzSTRK)
    /// 2. harvest_shares: new shares of underlying asset already distributed to user denominated in
    /// underlying shares (e.g. frmzSTRK)
    /// 3. shares_round: shares of user representing part of their share in a given round
    /// 4. for a given round, harvest_shares = (shares_round / total_round_points) * shares

    #[storage]
    pub struct Storage {
        last_updated_block: u64, // last block when rewards were updated
        // rewardsInfo gets add when ever there is harvesting
        rewards_info: starknet::storage::Map<u32, RewardsInfo>, // index => RewardsInfo
        rewards_len: u32,
        total_underlying_shares: u128, // total new shares of underlying contract (e.g. in frmzSTRK)
        user_rewards_info: starknet::storage::Map<
            ContractAddress, UserRewardsInfo
        >, // (user) => UserRewardsInfo
    }

    #[derive(Drop, starknet::Event)]
    struct Rewards {
        index: u32,
        info: RewardsInfo,
        total_reward_shares: u128,
        timestamp: u64,
    }

    #[derive(Drop, starknet::Event)]
    struct UserRewards {
        #[key]
        user: ContractAddress,
        info: UserRewardsInfo,
        total_reward_shares: u128,
        timestamp: u64,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        Rewards: Rewards,
        UserRewards: UserRewards,
    }

    #[embeddable_as(RewardShareImpl)]
    pub impl RewardShare<
        TContractState, +HasComponent<TContractState>, +Drop<TContractState>
    > of IRewardShare<ComponentState<TContractState>> {
        fn get_user_reward_info(
            self: @ComponentState<TContractState>, user: ContractAddress
        ) -> UserRewardsInfo {
            self.user_rewards_info.read(user)
        }

        fn get_rewards_info(self: @ComponentState<TContractState>, index: u32) -> RewardsInfo {
            self.rewards_info.read(index)
        }

        fn get_total_rewards(self: @ComponentState<TContractState>) -> u32 {
            self.rewards_len.read()
        }

        /// shares that are not yet created in contract global storage (e.g. in totalSupply var)
        fn get_total_unminted_shares(self: @ComponentState<TContractState>) -> u128 {
            self.total_underlying_shares.read()
        }

        /// returns new shares to be received by this user since last update based on
        /// points collected
        fn get_additional_shares(
            self: @ComponentState<TContractState>, user: ContractAddress,
        ) -> (u128, u64, u128) {
            let total_rounds = self.rewards_len.read();
            let user_rewards: UserRewardsInfo = self.user_rewards_info.read(user);
            let mut current_index = user_rewards.index; // computation of points begin here

            // variables updated in loop
            let mut net_additional_shares: u128 = 0;
            let mut last_block_number = user_rewards.block_number;

            // no deposits by user
            if (user_rewards.block_number == 0) {
                return (net_additional_shares, get_block_number(), 0);
            }

            let mut user_shares = user_rewards.shares_owned;
            let mut pending_points = user_rewards.pending_round_points;
            loop {
                let rewards: RewardsInfo = self.rewards_info.read(current_index);
                let mut end_block_number = rewards.block_number;

                // record computation of shares till current block if rewards not already harvested
                if (rewards.amount == 0) {
                    end_block_number = get_block_number();
                }

                assert(last_block_number <= end_block_number, 'Reward: Invalid block number');

                let block_diff: u128 = (end_block_number - last_block_number).into();

                // compute user's new points for this round
                let user_round_points = (user_shares * block_diff);

                // if true, its unfinished round. Just save points and exit.
                if (current_index == total_rounds) {
                    pending_points += user_round_points;
                    last_block_number = end_block_number;
                    // bcz last round isnt over yet so no new shares
                    break;
                }

                // if user has pending points, then add them to user_round_points
                let user_round_points = user_round_points + pending_points;
                let total_round_points = rewards.total_round_points;
                if (total_round_points == 0) {
                    // no shares minted in this round
                    // can happen if there are deposits in the same block as harvest
                    current_index += 1;
                    last_block_number = end_block_number;
                    continue;
                }
                let additional_shares = safe_decimal_math::div_round_down(
                    user_round_points.into() * rewards.shares.into(), total_round_points.into(),
                );

                net_additional_shares += additional_shares.try_into().unwrap();
                user_shares += additional_shares
                    .try_into()
                    .unwrap(); // updated total shares will be used for next round
                current_index += 1;
                last_block_number = end_block_number;
                pending_points = 0;
            };

            return (net_additional_shares, last_block_number, pending_points);
        }
    }

    #[generate_trait]
    pub impl InternalImpl<
        TContractState, +HasComponent<TContractState>, +Drop<TContractState>
    > of InternalTrait<TContractState> {
        // called everytime rewards are harvested
        fn update_harvesting_rewards(
            ref self: ComponentState<TContractState>,
            amount: u128, // e.g. USDC reward
            shares: u128, // in lp token terms of the contract (e.g. frmzUSDC) that corresponds to amount
            total_shares: u128,
        ) {
            let mut len = self.rewards_len.read();
            assert(len > 0, 'Rewards not initialized');
            assert(amount.into() > 0_u256, 'Invalid amount');
            assert(shares.into() > 0_u256, 'Invalid shares [1]');

            // generally rewards are always less then total TVL
            // unless everyone withdraws just before harvest.
            let total_shares_u256: u256 = total_shares.into();
            // in cases like dnmm_vesu, total_shares is 0 but it can still earn rewards
            assert(
                total_shares_u256 == 0 || shares.into() < total_shares_u256, 'Invalid shares [3]'
            );

            let now = get_block_number();
            let total_round_points = self.get_total_round_points(total_shares);
            let existing_reward_info: RewardsInfo = self.rewards_info.read(len);

            let rewards_info = RewardsInfo {
                amount,
                shares,
                total_round_points: existing_reward_info.total_round_points + total_round_points,
                block_number: get_block_number(),
            };

            // update total shares created for harvested funds
            let current_underlying_shares = self.total_underlying_shares.read();
            self.total_underlying_shares.write(current_underlying_shares + shares);

            self.update_rewards_info(len, rewards_info);
            self.rewards_len.write(len + 1);
            self.init_new_round_at_current_index(now);
            self.last_updated_block.write(now);
        }

        /// called everytime **before** user deposits or withdraws
        /// updates the shares this user receives which is a portion of total underlying shares
        fn update_user_rewards(
            ref self: ComponentState<TContractState>,
            user: ContractAddress,
            shares_owned: u128, // current lp shares
            pending_shares: u128, // pending lp shares
            pending_shares_last_block: u64,
            pending_round_points: u128, // pending shares of user in current round
            total_shares: u128, // total lp shares (prev) (e.g. totalSupply frmzSTRK)
        ) {
            let user_rewards = self.user_rewards_info.read(user);
            let mut current_index = self.rewards_len.read(); // bcz user will get rewards from here

            // call init if rewards are not initialized
            if (current_index == 0) {
                // rewards map is not initialized
                self.init(get_block_number());
                current_index = self.rewards_len.read();
            }

            // update total round shares
            let mut rewards: RewardsInfo = self.rewards_info.read(current_index);
            assert(rewards.amount == 0, 'Rewards already distributed'); // just an extra check
            let total_round_points = self.get_total_round_points(total_shares);
            rewards.total_round_points += total_round_points;
            rewards.block_number = get_block_number();

            /// assume that contract will mint these pending_shares,
            /// hence reduce total underlying shares as totalSupply already increases with mint
            let total_underlying_shares = self.total_underlying_shares.read();
            self.total_underlying_shares.write(total_underlying_shares - pending_shares);

            self.update_rewards_info(current_index, rewards);
            self.last_updated_block.write(rewards.block_number);

            if (user_rewards.block_number == 0) {
                // first time user
                let user_rewards = UserRewardsInfo {
                    pending_round_points: 0,
                    shares_owned: shares_owned,
                    block_number: get_block_number(),
                    index: current_index,
                };
                self.update_user_rewards_info(user, user_rewards);
            } else {
                // existing user. Compute new shares and add them.
                let user_rewards = UserRewardsInfo {
                    pending_round_points: pending_round_points,
                    shares_owned: shares_owned,
                    block_number: pending_shares_last_block,
                    index: current_index,
                };
                self.update_user_rewards_info(user, user_rewards);
            }
        }
    }

    #[generate_trait]
    pub impl PrivateImpl<
        TContractState, +HasComponent<TContractState>, +Drop<TContractState>
    > of PrivateTrait<TContractState> {
        /// blocknumber of first deposit
        /// computation of points starts from here
        fn init(
            ref self: ComponentState<TContractState>,
            block_number: u64, // block number of first deposit
        ) {
            let len = self.rewards_len.read();
            assert(len == 0, 'Already initialized');

            self.rewards_len.write(1);
            self.last_updated_block.write(block_number);

            // init current round
            // this will be updated by update_user_rewards when user deposits or withdraws for
            // current round
            self.init_new_round_at_current_index(block_number);
        }

        /// total points accrued since last update
        fn get_total_round_points(
            self: @ComponentState<TContractState>, total_shares: u128,
        ) -> u128 {
            let last_block = self.last_updated_block.read();
            assert(last_block > 0, 'Invalid block number');
            let now = get_block_number();
            let block_diff: u128 = (now - last_block).into();
            return total_shares * block_diff;
        }

        /// useful to initialize new round when prev round is over
        fn init_new_round_at_current_index(
            ref self: ComponentState<TContractState>,
            block_number: u64, // block number of round begin or first deposit
        ) {
            let len = self.rewards_len.read();
            let rewardsInfo = RewardsInfo {
                amount: 0, shares: 0, total_round_points: 0, block_number,
            };
            self.update_rewards_info(len, rewardsInfo);
        }

        /// updates rewards info and emits event with current state
        fn update_rewards_info(
            ref self: ComponentState<TContractState>, index: u32, info: RewardsInfo,
        ) {
            self.rewards_info.write(index, info);
            self
                .emit(
                    Rewards {
                        index,
                        info,
                        total_reward_shares: self.total_underlying_shares.read(),
                        timestamp: get_block_timestamp(),
                    }
                )
        }

        /// updates user rewards info and emits event with current state
        fn update_user_rewards_info(
            ref self: ComponentState<TContractState>, user: ContractAddress, info: UserRewardsInfo
        ) {
            self.user_rewards_info.write(user, info);
            self
                .emit(
                    UserRewards {
                        user,
                        info,
                        total_reward_shares: self.total_underlying_shares.read(),
                        timestamp: get_block_timestamp(),
                    }
                )
        }
    }
}
