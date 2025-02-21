use strkfarm_contracts::components::harvester::interface::{IClaimTrait, ClaimResult};
use strkfarm_contracts::interfaces::IEkuboDistributor::{
    IEkuboDistributorDispatcherTrait, Claim, IEkuboDistributorDispatcher
};
use starknet::{ContractAddress, get_contract_address};
use openzeppelin::token::erc20::interface::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};

/// -------------
/// Distribution contract style used by Ekubo and followed by some others
/// e.g. 0x03a3cc51e76135caee3473680a11f64db87537a0252f805d60e69f31e1a7e9b4 (mainnet)
/// -------------

#[derive(Drop, Copy, Serde)]
pub struct EkuboStyleClaimSettings {
    pub rewardsContract: ContractAddress
}

pub impl ClaimImpl of IClaimTrait<EkuboStyleClaimSettings> {
    fn claim_with_proofs(
        self: @EkuboStyleClaimSettings, claim: Claim, proof: Span<felt252>
    ) -> ClaimResult {
        let distributor: IEkuboDistributorDispatcher = IEkuboDistributorDispatcher {
            contract_address: *self.rewardsContract
        };
        let rewardToken: ContractAddress = distributor.get_token().contract_address;
        let rewardTokenDisp = ERC20ABIDispatcher { contract_address: rewardToken };

        if (proof.len() == 0) {
            return ClaimResult { token: rewardToken, amount: 0 };
        }

        let this = get_contract_address();
        let pre_bal = rewardTokenDisp.balanceOf(this);
        distributor.claim(claim, proof);
        let post_bal = rewardTokenDisp.balanceOf(this);

        // claim may not be exactly as requested, so we do bal diff check
        let amount = (post_bal - pre_bal);
        assert(amount > 0, 'No harvest');

        ClaimResult { token: rewardToken, amount }
    }
}
