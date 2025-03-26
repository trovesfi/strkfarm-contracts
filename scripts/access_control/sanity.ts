import { Contract, hash } from "starknet";
import { ACCESS_CONTROL, GOVERNOR, RELAYER, SUPER_ADMIN, TIMELOCK } from "../lib/constants";
import { getRpcProvider } from "../lib/utils"

export async function accessControlSanity() {
    const provider = getRpcProvider();
    const cls = await provider.getClassAt(ACCESS_CONTROL);
    const accessControl = new Contract(cls.abi, ACCESS_CONTROL, provider);

    const expectedRoles = [{
        name: '0', // DEFAULT_ADMIN_ROLE
        address: TIMELOCK,
        roleAdmin: 0,
    }, ...GOVERNOR.map((gov) => ({
        name: hash.getSelectorFromName('GOVERNOR'),
        address: gov,
        roleAdmin: 0,
    })), {
        name: hash.getSelectorFromName('RELAYER'),
        address: RELAYER,
        roleAdmin: 0,
    }, {
        name: hash.getSelectorFromName('EMERGENCY_ACTOR'),
        address: RELAYER,
        roleAdmin: 0,
    }]
    
    for (let i = 0; i < expectedRoles.length; i++) {
        const role = await accessControl.call('has_role', [expectedRoles[i].name, expectedRoles[i].address]);
        if (role !== true) {
            throw new Error(`${expectedRoles[i].address} does not have role ${expectedRoles[i].name}`);
        }
        console.log(`Role ${expectedRoles[i].name} has correct admin`);

        const roleAdmin: any = await accessControl.call('get_role_admin', [expectedRoles[i].name]);
        if (roleAdmin != expectedRoles[i].roleAdmin) {
            throw new Error(`Role ${expectedRoles[i].name} does not have admin ${roleAdmin}`);
        }
        console.log(`Role ${expectedRoles[i].name} has admin ${roleAdmin}`);
    }
}

if (require.main === module) {
    accessControlSanity().catch(console.error);
}