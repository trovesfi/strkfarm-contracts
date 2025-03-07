import { RELAYER } from "../lib/constants";
import { ACCOUNT_NAME, deployContract, getAccount, getRpcProvider, myDeclare } from "../lib/utils";

export async function declareAndDeployAccessControl() {
    const acc = getAccount(ACCOUNT_NAME);
    const { class_hash } = await myDeclare("AccessControl");
    
    const tx = await deployContract("AccessControl", class_hash, {
        owner: acc.address,
        governor_address: acc.address,
        relayer_address: RELAYER,
        emergency_address: RELAYER,
    });
    return tx.contract_address;
}

if (require.main === module) {
    declareAndDeployAccessControl().then(console.log).catch(console.error);
}