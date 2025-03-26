import { TransactionExecutionStatus } from "starknet";
import { EMERGENCY_ACTORS, RELAYER, SUPER_ADMIN } from "../lib/constants";
import { ACCOUNT_NAME, getAccount, getRpcProvider } from "../lib/utils"

async function run() {
    // Verified timelock contract on walnut, used by endur
    // https://app.walnut.dev/contracts/0x065261df7fe10ab989251b315aab95ccdba68fc503855bb557c555a723f828e2
    /**
     * Their pause/unpause functions are not required, bcz this func is only callable by the emergency actors
     */
    const class_hash = '0x06aa60b9d99be4577c55be9ae9f53fe9ceee5fa822ab3837b786ebb2516eeb36'

    const acc = getAccount(ACCOUNT_NAME);
    const tx = await acc.deployContract({
        classHash: class_hash,
        constructorCalldata: {
            min_delay: 0,
            proposers: [SUPER_ADMIN],
            executors: [SUPER_ADMIN, RELAYER],
            pausors: [...EMERGENCY_ACTORS],
            admin: SUPER_ADMIN,
            lst: "0" // doesn't matter here
        },
        unique: true,
    });
    console.log('Deploy tx: ', tx.transaction_hash);
    await getRpcProvider().waitForTransaction(tx.transaction_hash, {
        successStates: [TransactionExecutionStatus.SUCCEEDED]
    })
    console.log(`Contract deployed: Timelock`)
}

if (require.main === module) {
    run()
}