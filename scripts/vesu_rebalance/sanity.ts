import { VesuRebalanceStrategies } from "@strkfarm/sdk";
import { getAccount, getRpcProvider } from "../lib/utils";
import { Contract } from "starknet";
import { accountKeyMap, GOVERNOR, RELAYER } from "../lib/constants";
import { getSTRKConfig } from "./deploy_vesu_rebalance";
import { commonSanity, upgradeSanity } from "../lib/sanity";

async function sanity() {
    const VAULT_ADDR = VesuRebalanceStrategies[0].address.address;
    const provider = getRpcProvider();
    const cls = await provider.getClassAt(VAULT_ADDR);
    const contract = new Contract(cls.abi, VAULT_ADDR, provider);

    const gov = getAccount(accountKeyMap[GOVERNOR[0]]);
    // gov should be able to set_settings, set_allowed_pools, set_incentives_off
    const settings = await contract.populate('set_settings', [{
        default_pool_index: 0,
        fee_bps: 1000, // 10%
        fee_receiver: '0x0'
    }])
    const gas = await gov.estimateInvokeFee([settings]);
    console.log(`Has permission to set_settings. Max fee: ${gas.suggestedMaxFee}`);

    const { pools } = await getSTRKConfig();
    const allowedPools = await contract.populate('set_allowed_pools', [
        pools.slice(0, 1)
    ])
    const gas2 = await gov.estimateInvokeFee([allowedPools]);
    console.log(`Has permission to set_allowed_pools. Max fee: ${gas2.suggestedMaxFee}`);

    const incentivesOff = await contract.populate('set_incentives_off', [])
    const gas3 = await gov.estimateInvokeFee([incentivesOff]);
    console.log(`Has permission to set_incentives_off. Max fee: ${gas3.suggestedMaxFee}`);

    // test same actions with non-governor
    const nonGov = getAccount('akira'); // e.g. an example personal account
    try {
        const gas4 = await nonGov.estimateInvokeFee([settings]);
        throw new Error('Should not have permission to set_settings');
    } catch (e) {
        console.log('set_settings permission denied as expected by nonGov');
    }

    try {
        const gas5 = await nonGov.estimateInvokeFee([allowedPools]);
        throw new Error('Should not have permission to set_allowed_pools');
    } catch (e) {
        console.log('set_allowed_pools permission denied as expected by nonGov');
    }

    try {
        const gas6 = await nonGov.estimateInvokeFee([incentivesOff]);
        throw new Error('Should not have permission to set_incentives_off');
    } catch (e) {
        console.log('set_incentives_off permission denied as expected by nonGov');
    }

    const actualClass = await provider.getClassHashAt(VAULT_ADDR);
    await upgradeSanity(VAULT_ADDR, actualClass, ['set_settings', 'set_allowed_pools', 'deposit', 'withdraw', 'upgrade']);
}

if (require.main === module) {
    sanity().catch(console.error);
}