import { deployContract, getAccount, getRpcProvider, myDeclare } from "../lib/utils";
import { VESU_GENESIS_POOL, GENESIS_V_TOKEN, RE7_XSTRK_POOL, RE7_XSTRK_V_TOKEN, RE7_SSTRK_POOL, RE7_SSTRK_V_TOKEN, RE7_USDC_POOL, RE7_USDC_V_TOKEN, STRK, VESU_SINGLETON, ORACLE_OURS } from "../lib/constants";

type PoolProps = {
    pool_id: string; 
    max_weight: number;
    v_token: string;
};

type Settings = {
    default_pool_index: number; 
    fee_bps: number; 
    fee_receiver: string;
};

type VesuStruct = {
    singleton: string; 
    pool_id: string; 
    debt: string; 
    col: string; 
    oracle: string; 
};


function createAllowedPools() {
    let allowed_pools: PoolProps[] = [];

    return {
        addPool: (pool_id: string, max_weight: number, v_token: string) => {
            allowed_pools.push({ pool_id, max_weight, v_token });
        },
        getPools: (): PoolProps[] => allowed_pools
    };
}

function getDefaultSettings(): Settings {
    return {
        default_pool_index: 0, 
        fee_bps: 500, 
        fee_receiver: "0xFeeReceiverAddress" 
    };
}

function getDefaultVesuStruct(): VesuStruct {
    return {
        singleton: VESU_SINGLETON,
        pool_id: "0", 
        debt: "0", 
        col: STRK, 
        oracle: ORACLE_OURS 
    };
}

async function declareAndDeployVesuRebalance() {
    const {class_hash } = await myDeclare("VesuRebalance", 'strkfarm');
    let allowed_pools = createAllowedPools();
    allowed_pools.addPool(VESU_GENESIS_POOL, 5000, GENESIS_V_TOKEN);
    allowed_pools.addPool(RE7_XSTRK_POOL, 4000, RE7_XSTRK_V_TOKEN);
    allowed_pools.addPool(RE7_SSTRK_POOL, 3000, RE7_SSTRK_V_TOKEN);
    allowed_pools.addPool(RE7_USDC_POOL, 1000, RE7_USDC_V_TOKEN);
    let settings = getDefaultSettings();
    let vesu_settings = getDefaultVesuStruct();
    let access_control = await declareAndDeployAccessControl();
    await deployContract("VesuRebalance", class_hash, {
        asset: STRK,
        access_control: access_control,
        allowed_pools: allowed_pools,
        settings: settings,
        vesu_settings: vesu_settings
    })
}

async function declareAndDeployAccessControl() {
    const acc = getAccount('strkfarmadmin')
    const {class_hash} = await myDeclare("AccessControl", 'strkfarm')
    let tx = await deployContract("AccessControl", class_hash, {
        owner: acc.address,
        governor_address: acc.address,
        relayer_address: acc.address,
        emergency_address: acc.address
    })

    return tx.contract_address
}