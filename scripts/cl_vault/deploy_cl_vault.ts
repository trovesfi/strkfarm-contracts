import { deployContract, getAccount, getRpcProvider, myDeclare } from "../lib/utils";
import { EKUBO_POSITIONS, EKUBO_CORE, EKUBO_POSITIONS_NFT, ORACLE_OURS, wstETH, ETH, ACCESS_CONTROL} from "../lib/constants";

// Added parameters for pool configuration
function createPoolKey(
    token0: string,
    token1: string,
    fee: string,
    tick_spacing: number,
    extension: number = 0
) {
    return {
        token0,
        token1,
        fee,
        tick_spacing, 
        extension 
    };
}

function createBounds(
    lowerTick: number,
    upperTick: number,
    loweSign: boolean,
    upperSign: boolean
) {
    return {
        lower: {
            mag: lowerTick, 
            sign: loweSign     
        },
        upper: {
            mag: upperTick, 
            sign: upperSign
        }
    };
}

function createFeeSettings(
    feeBps: number,
    collector: string
) {
    return {
        fee_bps: feeBps,      
        fee_collector: collector 
    };
}

async function declareAndDeployConcLiquidityVault(
    token0: string, 
    token1: string, 
    fee: string, 
    tickSpacing: number, 
    extension: number,
    lowerTick: number,
    upperTick: number,
    lowerSign: boolean,
    upperSign: boolean,
    feeBps: number,
    collector: string
) {
    const accessControl = ACCESS_CONTROL;
    const { class_hash } = await myDeclare("ConcLiquidityVault");
    const poolKey = createPoolKey(
        token0,      
        token1,          
        fee, 
        tickSpacing,     
        extension          
    );
    
    const bounds = createBounds(
        lowerTick,      
        upperTick,
        lowerSign,
        upperSign
    );
    
    const feeSettings = createFeeSettings(
        feeBps,        
        collector 
    );

    await deployContract("ConcLiquidityVault", class_hash, {
        name: "ConcLiquidityVault",
        symbol: "CLV",
        access_control: accessControl,
        ekubo_positions_contract: EKUBO_POSITIONS,
        bounds_settings: bounds,
        pool_key: poolKey,
        ekubo_positions_nft: EKUBO_POSITIONS_NFT,
        ekubo_core: EKUBO_CORE,
        oracle: ORACLE_OURS,
        fee_settings: feeSettings
    });
}

// deploy cl vault
declareAndDeployConcLiquidityVault(
    "jfjf",
    "jfjf",
    "fjf",
    12,
    12,
    12,
    12,
    true,
    true,
    12,
    "jff"
);

if (require.main === module) {

}