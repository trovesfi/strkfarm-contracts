import { BlockIdentifier, RpcProvider } from "starknet"

export interface TokenInfo {
    name: string,
    symbol: string,
    address: string,
    decimals: number,
    coingeckId?: string,
}

export enum Network {
    mainnet = "mainnet",
    sepolia = "sepolia",
    devnet = "devnet"
}

export interface IConfig {
    provider: RpcProvider,
    network: Network,
    stage: 'production' | 'staging',
    heartbeatUrl?: string
}

export function getMainnetConfig(rpcUrl = "https://starknet-mainnet.public.blastapi.io", blockIdentifier: BlockIdentifier = 'pending'): IConfig {
    return {
        provider: new RpcProvider({
            nodeUrl: rpcUrl,
            blockIdentifier: blockIdentifier
        }),
        stage: "production",
        network: Network.mainnet
    }
}