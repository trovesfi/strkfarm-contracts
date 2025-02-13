#[starknet::component]
pub mod CommonComp {
    use openzeppelin::upgrades::UpgradeableComponent;
    use openzeppelin::upgrades::UpgradeableComponent::InternalTrait as UpgradeableInternalTrait;
    use openzeppelin::access::ownable::OwnableComponent;
    use openzeppelin::access::ownable::OwnableComponent::{InternalTrait as OwnableInternalTrait,};
    use openzeppelin::access::ownable::interface::{IOwnable};
    use openzeppelin::security::pausable::{PausableComponent};
    use openzeppelin::security::pausable::PausableComponent::{
        InternalTrait as PausableInternalTrait, PausableImpl
    };
    use openzeppelin::security::reentrancyguard::ReentrancyGuardComponent;
    use openzeppelin::security::reentrancyguard::ReentrancyGuardComponent::{
        InternalTrait as ReentrancyGuardInternalTrait,
    };

    use strkfarm_contracts::interfaces::common::ICommon;
    use starknet::{ClassHash, ContractAddress};

    #[storage]
    pub struct Storage {}

    #[embeddable_as(CommonImpl)]
    impl Common<
        TContractState,
        +HasComponent<TContractState>,
        impl Upgradeable: UpgradeableComponent::HasComponent<TContractState>,
        impl Ownable: OwnableComponent::HasComponent<TContractState>,
        impl Pausable: PausableComponent::HasComponent<TContractState>,
        impl ReentrancyGuard: ReentrancyGuardComponent::HasComponent<TContractState>,
        +Drop<TContractState>
    > of ICommon<ComponentState<TContractState>> {
    
        // todo add options to add additional calldata to execute after the upgrade
        fn upgrade(ref self: ComponentState<TContractState>, new_class: ClassHash) {
            self.assert_only_owner();
            let mut upgradeable = get_dep_component_mut!(ref self, Upgradeable);
            upgradeable.upgrade(new_class);
        }

        fn pause(ref self: ComponentState<TContractState>) {
            self.assert_only_owner();
            let mut pausable = get_dep_component_mut!(ref self, Pausable);
            pausable.pause();
        }

        fn unpause(ref self: ComponentState<TContractState>) {
            self.assert_only_owner();
            let mut pausable = get_dep_component_mut!(ref self, Pausable);
            pausable.unpause();
        }

        fn is_paused(self: @ComponentState<TContractState>) -> bool {
            let pausable = get_dep_component!(self, Pausable);
            pausable.is_paused()
        }

        // for easy of importing impls, adding ownable stuff here
        // instead of importing from oz
        fn owner(self: @ComponentState<TContractState>) -> ContractAddress {
            let ownable = get_dep_component!(self, Ownable);
            ownable.owner()
        }

        fn transfer_ownership(
            ref self: ComponentState<TContractState>, new_owner: ContractAddress
        ) {
            let mut ownable = get_dep_component_mut!(ref self, Ownable);
            ownable.transfer_ownership(new_owner);
        }

        fn renounce_ownership(ref self: ComponentState<TContractState>) {
            let mut ownable = get_dep_component_mut!(ref self, Ownable);
            ownable.renounce_ownership();
        }
    }

    #[generate_trait]
    pub impl InternalImpl<
        TContractState,
        +HasComponent<TContractState>,
        impl Upgradeable: UpgradeableComponent::HasComponent<TContractState>,
        impl Ownable: OwnableComponent::HasComponent<TContractState>,
        impl Pausable: PausableComponent::HasComponent<TContractState>,
        impl ReentrancyGuard: ReentrancyGuardComponent::HasComponent<TContractState>,
        +Drop<TContractState>
    > of InternalTrait<TContractState> {
        fn initializer(ref self: ComponentState<TContractState>, owner: ContractAddress) {
            let mut ownable = get_dep_component_mut!(ref self, Ownable);
            ownable.initializer(owner);
        }

        fn assert_only_owner(self: @ComponentState<TContractState>) {
            let ownable = get_dep_component!(self, Ownable);
            ownable.assert_only_owner();
        }

        fn assert_not_paused(self: @ComponentState<TContractState>) {
            let pausable = get_dep_component!(self, Pausable);
            pausable.assert_not_paused();
        }
    }
}
