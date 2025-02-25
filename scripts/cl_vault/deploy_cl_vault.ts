import { deployContract, getAccount, getRpcProvider, myDeclare } from "../lib/utils";
import { 
    STRK,
    USDC,
    EKUBO_POSITIONS,
    EKUBO_CORE,
    EKUBO_POSITIONS_NFT,
    ORACLE_OURS,
    wstETH,
    ETH,
} from "../lib/constants";

function createPoolKey() {
    return {
        token0: wstETH,
        token1: ETH,
        fee: '34028236692093847977029636859101184',
        tick_spacing: 200,
        extension: 0
    };
}

function createBounds() {
    return {
        lower: {
            mag: 160000,
            sign: false
        },
        upper: {
            mag: 18000,
            sign: false
        }
    };
}

function createFeeSettings() {
    let acc = getAccount('strkfarmadmin')
    return {
        fee_bps: 1000,
        fee_collector: acc.address
    };
}

async function declareAndDeployConcLiquidityVault() {
    const accessControl = await declareAndDeployAccessControl();
    const { class_hash } = await myDeclare("ConcLiquidityVault", 'strkfarm');
    const poolKey = createPoolKey(); 
    const bounds = createBounds();
    const feeSettings = createFeeSettings();
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

async function declareAndDeployAccessControl() {
    const acc = getAccount('strkfarmadmin');
    const { class_hash } = await myDeclare("AccessControl", 'strkfarm');
    const tx = await deployContract("AccessControl", class_hash, {
        owner: acc.address,
        governor_address: acc.address,
        relayer_address: acc.address,
        emergency_address: acc.address
    });
    return tx.contract_address;
}
