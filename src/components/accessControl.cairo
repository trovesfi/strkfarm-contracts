#[starknet::contract]
pub mod AccessControl {
    use AccessControlComponent::InternalTrait;
    use starknet::{ContractAddress, ClassHash};
    use openzeppelin::access::accesscontrol::AccessControlComponent;
    use openzeppelin::upgrades::upgradeable::UpgradeableComponent;
    use openzeppelin::upgrades::interface::IUpgradeable;
    use openzeppelin::introspection::src5::SRC5Component;
    use core::num::traits::Zero;

    component!(path: AccessControlComponent, storage: access_control, event: AccessControlEvent);
    component!(path: UpgradeableComponent, storage: upgradeable, event: UpgradeableEvent);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);

    impl AccessControlInternalImpl = AccessControlComponent::InternalImpl<ContractState>;
    impl UpgradeableInternalImpl = UpgradeableComponent::InternalImpl<ContractState>;

    #[abi(embed_v0)]
    impl AccessControlImpl =
        AccessControlComponent::AccessControlImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        access_control: AccessControlComponent::Storage,
        #[substorage(v0)]
        upgradeable: UpgradeableComponent::Storage,
        #[substorage(v0)]
        src5: SRC5Component::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        AccessControlEvent: AccessControlComponent::Event,
        #[flat]
        UpgradeableEvent: UpgradeableComponent::Event,
        #[flat]
        SRC5Event: SRC5Component::Event,
    }

    // Define roles
    pub mod Roles {
        pub const DEFAULT_ADMIN_ROLE: felt252 = 0;
        pub const GOVERNOR: felt252 = selector!("GOVERNOR");
        pub const RELAYER: felt252 = selector!("RELAYER");
        pub const EMERGENCY_ACTOR: felt252 = selector!("EMERGENCY_ACTOR");
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        admin: ContractAddress,
        governor_address: ContractAddress,
        relayer_address: ContractAddress,
        emergency_address: ContractAddress,
    ) {
        self.access_control.initializer();
        // Grant DEFAULT_ADMIN_ROLE to the admin
        self.access_control._grant_role(Roles::DEFAULT_ADMIN_ROLE, admin);
        // set role admin for all roles as DEFAULT_ADMIN_ROLE
        self.access_control.set_role_admin(Roles::GOVERNOR, Roles::DEFAULT_ADMIN_ROLE);
        self.access_control.set_role_admin(Roles::RELAYER, Roles::DEFAULT_ADMIN_ROLE);
        self.access_control.set_role_admin(Roles::EMERGENCY_ACTOR, Roles::DEFAULT_ADMIN_ROLE);

        // grant roles to each address
        assert(governor_address.is_non_zero(), 'Governor address cannot be zero');
        assert(relayer_address.is_non_zero(), 'Relayer address cannot be zero');
        assert(emergency_address.is_non_zero(), 'Emgncy address cannot be zero');
        self.access_control._grant_role(Roles::GOVERNOR, governor_address);
        self.access_control._grant_role(Roles::RELAYER, relayer_address);
        self.access_control._grant_role(Roles::EMERGENCY_ACTOR, emergency_address);
    }

    #[abi(embed_v0)]
    impl UpgradeableImpl of IUpgradeable<ContractState> {
        fn upgrade(ref self: ContractState, new_class_hash: ClassHash) {
            self.access_control.assert_only_role(Roles::DEFAULT_ADMIN_ROLE);

            self.upgradeable.upgrade(new_class_hash);
        }
    }
}
