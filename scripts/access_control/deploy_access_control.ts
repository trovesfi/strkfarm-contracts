import { deployContract, getAccount, getRpcProvider, myDeclare } from "../lib/utils";

export async function declareAndDeployAccessControl() {
    const acc = getAccount('strkfarmadmin');
    const { class_hash } = await myDeclare("AccessControl", 'strkfarm');
    const tx = await deployContract("AccessControl", class_hash, {
        owner: acc.address,
        governor_address: acc.address,
        relayer_address: acc.address,
        emergency_address: acc.address
    });
    return tx.contract_address;
}
