import { byteArray, Contract, num } from "starknet";
import { ACCESS_CONTROL, ETH, ORACLE_OURS, STRK, USDC } from "../lib/constants";
import { deployContract, getAccount, getRpcProvider, myDeclare } from "../lib/utils";
import { ContractAddr, VesuRebalance, VesuRebalanceStrategies } from "@strkfarm/sdk";

type PoolConfig = {
    pool_id: string; 
    max_weight: number;
    v_token: string;
};

type FeeConfig = {
    default_pool_index: number; 
    fee_bps: number; 
    fee_receiver: string;
};

type ProtocolConfig = {
    singleton: string; 
    pool_id: string; 
    debt: string; 
    collateral: string; 
    oracle: string; 
};

async function deployVesuRebalance(
    name: string,
    symbol: string,
    asset: string,
    pools: PoolConfig[],
    feeConfig: FeeConfig,
    protocolConfig: ProtocolConfig,
) {
    const { class_hash } = await myDeclare("VesuRebalance");
    const controller = ACCESS_CONTROL;
    
    await deployContract("VesuRebalance", class_hash, {
        name: byteArray.byteArrayFromString(name),
        symbol: byteArray.byteArrayFromString(symbol),
        asset,
        access_control: controller,
        allowed_pools: pools,
        settings: feeConfig,
        vesu_settings: protocolConfig
    });
}

const POOL_IDs = {
    GENESIS: '0x4dc4f0ca6ea4961e4c8373265bfd5317678f4fe374d76f3fd7135f57763bf28',
    Re7_xSTRK: '0x52fb52363939c3aa848f8f4ac28f0a51379f8d1b971d8444de25fbd77d8f161',
    Re7_Eco: '0x6febb313566c48e30614ddab092856a9ab35b80f359868ca69b2649ca5d148d',
    Re7_steth: '0x59ae5a41c9ae05eae8d136ad3d7dc48e5a0947c10942b00091aeb7f42efabb7',
    Alterscope_CASH: '0x7bafdbd2939cc3f3526c587cb0092c0d9a93b07b9ced517873f7f6bf6c65563',
    Re7_USDC: '0x7f135b4df21183991e9ff88380c2686dd8634fd4b09bb2b5b14415ac006fe1d',
    Alterscope_xSTRK: '0x27f2bb7fb0e232befc5aa865ee27ef82839d5fad3e6ec1de598d0fab438cb56',
    Alterscope_steth: '0x5c678347b60b99b72f245399ba27900b5fc126af11f6637c04a193d508dda26',
    Alterscope_cornerstone: '0x2906e07881acceff9e4ae4d9dacbcd4239217e5114001844529176e1f0982ec'
}

const FEE_RECEIVER = '0x06419f7DeA356b74bC1443bd1600AB3831b7808D1EF897789FacFAd11a172Da7';
const SINGLETON = '0x02545b2e5d519fc230e9cd781046d3a64e092114f07e44771e0d719d148725ef';

async function getVTokens(pools: PoolConfig[], asset: string) {
    const provider = getRpcProvider();
    const singletonCls = await provider.getClassAt(SINGLETON);
    const singletonContract = new Contract(singletonCls.abi, SINGLETON, provider);

    let _pools: PoolConfig[] = [];
    for (let i = 0; i < pools.length; i++) {
        let pool = pools[i];
        const extension: any = await singletonContract.call('extension', [pool.pool_id]);
        const extensionCls = await provider.getClassAt(extension);
        const extensionContract = new Contract(extensionCls.abi, num.getHexString(extension.toString()), provider);
        const vToken = await extensionContract.call('v_token_for_collateral_asset', [pool.pool_id, asset]);
        console.log(`vToken for pool ${pool.pool_id}: ${num.getHexString(vToken.toString())}`);
        _pools.push({
            pool_id: pool.pool_id,
            max_weight: pool.max_weight,
            v_token: num.getHexString(vToken.toString())
        });
    }
    return _pools;
}

const trustedPools = ['Genesis', 'Re7'];
const midWeightPools = ['Re7 xSTRK'];

function getPoolWeights(allPools: any) {
    return allPools.filter(pool => !pool.name.includes('sSTRK'))
    .map((pool) => {
        const doesTrustPoolNameIncluded = trustedPools.some((trustedPool) => pool.name.includes(trustedPool));
        const doesMidWeightPoolNameIncluded = midWeightPools.some((midWeightPool) => pool.name.includes(midWeightPool));
        const weight = doesMidWeightPoolNameIncluded ? 10000 : doesTrustPoolNameIncluded ? 10000 : 2000;
        const item = {
            pool_id: pool.pool_id.address,
            max_weight: weight,
            v_token: pool.v_token.address
        }
        console.log("item", {...item, name: pool.name});
        return item;
    })
}

export async function getSTRKConfig() {
    const allPools = await VesuRebalance.getAllPossibleVerifiedPools(ContractAddr.from(STRK));
    const pools = getPoolWeights(allPools);
    
    console.log(pools);
    // const pools = await getVTokens(_pools, STRK);

    return {
        asset: STRK,
        pools,
        name: 'STRK',
    }
}

async function getETHConfig() {
    const allPools = await VesuRebalance.getAllPossibleVerifiedPools(ContractAddr.from(ETH));
    const pools = getPoolWeights(allPools);

    return {
        asset: ETH,
        pools,
        name: 'ETH',
    }
}

async function getUSDCConfig() {
    const allPools = await VesuRebalance.getAllPossibleVerifiedPools(ContractAddr.from(USDC));
    const pools = getPoolWeights(allPools);

    return {
        asset: USDC,
        pools,
        name: 'USDC',
    }
}

if (require.main === module) {

    async function run() {
        // const { asset, pools, name } = await getSTRKConfig();
        // const { asset, pools, name } = await getETHConfig();
        const { asset, pools, name } = await getUSDCConfig();
        const feeConfig = {
            default_pool_index: 0,
            fee_bps: 1000, // 10%
            fee_receiver: FEE_RECEIVER
        };
    
        const protocolConfig = {
            singleton: SINGLETON,
            pool_id: "0",
            debt: "0",
            collateral: asset,
            oracle: ORACLE_OURS
        };

        const _name = `Vesu Fusion ${name}`;
        const symbol = `vf${name}`;
        await deployVesuRebalance(_name, symbol, asset, pools, feeConfig, protocolConfig);
    }

    run()
}