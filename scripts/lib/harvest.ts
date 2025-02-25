import { Account, Call, Contract, TransactionExecutionStatus, Uint256, num, number, uint256 } from "starknet";
import { getAccount, getRpcProvider } from "./utils";
import axios from 'axios';
import { ETH, STRK, USDC, xSTRK } from "./constants";
import { fetchBuildExecuteTransaction, fetchQuotes } from "@avnu/avnu-sdk";
import { assert, formatUnits } from "ethers";
import { TelegramNotif, PricerRedis } from "@strkfarm/sdk";

export const ACCOUNT_NAME = 'strkfarmadmin'

interface Route {
    token_from: string,
    token_to: string,
    exchange_address: string,
    percent: number,
    additional_swap_params: string[]
}

interface SwapInfo {
    token_from_address: string, 
    token_from_amount: Uint256, 
    token_to_address: string,   
    token_to_amount: Uint256, 
    token_to_min_amount: Uint256,  
    beneficiary: string,  
    integrator_fee_amount_bps: number,
    integrator_fee_recipient: string,
    routes: Route[]
}

interface Settings {
    rewardsContract: string,
    depositMarket: string,
    lendClassHash: string,
    swapClassHash: string
}

async function harvestAutoToken(
    address: string,
    claimId: number,
    amount: string,
    proofs: string[],
    swapInfo: SwapInfo,
    settings: Settings | null
) {
    const provider = getRpcProvider();
    const acc: Account = <any>getAccount(ACCOUNT_NAME);
    const classHash = await provider.getClassAt(address);
    const contract = new Contract(classHash.abi, address, provider);
    contract.connect(acc);

    let calls: Call[] = [];
    if (settings) {
        const call = contract.populate('set_settings', {
            settings
        })
        calls.push(call)
    }

    const call = contract.populate('harvest', {
        claim: {
            id: claimId,
            claimee: address,
            amount: amount
        },
        proof: proofs,
        swapInfo
    })
    console.log('call', JSON.stringify(call))
    calls.push(call)
    const tx = await acc.execute(calls);
    console.log('txhash', tx.transaction_hash)
    await provider.waitForTransaction(tx.transaction_hash, {
        successStates: [TransactionExecutionStatus.SUCCEEDED]
    })
    console.log('Done')
}

async function getPriceCoinbase(tokenSymbol: string) {
    const url = `https://api.coinbase.com/v2/prices/${tokenSymbol}-USD/buy`;
    const result = await axios.get(url)
    const data: any = result.data;
    return Number(data.data.amount);
}


async function harvestAutoStrk() {
    console.log('harvesting STRK')
    const address = '0x541681b9ad63dff1b35f79c78d8477f64857de29a27902f7298f7b620838ea';
    const result = await getzklendProofs(address);
    const claimId = result.claimId;
    const amount = result.amount;
    const proofs = result.proofs;
    let settings: Settings = {
        rewardsContract: result.claimContract,
        depositMarket: '0x04c0a5193d58f74fbace4b74dcf65481e734ed1714121bdc571da345540efa05',
        lendClassHash: '0x6f9c4e995d20490d46e3e743a052ad5b728bc5b58c4281f058f7242ac247ed9',
        swapClassHash: '0x56c809dd30d3c06e772f82a91d19e2b8553e538ff7e6699b06c82fc4b796eaf'
    }
    const swapInfo: SwapInfo = {
        token_from_address: "0", 
        token_from_amount: uint256.bnToUint256("0"), 
        token_to_address: "0",   
        token_to_amount: uint256.bnToUint256("0"), 
        token_to_min_amount: uint256.bnToUint256("0"),  
        beneficiary: "0",  
        integrator_fee_amount_bps: 0,
        integrator_fee_recipient: "0",
        routes: []
    }
    await harvestAutoToken(address, claimId, amount, proofs, swapInfo, settings);
}

