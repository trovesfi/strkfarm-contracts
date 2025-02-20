#[starknet::contract]
pub mod DefiSpringEkuboMock {
    use strkfarm_contracts::helpers::constants;
    use strkfarm_contracts::interfaces::IEkuboDistributor::{
        IEkuboDistributor, Claim
    };
    use strkfarm_contracts::helpers::ERC20Helper;
    use openzeppelin::token::erc20::interface::{IERC20, IERC20Dispatcher, IERC20DispatcherTrait};

    #[storage]
    pub struct Storage {
    }

    #[abi(embed_v0)]
    pub impl DefiSpringEkuboMockImpl of IEkuboDistributor<ContractState> {
        fn claim(ref self: ContractState, claim: Claim, proof: Span<felt252>) -> bool {
            ERC20Helper::transfer(constants::STRK_ADDRESS(), claim.claimee, claim.amount.into());
            return true;
        }

        fn get_token(self: @ContractState) -> IERC20Dispatcher {
            IERC20Dispatcher { contract_address: constants::STRK_ADDRESS() }
        }
    }
}