import { Contract, hash, TransactionExecutionStatus, uint256 } from "starknet";
import { ACCESS_CONTROL, accountKeyMap, GOVERNOR, RELAYER, STRK, SUPER_ADMIN, TIMELOCK } from "../lib/constants";
import { ACCOUNT_NAME, deployContract, getAccount, getRpcProvider, myDeclare } from "../lib/utils";
import { executeBatch, scheduleBatch } from "../timelock/actions";

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

async function transferSuperAdmin() {
    const acc = getAccount(ACCOUNT_NAME);
    const provider = getRpcProvider();
    const cls = await provider.getClassAt(ACCESS_CONTROL);
    const accessControl = new Contract(cls.abi, ACCESS_CONTROL, provider);

    const call = await accessControl.populate("grant_role", [
        "0", // DEFAULT ADMIN ROLE
        TIMELOCK
    ]);
    // renounce
    const call2 = await accessControl.populate("renounce_role", [
        "0", // DEFAULT ADMIN ROLE
        acc.address
    ]); 
    const tx = await acc.execute([call, call2]);
    console.log(`Transfered super admin to timelock. tx: ${tx.transaction_hash}`);
    await provider.waitForTransaction(tx.transaction_hash, {
        successStates: [TransactionExecutionStatus.SUCCEEDED]
    });
    console.log(`Super admin transferred to timelock`);
}

async function addGovernor() {
    const acc = getAccount(accountKeyMap[SUPER_ADMIN]);
    const provider = getRpcProvider();
    const cls = await provider.getClassAt(ACCESS_CONTROL);
    const accessControl = new Contract(cls.abi, ACCESS_CONTROL, provider);

    const calls = GOVERNOR.map((gov) => {
        return accessControl.populate("grant_role", [
            hash.getSelectorFromName('GOVERNOR'),
            gov
        ]);
    });

    const scheduleCall = await scheduleBatch(calls, "0", "0x0", true);
    const executeCall = await executeBatch(calls, "0", "0x0", true);
    const tx = await acc.execute([...scheduleCall, ...executeCall]);
    console.log(`Added governors. tx: ${tx.transaction_hash}`);
    await provider.waitForTransaction(tx.transaction_hash, {
        successStates: [TransactionExecutionStatus.SUCCEEDED]
    });
    console.log(`Governors added`);
}

async function renounceRole() {
    const acc = getAccount(accountKeyMap[SUPER_ADMIN]);
    const provider = getRpcProvider();
    const cls = await provider.getClassAt(ACCESS_CONTROL);
    const accessControl = new Contract(cls.abi, ACCESS_CONTROL, provider);

    const call = await accessControl.populate("renounce_role", [
        hash.getSelectorFromName('GOVERNOR'),
        getAccount(ACCOUNT_NAME).address
    ]);
    const scheduleCall = await scheduleBatch([call], "0", "0x0", true);
    const executeCall = await executeBatch([call], "0", "0x0", true);
    const tx = await acc.execute([...scheduleCall, ...executeCall]);
    console.log(`Renounced role. tx: ${tx.transaction_hash}`);
    await provider.waitForTransaction(tx.transaction_hash, {
        successStates: [TransactionExecutionStatus.SUCCEEDED]
    });
    console.log(`Role renounced`);
}

if (require.main === module) {
    // declareAndDeployAccessControl().then(console.log).catch(console.error);
    // transferSuperAdmin().catch(console.error);
    // addGovernor().catch(console.error);
    renounceRole().catch(console.error);
}