function getRoute(toToken: string): Route {
    const pairMap: any = {}
    pairMap[USDC] = "0x42543c7d220465bd3f8f42314b51f4f3a61d58de3770523b281da61dbf27c8a"
    pairMap[ETH] = '0x068400056dccee818caa7e8a2c305f9a60d255145bac22d6c5c9bf9e2e046b71'
    return {
        token_from: STRK,
        token_to: toToken,
        exchange_address: "0x49ff5b3a7d38e2b50198f408fa8281635b5bc81ee49ab87ac36c8324c214427", //nostra
        percent: 1000000000000,
        additional_swap_params: [
            pairMap[toToken]
        ]
    }
}

async function harvestAutoUSDC() {
    console.log('harvesting USDC')
    const address = '0x016912b22d5696e95ffde888ede4bd69fbbc60c5f873082857a47c543172694f';
    const result = await getzklendProofs(address);
    const claimId = result.claimId;
    const amount = result.amount;
    const proofs = result.proofs;
    let settings: Settings = {
        rewardsContract: result.claimContract,
        depositMarket: '0x04c0a5193d58f74fbace4b74dcf65481e734ed1714121bdc571da345540efa05',
        lendClassHash: '0x6f9c4e995d20490d46e3e743a052ad5b728bc5b58c4281f058f7242ac247ed9',
        swapClassHash: '0x56c809dd30d3c06e772f82a91d19e2b8553e538ff7e6699b06c82fc4b796eaf'
    }

    const STRK = '0x4718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d'
    const USDC = '0x053c91253bc9682c04929ca02ed00b3e423f6710d2ee7e0d5ebb06f3ecf368a8'
    const route: Route = getRoute(USDC);
    const acc: Account = <any>getAccount(ACCOUNT_NAME);
    // ! REMEMBER TO SET THIS
    const CURRENT_PRICE = (await getPriceCoinbase('STRK')) * 95 / 100;
    const MIN_OUT = ((CURRENT_PRICE * parseInt(result.amount) / 10 ** 18) * 10**6).toFixed(0);
    console.log(`min out: ${MIN_OUT}`);
    console.log(`amount: ${amount}`);
    const swapInfo: SwapInfo = {
        token_from_address: STRK, 
        token_from_amount: uint256.bnToUint256(amount), 
        token_to_address: USDC,   
        token_to_amount: uint256.bnToUint256("0"), 
        token_to_min_amount: uint256.bnToUint256(MIN_OUT),  
        beneficiary: address,  
        integrator_fee_amount_bps: 0,
        integrator_fee_recipient: acc.address,
        routes: [route]
    }
    await harvestAutoToken(address, claimId, amount, proofs, swapInfo, settings);
}

interface ProofOutput {
    proofs: string[],
    amount: string,
    claimContract: string,
    claimId: number
}

async function getzklendProofs(address: string): Promise<ProofOutput> {
    const DATA_INDEX = 0;
    const result = await axios.get(`https://app.zklend.com/api/reward/all/${address}`);
    const data = result.data;
    if (data[DATA_INDEX].claimed) {
        throw new Error("zkLend: already claimed");
    }
    const proofs = data[DATA_INDEX].proof;
    const amount = data[DATA_INDEX].amount.value;
    const claimContract = data[DATA_INDEX].claim_contract
    const claimId = data[DATA_INDEX].claim_id

    return {
        proofs,
        amount,
        claimContract,
        claimId
    }
}

