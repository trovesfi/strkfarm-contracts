use strkfarm_contracts::components::harvester::interface::{IClaimTrait, ClaimResult};
use strkfarm_contracts::interfaces::IEkuboDistributor::{Claim};
use starknet::{ContractAddress, get_contract_address};
use openzeppelin::token::erc20::interface::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};
use strkfarm_contracts::helpers::constants;

/// -------------
/// Distribution contract style Created by SNF, followed by Nostra and others
/// e.g. 0x6f80b8e79c5a4f60aaa1d5d251e2dfc55496ed748f96cf38c034de6d578f3f (mainnet)
/// -------------

#[starknet::interface]
pub trait ISNFClaimTrait<TContractState> {
    fn claim(ref self: TContractState, amount: u128, proof: Span<felt252>);
}

#[derive(Drop, Copy, Serde)]
pub struct SNFStyleClaimSettings {
    pub rewardsContract: ContractAddress
}

pub impl ClaimImpl of IClaimTrait<SNFStyleClaimSettings> {
    fn claim_with_proofs(
        self: @SNFStyleClaimSettings, claim: Claim, proof: Span<felt252>
    ) -> ClaimResult {
        let mut distributor: ISNFClaimTraitDispatcher = ISNFClaimTraitDispatcher {
            contract_address: *self.rewardsContract
        };
        let rewardToken: ContractAddress = constants::STRK_ADDRESS();
        let rewardTokenDisp = ERC20ABIDispatcher { contract_address: rewardToken };

        if (proof.len() == 0) {
            return ClaimResult { token: rewardToken, amount: 0 };
        }

        let this = get_contract_address();

        let pre_bal = rewardTokenDisp.balanceOf(this);
        distributor.claim(claim.amount, proof);
        let post_bal = rewardTokenDisp.balanceOf(this);

        // claim may not be exactly as requested, so we do bal diff check
        let amount = (post_bal - pre_bal);
        assert(amount > 0, 'No harvest');

        ClaimResult { token: rewardToken, amount }
    }
}
