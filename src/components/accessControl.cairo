#[starknet::contract]
pub mod AccessControl {
    use AccessControlComponent::InternalTrait;
use starknet::{ContractAddress, get_caller_address, ClassHash};
    use openzeppelin::access::accesscontrol::AccessControlComponent;
    use openzeppelin::access::accesscontrol::interface::IAccessControl;
    use openzeppelin::upgrades::upgradeable::UpgradeableComponent;
    use openzeppelin::upgrades::interface::IUpgradeable;
    use openzeppelin::introspection::src5::SRC5Component;

    component!(path: AccessControlComponent, storage: access_control, event: AccessControlEvent);
    component!(path: UpgradeableComponent, storage: upgradeable, event: UpgradeableEvent);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);

    impl AccessControlInternalImpl = AccessControlComponent::InternalImpl<ContractState>;
    impl UpgradeableInternalImpl = UpgradeableComponent::InternalImpl<ContractState>;

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
        self.access_control._grant_role(Roles::GOVERNOR, governor_address);
        self.access_control._grant_role(Roles::RELAYER, relayer_address);
        self.access_control._grant_role(Roles::EMERGENCY_ACTOR, emergency_address);
    }

    #[abi(embed_v0)]
    impl AccessControlExternalImpl of IAccessControl<ContractState> {
        fn has_role(self: @ContractState, role: felt252, account: ContractAddress) -> bool {
            self.access_control.has_role(role, account)
        }

        fn get_role_admin(self: @ContractState, role: felt252) -> felt252 {
            self.access_control.get_role_admin(role)
        }

        fn grant_role(ref self: ContractState, role: felt252, account: ContractAddress) {
            self.access_control.assert_only_role(Roles::DEFAULT_ADMIN_ROLE);
            self.access_control.grant_role(role, account);
        }

        fn revoke_role(ref self: ContractState, role: felt252, account: ContractAddress) {
            self.access_control.assert_only_role(Roles::DEFAULT_ADMIN_ROLE);
            self.access_control.revoke_role(role, account);
        }

        fn renounce_role(ref self: ContractState, role: felt252, account: ContractAddress) {
            self.access_control.assert_only_role(Roles::DEFAULT_ADMIN_ROLE);
            self.access_control.renounce_role(role, account);
        }
    }

    #[abi(embed_v0)]
    impl UpgradeableImpl of IUpgradeable<ContractState> {
        fn upgrade(ref self: ContractState, new_class_hash: ClassHash) {
            self.access_control.assert_only_role(Roles::DEFAULT_ADMIN_ROLE);
            self.upgradeable.upgrade(new_class_hash);
        }
    }
}