async function getNostraProofs(address: string, retry = 0): Promise<ProofOutput> {
    try {
        let data = JSON.stringify({
            "dataSource": "nostra-production",
            "database": "prod-a-nostra-db",
            "collection": "rewardProofs",
            "filter": {
            "account": address
            }
        });
        
        let config = {
            method: 'post',
            maxBodyLength: Infinity,
            url: 'https://us-east-2.aws.data.mongodb-api.com/app/data-yqlpb/endpoint/data/v1/action/find',
            data : data
        };
        const result = (await axios.request(config)).data.documents;
        console.log(`nostra total claims: ${result.length}`);

        // get claim contract
        const result2 = await fetch('https://kx58j6x5me.execute-api.us-east-1.amazonaws.com/starknet/fetchFile?file=address_settings/settings.json');
        const RawContracts: any = await result2.json();
        let claimContract = ''
        let date = new Date(0);
        for(let i=0; i<RawContracts.length; ++i) {
            const contract = RawContracts[i]
            if (contract['Protocol Name'] == 'Nostra' && contract['Vertical'] == 'Money Market') {
                claimContract = contract['Address'];
                date = new Date(contract['Grant Period Distribution Date'])
            }
        }
        if (!claimContract) {
            throw new Error('No Nostra contract found')
        } else {
            // asserts its in last 4-5 days
            let now = new Date();
            if (now.getTime() - date.getTime() > 5 * 24 * 60 * 60 * 1000) {
                throw new Error('Nostra contract is too old')
            }
            console.log(`Nostra contract: ${claimContract}`)
            console.log(`Nostra contract date: ${date}`)
        }

        if(!result.length) {
            return {
                proofs: [],
                amount: "1", // to bypass contract check
                claimContract,
                claimId: 0
            }
        }
        const proofs = result[result.length - 1].proofs;
        const amount = result[result.length - 1].reward;

        return {
            proofs,
            amount,
            claimContract,
            claimId: 0
        }
    } catch(err) {
        if (retry < 10) {
            await new Promise((resolve) => setTimeout(resolve, 5000));
            return await getNostraProofs(address, retry + 1)
        } else {
            throw err;
        }
    }
}

async function getVesuProofs(address: string): Promise<ProofOutput> {
    const result = await axios.get(`https://api.vesu.xyz/users/${address}/strk-rewards/calldata`);
    return {
        claimContract: '0x0387f3eb1d98632fbe3440a9f1385Aec9d87b6172491d3Dd81f1c35A7c61048F',
        proofs: result.data.data.proof,
        claimId: 0,
        amount: result.data.data.amount
    }
}

async function getDummyProofs(address: string): Promise<ProofOutput> {
    return {
        claimContract: '0',
        proofs: [],
        claimId: 0,
        amount: '0'
    }
}

interface Claim {
    id: string,
    claimee: string,
    amount: string
}

async function doubleHarvest(
    address: string,
    protocol1_rewards_contract: string,
    claim1: Claim,
    proof1: string[],
    protocol2_rewards_contract: string,
    claim2: Claim,
    proof2: string[],
    swapInfo: SwapInfo
) {
    const provider = getRpcProvider();
    const acc: Account = <any>getAccount(ACCOUNT_NAME);
    const classHash = await provider.getClassAt(address);
    const contract = new Contract(classHash.abi, address, provider);
    contract.connect(acc);

    let calls: Call[] = [];
    const data = {
        protocol1_rewards_contract,
        claim1,
        proof1,
        protocol2_rewards_contract,
        claim2,
        proof2,
        swapInfo
    };
    const call = contract.populate('harvest', data);
    calls.push(call)
    const tx = await acc.execute(calls);
    console.log('txhash', tx.transaction_hash);
    await provider.waitForTransaction(tx.transaction_hash, {
        successStates: [TransactionExecutionStatus.SUCCEEDED]
    })
    console.log('Done')
}



