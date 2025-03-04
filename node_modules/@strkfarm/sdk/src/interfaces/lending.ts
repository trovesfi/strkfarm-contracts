import { IConfig } from "@/interfaces/common";
import { TokenInfo } from "./common";
import { ContractAddr } from "@/dataTypes/address";
import { loggers } from "winston";
import { logger } from "@/global";
import { log } from "console";
import { Web3Number } from "@/dataTypes/bignumber";

export interface ILendingMetadata {
    name: string;
    logo: string;
}

export enum MarginType {
    SHARED = "shared",
    NONE = "none",
}

export interface ILendingPosition {
    tokenName: string;
    tokenSymbol: string;
    marginType: MarginType,
    debtAmount: Web3Number;
    debtUSD: Web3Number;
    supplyAmount: Web3Number;
    supplyUSD: Web3Number;
}

export interface LendingToken extends TokenInfo {
    borrowFactor: Web3Number;
    collareralFactor: Web3Number;
}

export abstract class ILending {
    readonly config: IConfig;
    readonly metadata: ILendingMetadata;
    readonly tokens: LendingToken[] = [];

    protected initialised: boolean = false;
    constructor(config:IConfig, metadata: ILendingMetadata) {
        this.metadata = metadata;
        this.config = config;
        this.init();
    }

    /** Async function to init the class */
    abstract init(): Promise<void>;

    /** Wait for initialisation */
    waitForInitilisation() {
        return new Promise<void>((resolve, reject) => {
            const interval = setInterval(() => {
                logger.verbose(`Waiting for ${this.metadata.name} to initialise`);
                if (this.initialised) {
                    logger.verbose(`${this.metadata.name} initialised`);
                    clearInterval(interval);
                    resolve();
                }
            }, 1000);
        });
    }

    /**
     * 
     * @param lending_tokens Array of tokens to consider for compute collateral value
     * @param debt_tokens Array of tokens to consider to compute debt values
     * @param user 
     */
    abstract get_health_factor_tokenwise(lending_tokens: TokenInfo[], debt_tokens: TokenInfo[], user: ContractAddr): Promise<number>;
    abstract get_health_factor(user: ContractAddr): Promise<number>;
    abstract getPositionsSummary(user: ContractAddr): Promise<{
        collateralUSD: number,
        debtUSD: number,
    }>
}