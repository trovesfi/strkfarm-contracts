import * as dotenv from 'dotenv';
dotenv.config();
import {Account, Call, RawArgs, RpcProvider, TransactionExecutionStatus, Uint256, extractContractHashes, hash, json, provider, uint256} from 'starknet'
import { readFileSync, existsSync, writeFileSync } from 'fs'
import { IConfig, Network, Store, getDefaultStoreConfig } from '@strkfarm/sdk';
import assert from 'assert';
import { fetchBuildExecuteTransaction, fetchQuotes } from "@avnu/avnu-sdk";

export const ACCOUNT_NAME = "strkfarmadmin";

export function getRpcProvider(rpcUrl: string | undefined = process.env.RPC_URL) {
    assert(rpcUrl, 'invalid RPC_URL');
    console.log(`RPC: ${rpcUrl}`);
    return new RpcProvider({nodeUrl: rpcUrl})
}

function getContracts() {
    const PATH = './contracts.json'
    if (existsSync(PATH)) {
        return JSON.parse(readFileSync(PATH, {encoding: 'utf-8'}))
    }
    return {}
}

function saveContracts(contracts: any) {
    const PATH = './contracts.json'
    writeFileSync(PATH, JSON.stringify(contracts));
}

export function getAccount(accountKey: string, fileName = 'accounts-orig.json', password = process.env.ACCOUNT_SECURE_PASSWORD) {
    const config: IConfig = {
        provider: <any>new RpcProvider({nodeUrl: process.env.RPC_URL}),
        network: Network.mainnet,
        stage: 'production'
    }
    const storeConfig = getDefaultStoreConfig(Network.mainnet);
    storeConfig.ACCOUNTS_FILE_NAME = fileName;
    const store = new Store(config, {
        ...storeConfig,
        PASSWORD: password || '',
    });
    
    return store.getAccount(accountKey, '0x3');
}

// export function getAccount(accountKey: string) {
//     const rpc = getRpcProvider(process.env.RPC_URL)
//     return new Account(rpc, process.env.ACCOUNT_ADDRESS!, process.env.ACCOUNT_SECURE_PASSWORD!)
//     //  process.env.ACCOUNT_ADDRESS
// }

export async function myDeclare(contract_name: string, package_name: string = 'strkfarm_contracts') {
    const provider = getRpcProvider();
    const acc = getAccount(ACCOUNT_NAME);
    const compiledSierra = json.parse(
        readFileSync(`./target/release/${package_name}_${contract_name}.contract_class.json`).toString("ascii")
    )
    const compiledCasm = json.parse(
    readFileSync(`./target/release/${package_name}_${contract_name}.compiled_contract_class.json`).toString("ascii")
    )
    
    const contracts = getContracts();
    const payload = {
        contract: compiledSierra,
        casm: compiledCasm
    };
    
    const result = extractContractHashes(payload);
    console.log("classhash:", result.classHash);

    try {
        const cls = await provider.getClass(result.classHash);
        return {
            class_hash: result.classHash,
            transaction_hash: null
        }
    } catch {
        console.log('Class not declared, continue');
    }
    
    const fee = await acc.estimateDeclareFee({
        contract: compiledSierra,
        casm: compiledCasm, 
    })
    console.log('declare fee', Number(fee.suggestedMaxFee) / 10 ** 18, 'ETH')
    
    
    const tx = await acc.declareIfNot(payload)
    console.log(`Declaring: ${contract_name}, tx:`, tx.transaction_hash);
    await provider.waitForTransaction(tx.transaction_hash, {
        successStates: [TransactionExecutionStatus.SUCCEEDED]
    })
    
    if (!contracts.class_hashes) {
        contracts['class_hashes'] = {};
    }

    // Todo attach cairo and scarb version. and commit ID
    contracts.class_hashes[contract_name] = tx.class_hash;
    saveContracts(contracts);
    console.log(`Contract declared: ${contract_name}`)
    console.log(`Class hash: ${tx.class_hash}`)
    return tx;
}

export async function deployContract(contract_name: string, classHash: string, constructorData: RawArgs, sub_contract_name: string = '') {
    const provider = getRpcProvider();
    const acc = getAccount(ACCOUNT_NAME);

    const fee = await acc.estimateDeployFee({
        classHash,
        constructorCalldata: constructorData,
    })
    console.log("Deploy fee", contract_name, Number(fee.suggestedMaxFee) / 10 ** 18, 'ETH')

    return deploy(classHash, constructorData, contract_name, sub_contract_name);
}

export async function deploy(
    classHash: string,
    constructorData: RawArgs,
    contract_name: string,
    sub_contract_name: string = ''
) {
    const provider = getRpcProvider();
    const acc = getAccount(ACCOUNT_NAME);
    const tx = await acc.deployContract({
        classHash,
        constructorCalldata: constructorData,
    })
    console.log('Deploy tx: ', tx.transaction_hash);
    await provider.waitForTransaction(tx.transaction_hash, {
        successStates: [TransactionExecutionStatus.SUCCEEDED]
    })
    const contracts = getContracts();
    if (!contracts.contracts) {
        contracts['contracts'] = {};
    }
    if (sub_contract_name) {
        if (!contracts.contracts[contract_name]) {
            contracts.contracts[contract_name] = {};
        }
        contracts.contracts[contract_name][sub_contract_name] = tx.contract_address;
    } else {
        contracts.contracts[contract_name] = tx.contract_address;
    }
    saveContracts(contracts);
    console.log(`Contract deployed: ${contract_name}`)
    console.log(`Address: ${tx.contract_address}`)
    return tx;
}

export interface Route {
    token_from: string,
    token_to: string,
    exchange_address: string,
    percent: number,
    additional_swap_params: string[]
}

export interface SwapInfo {
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

export async function getSwapInfo(
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
    // console.log(params);
    const routes: Route[] = [];
    if (fromToken != toToken) {
        const quotes = await fetchQuotes(params);
        assert(quotes.length > 0, 'No quotes found');
        // console.log(quotes);
        const calldata = await  fetchBuildExecuteTransaction(quotes[0].quoteId);
        // console.log(calldata.calls[1].calldata);
        const call: Call = calldata.calls[1];
        const callData: string[] = call.calldata as string[];
        const routesLen: number = Number(callData[11]);
        assert(routesLen > 0, 'No routes found');

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
    // console.log(routes);
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