async function harvestDNMM(
    address: string, 
    decimals: number, 
    tokenAddr: string, 
    tokenName: string,
    firstProof: (addr: string) => Promise<ProofOutput> = getzklendProofs,
    secondProof: (addr: string) => Promise<ProofOutput> = getNostraProofs
) {
    console.log(`harvesting ${address}`)
    const zkLendProofInfo = await firstProof(address);
    const nostraProofInfo = await secondProof(address);

    const acc = getAccount(ACCOUNT_NAME);
    // ! REMEMBER TO SET THIS
    const STRK_PRICE = (await getPriceCoinbase('STRK')) * 95 / 100;
    const TO_TOKEN_PRICE = (await getPriceCoinbase(tokenName)) * 105 / 100;

    let totalAmount = BigInt(zkLendProofInfo.amount);
    if (nostraProofInfo.proofs.length > 0) {
        totalAmount += BigInt(nostraProofInfo.amount);
    }
    if (zkLendProofInfo.proofs.length == 0) {
        totalAmount = BigInt(nostraProofInfo.amount);
    }
    const MIN_OUT = BigInt((((STRK_PRICE * parseInt(totalAmount.toString()) / 10 ** 18) / TO_TOKEN_PRICE) * 10**decimals)).toString();
    console.log('totalAmount', totalAmount.toString());
    console.log('min out', MIN_OUT);

    const swapInfo = await getSwapInfo(STRK, tokenAddr, totalAmount.toString(), address, MIN_OUT);
    await doubleHarvest(
        address, 
        zkLendProofInfo.claimContract, 
        {
            id: zkLendProofInfo.claimId.toString(),
            claimee: address,
            amount: zkLendProofInfo.amount
        },
        zkLendProofInfo.proofs,
        nostraProofInfo.claimContract,
        {
            id: nostraProofInfo.claimId + '',
            claimee: address,
            amount: nostraProofInfo.amount
        },
        nostraProofInfo.proofs,
        swapInfo
    );
}

async function getSwapInfo(
    fromToken: string,
    toToken: string,
    amountWei: string,
    taker: string,
    minAmount = "0"
) {
    const params: any = {
        sellTokenAddress: fromToken,
        buyTokenAddress: toToken,
        sellAmount: amountWei,
        takerAddress: taker,
    };
    console.log(params);
    const routes: Route[] = [];
    if (fromToken != toToken) {
        const quotes = await fetchQuotes(params);
        assert(quotes.length > 0, 'No quotes found', 'NETWORK_ERROR');
        console.log(quotes);
        const calldata = await  fetchBuildExecuteTransaction(quotes[0].quoteId);
        console.log(calldata.calls[1].calldata);
        const call: Call = calldata.calls[1];
        const callData: string[] = call.calldata as string[];
        const routesLen: number = Number(callData[11]);
        console.log('routesLen', routesLen);
        assert(routesLen > 0, 'No routes found', 'NETWORK_ERROR');

        let startIndex = 12;
        for(let i=0; i<routesLen; ++i) {
            const swap_params_len = Number(callData[startIndex + 4]);
            const route: Route = {
                token_from: callData[startIndex],
                token_to: callData[startIndex + 1],
                exchange_address: callData[startIndex + 2],
                percent: Number(callData[startIndex + 3]),
                additional_swap_params: swap_params_len > 0 ? callData.slice(startIndex + 5, startIndex + 5 + swap_params_len): []
            }
            routes.push(route);
            startIndex += 5 + swap_params_len;
        }
    }
    console.log(routes);
    const swapInfo: SwapInfo = {
        token_from_address: fromToken, 
        token_from_amount: uint256.bnToUint256(amountWei),
        token_to_address: toToken,
        token_to_amount: uint256.bnToUint256("0"), 
        token_to_min_amount: uint256.bnToUint256(minAmount),
        beneficiary: taker,
        integrator_fee_amount_bps: 0,
        integrator_fee_recipient: taker,
        routes
    };

    return swapInfo;
}

