import { Contract } from "starknet";
import { getAccount, getRpcProvider } from "./utils";
import { accountKeyMap, SUPER_ADMIN } from "./constants";
import { executeBatch, scheduleBatch } from "../timelock/actions";

export async function commonSanity(addr: string, newClassHash: string) {
    await upgradeSanity(addr, newClassHash);
    console.log('Upgrade Sanity check passed');
}

export async function upgradeSanity(vault: string, newClassHash: string, expectedFunctionsInNewClass: string[] = []) {
    const provider = getRpcProvider();
    const vaultCls = await provider.getClassAt(vault);
    const vaultContract = new Contract(vaultCls.abi, vault, provider);

    if (expectedFunctionsInNewClass.length > 0) {
        const newCls = await provider.getClassByHash(newClassHash);
        const abiString = JSON.stringify(newCls.abi);
        for (let i = 0; i < expectedFunctionsInNewClass.length; i++) {
            if (!abiString.includes(expectedFunctionsInNewClass[i])) {
                throw new Error(`Function ${expectedFunctionsInNewClass[i]} not found in new class`);
            }
        }
        console.log('All expected functions found in new class');
    }

    // todo add timelock support
    const superAdmin = getAccount(accountKeyMap[SUPER_ADMIN]);
    const upgrade = await vaultContract.populate('upgrade', [newClassHash]);
    const salt = new Date().getTime().toString();
    const scheduleCall = await scheduleBatch([upgrade], salt, '0x0', true);
    const executeCall = await executeBatch([upgrade], salt, '0x0', true);
    if (!scheduleCall || !executeCall) {
        throw new Error('Error in creating scheduleCall or executeCall');
    }
    const gas = await superAdmin.estimateInvokeFee([...scheduleCall, ...executeCall]);
    console.log(`Has permission to upgrade. Max fee: ${gas.suggestedMaxFee}`);

    const nonAdmin = getAccount('akira'); // e.g. an example personal account
    try {
        const gas2 = await nonAdmin.estimateInvokeFee([upgrade]);
        throw new Error('Should not have permission to upgrade');
    } catch (e) {
        console.log('Upgrade permission denied as expected by nonAdmin');
    }
}