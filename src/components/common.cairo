#[starknet::component]
pub mod CommonComp {
    use openzeppelin::upgrades::UpgradeableComponent;
    use starknet::get_caller_address;
    use openzeppelin::upgrades::UpgradeableComponent::InternalTrait as UpgradeableInternalTrait;
    use openzeppelin::security::pausable::{PausableComponent};
    use openzeppelin::security::pausable::PausableComponent::{
        InternalTrait as PausableInternalTrait, PausableImpl
    };
    use openzeppelin::security::reentrancyguard::ReentrancyGuardComponent;
    use openzeppelin::access::accesscontrol::interface::{
        IAccessControlDispatcher, IAccessControlDispatcherTrait
    };
    use strkfarm_contracts::interfaces::common::ICommon;
    use strkfarm_contracts::components::accessControl::AccessControl::Roles;
    use starknet::{ClassHash, ContractAddress};

    #[storage]
    pub struct Storage {
        access_control: ContractAddress
    }

    #[embeddable_as(CommonImpl)]
    impl Common<
        TContractState,
        +HasComponent<TContractState>,
        impl Upgradeable: UpgradeableComponent::HasComponent<TContractState>,
        impl Pausable: PausableComponent::HasComponent<TContractState>,
        impl ReentrancyGuard: ReentrancyGuardComponent::HasComponent<TContractState>,
        +Drop<TContractState>
    > of ICommon<ComponentState<TContractState>> {
        // todo add options to add additional calldata to execute after the upgrade
        fn upgrade(ref self: ComponentState<TContractState>, new_class: ClassHash) {
            self.assert_admin_role();
            let mut upgradeable = get_dep_component_mut!(ref self, Upgradeable);
            upgradeable.upgrade(new_class);
        }

        fn pause(ref self: ComponentState<TContractState>) {
            self.assert_emergency_actor_role();
            let mut pausable = get_dep_component_mut!(ref self, Pausable);
            pausable.pause();
        }

        fn unpause(ref self: ComponentState<TContractState>) {
            self.assert_emergency_actor_role();
            let mut pausable = get_dep_component_mut!(ref self, Pausable);
            pausable.unpause();
        }

        fn is_paused(self: @ComponentState<TContractState>) -> bool {
            let pausable = get_dep_component!(self, Pausable);
            pausable.is_paused()
        }
    }

    #[generate_trait]
    pub impl InternalImpl<
        TContractState,
        +HasComponent<TContractState>,
        impl Upgradeable: UpgradeableComponent::HasComponent<TContractState>,
        impl Pausable: PausableComponent::HasComponent<TContractState>,
        impl ReentrancyGuard: ReentrancyGuardComponent::HasComponent<TContractState>,
        +Drop<TContractState>
    > of InternalTrait<TContractState> {
        fn initializer(ref self: ComponentState<TContractState>, access_control: ContractAddress) {
            self.access_control.write(access_control);
        }

        fn assert_not_paused(self: @ComponentState<TContractState>) {
            let pausable = get_dep_component!(self, Pausable);
            pausable.assert_not_paused();
        }

        // Assert that the caller has a specific role
        fn has_role(self: @ComponentState<TContractState>, role: felt252) -> bool {
            let access_control = self.access_control.read();
            IAccessControlDispatcher { contract_address: access_control }
                .has_role(role, get_caller_address())
        }

        // Assert that the caller is the DEFAULT_ADMIN_ROLE
        fn assert_admin_role(self: @ComponentState<TContractState>) {
            assert(self.has_role(Roles::DEFAULT_ADMIN_ROLE), 'Access: Missing admin role');
        }

        // Assert that the caller is the GOVERNOR
        fn assert_governor_role(self: @ComponentState<TContractState>) {
            assert(self.has_role(Roles::GOVERNOR), 'Access: Missing governor role');
        }

        // Assert that the caller is the EMERGENCY_ACTOR
        fn assert_emergency_actor_role(self: @ComponentState<TContractState>) {
            assert(self.has_role(Roles::EMERGENCY_ACTOR), 'Access: Missing EA role');
        }

        // Assert that the caller is the RELAYER
        fn assert_relayer_role(self: @ComponentState<TContractState>) {
            assert(self.has_role(Roles::RELAYER), 'Access: Missing relayer role');
        }
    }
}