function getNumProof() {
    const x = [
        "0x6932e4c13f81f0d8e83f38dad15012ba93b984cecae26c36edbdc06f4bff84d",
        "0x1c9e1f920fedcf201759b7aee1d176857dad1fe6e9663676469ddda7bd7123",
        "0x56a0e58285ee06d2e6cdd27ba906a66788a03e5b664f604a6befc2f1f051d44",
        "0xb22c44b097113550f8a340254af971d666a1d0f87fa3cb61dc505215f60153",
        "0x2821b32cb8b9bddf69694d71d44b071368dfbb6ff9a5c6f9692ac450df92d40",
        "0x67752ec43658877f4ee13bdfa3c957e3d689a780346ca492a5fac9a9e50259",
        "0x1dd7fbdfbab95be03b65396638e2b9d7175f6001c3a760478a994674b5a774f",
        "0x2587777dbcd35a3d33048cc60fcec1577c9e26b0581273a906e68141b820fc2",
        "0x1742da3581023d6547c37e741c01d408998295c5aaa5f1e793727a9ffc2d8a8",
        "0x2d48e1d6bbcf879ff436abb60881aa7640454894809284ef23d86a464d47656",
        "0xffb40fb5de5c6da3baee7b0084c7b36f6ec2ee7c74035887b23cea6f755282",
        "0x5b38b4e4355ed64346c10e45d9c652dae3a3e17010fb74dc2d19d5d2fb60f8d",
        "0x596636ef6e06f12870cb5c7a7410384d894fdf2efadfbf9878bd84f47fed49c"
    ]
    const res = x.map(num.getDecimalString)
    console.log(res.join(','))
    return res;
}

async function bulkHarvest() {
    const notif = new TelegramNotif(process.env.TELEGRAM_TOKEN || '', false);
    try {
        notif.sendMessage('Starting bulk harvest');
        // await harvestAutoStrk();
        // notif.sendMessage('Auto harvest STRK done');
        // await harvestAutoUSDC();
        // notif.sendMessage('Auto harvest USDC done');
        // await harvestDNMM('0x04937b58e05a3a2477402d1f74e66686f58a61a5070fcc6f694fb9a0b3bae422', 6, USDC, "USDC");
        // notif.sendMessage('DNMM USDC done');
        // await harvestDNMM('0x020d5fc4c9df4f943ebb36078e703369c04176ed00accf290e8295b659d2cea6', 18, STRK, "STRK");
        // notif.sendMessage('DNMM STRK done');
        // await harvestDNMM('0x009d23d9b1fa0db8c9d75a1df924c3820e594fc4ab1475695889286f3f6df250', 18, ETH, "ETH");
        // notif.sendMessage('DNMM ETH done');
        // await harvestDNMM('0x009140757f8fb5748379be582be39d6daf704cc3a0408882c0d57981a885eed9', 18, ETH, "ETH");
        // notif.sendMessage('DNMM ETH (XL) done');
        // await harvestDNMM('0x7b07bf17944cbc5f8d8a3f8c75c3ddd3f3634b45d1290b88fc3b82760dd6b06', 18, xSTRK,
        //     getVesuProofs, getDummyProofs
        // ); // xSTRK - STRK

        await harvestDNMM('0x7023a5cadc8a5db80e4f0fde6b330cbd3c17bbbf9cb145cbabd7bd5e6fb7b0b', 18, STRK, "STRK",
            getVesuProofs, getDummyProofs
        ); // STRK - xSTRK
        notif.sendMessage('DNMM xSTRK done');
        notif.sendMessage('Bulk harvest done');
    } catch (e: any) {
        console.log(e);
        notif.sendMessage(`Bulk harvest failed: ${e.message}`);
    }
    

    // 0x7b07bf17944cbc5f8d8a3f8c75c3ddd3f3634b45d1290b88fc3b82760dd6b06 // xSTRK-STRK vesu
}

if (require.main === module) {
    // getNumProof();
    // harvestAutoStrk();
    // harvestAutoUSDC()
    // harvestDNMM('0x04937b58e05a3a2477402d1f74e66686f58a61a5070fcc6f694fb9a0b3bae422', 6);
    // harvestDNMM('0x020d5fc4c9df4f943ebb36078e703369c04176ed00accf290e8295b659d2cea6', 18);
    // update_settings();
    bulkHarvest();
}