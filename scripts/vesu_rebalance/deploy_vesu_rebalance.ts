import { deployContract, getAccount, myDeclare } from "../lib/utils";
import { declareAndDeployAccessControl } from "../access_control/deploy_access_control";

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
    asset: string,
    pools: PoolConfig[],
    feeConfig: FeeConfig,
    protocolConfig: ProtocolConfig,
    accessControl?: string
) {
    const { class_hash } = await myDeclare("VesuRebalance", 'strkfarm');
    const controller = accessControl || await declareAndDeployAccessControl();
    
    await deployContract("VesuRebalance", class_hash, {
        asset,
        access_control: controller,
        allowed_pools: pools,
        settings: feeConfig,
        vesu_settings: protocolConfig
    });
}