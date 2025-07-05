import { ContractAddr, DualActionAmount, EkuboCLVault, EkuboCLVaultStrategies, getMainnetConfig, Global, Pricer, PricerFromApi, PricerRedis, Web3Number } from "@strkfarm/sdk";
import { getAccount, getRpcProvider } from "../lib/utils";
import { STRK, xSTRK } from "../lib/constants";

async function main() {
    const provider = getRpcProvider();
    const config = getMainnetConfig();
    // const pricer = new PricerRedis(config, await Global.getTokens());
    // await pricer.initRedis(process.env.REDIS_URL!);
    const pricer = new PricerFromApi(config, await Global.getTokens());
    console.log('Pricer ready');

    const mod = new EkuboCLVault(config, pricer, EkuboCLVaultStrategies[1]);

    const user = ContractAddr.from('0x0055741fd3ec832f7b9500e24a885b8729f213357be4a8e209c4bca1f3b909ae')
    const userTVL = await mod.getUserTVL(user);
    console.log(`User TVL: ${JSON.stringify(userTVL)}`);

    const tvl = await mod.getTVL();
    console.log(`TVL: ${JSON.stringify(tvl)}`);

    const apy = await mod.netAPY();
    console.log(`Net APY: ${JSON.stringify(apy)}`);
    // 21.05884839475128
    // const myDepositAmounts = {
    //     token0: {
    //         tokenInfo: {
    //             name: 'xSTRK',
    //             symbol: 'xSTRK',
    //             decimals: 18,
    //             logo: '',
    //             address: ContractAddr.from(xSTRK)
    //         },
    //         amount: new Web3Number(1, 18)
    //     },
    //     token1: {
    //         tokenInfo: {
    //             name: 'STRK',
    //             symbol: 'STRK',
    //             decimals: 18,
    //             logo: '',
    //             address: ContractAddr.from(STRK)
    //         },
    //         amount: new Web3Number(1, 18)
    //     }
    // }
    // const depositAmounts = await mod.getDepositAmounts(myDepositAmounts);
    // console.log(`Deposit amounts: token0: ${depositAmounts.token0.amount}, token1: ${depositAmounts.token1.amount}`);
    
    // const acc = getAccount('strkfarmadmin');
    // const caller = ContractAddr.from(acc.address);

    // const depositCalls = await mod.depositCall(myDepositAmounts, caller);
    // const tx = await acc.execute(depositCalls);
    // console.log(`Deposit tx: ${tx.transaction_hash}`);
    // await provider.waitForTransaction(tx.transaction_hash, {
    //     successStates: ['SUCCEEDED']
    // });
    // console.log('Deposit done');

    // const myShares = await mod.balanceOf(caller);
    // console.log(`My shares: ${myShares}`);

    // const userTVL2 = await mod.getUserTVL(caller);
    // console.log(`User TVL: ${JSON.stringify(userTVL2)}`);
    // const withdrawAmounts: DualActionAmount = {
    //     token0: {
    //         tokenInfo: userTVL2.token0.tokenInfo,
    //         amount: userTVL2.token0.amount.dividedBy(1)
    //     },
    //     token1: {
    //         tokenInfo: userTVL2.token1.tokenInfo,
    //         amount: userTVL2.token1.amount.dividedBy(1)
    //     }
    // }
    // const withdrawCalls = await mod.withdrawCall(withdrawAmounts, caller, caller);
    // const tx = await acc.execute(withdrawCalls);
    // console.log(`Withdraw tx: ${tx.transaction_hash}`);
    // await provider.waitForTransaction(tx.transaction_hash, {
    //     successStates: ['SUCCEEDED']
    // });
    // console.log('Withdraw done');
}

async function harvest() {
    const provider = getRpcProvider();
    const config = getMainnetConfig();
    const pricer = new PricerFromApi(config, await Global.getTokens());
    console.log('Pricer ready');

    const mod = new EkuboCLVault(config, pricer, EkuboCLVaultStrategies[0]);
    const riskAcc = getAccount('risk-manager', 'accounts-risk.json', process.env.ACCOUNT_SECURE_PASSWORD_RISK);
    const calls = await mod.harvest(riskAcc);
    if (calls.length) {
        // console.log('harvest ready');
        const tx = await riskAcc.execute(calls);
        console.log(`Harvest tx: ${tx.transaction_hash}`);
        await provider.waitForTransaction(tx.transaction_hash, {
            successStates: ['SUCCEEDED']
        });
        console.log('Harvest done');
    } else {
        console.log('No harvest calls');
    }
}

if (require.main === module) {
    // main();
    harvest();
}