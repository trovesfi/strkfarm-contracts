import { RpcProvider, BlockIdentifier, Contract, Account } from 'starknet';
import BigNumber from 'bignumber.js';
import * as util from 'util';
import TelegramBot from 'node-telegram-bot-api';

interface TokenInfo {
    name: string;
    symbol: string;
    address: string;
    decimals: number;
    coingeckId?: string;
}
declare enum Network {
    mainnet = "mainnet",
    sepolia = "sepolia",
    devnet = "devnet"
}
interface IConfig {
    provider: RpcProvider;
    network: Network;
    stage: 'production' | 'staging';
    heartbeatUrl?: string;
}
declare function getMainnetConfig(rpcUrl?: string, blockIdentifier?: BlockIdentifier): IConfig;

declare class Web3Number extends BigNumber {
    decimals: number;
    constructor(value: string | number, decimals: number);
    static fromWei(weiNumber: string | number, decimals: number): Web3Number;
    toWei(): string;
    multipliedBy(value: string | number): Web3Number;
    dividedBy(value: string | number): Web3Number;
    plus(value: string | number): Web3Number;
    minus(n: number | string, base?: number): Web3Number;
    toString(base?: number | undefined): string;
}

/**
 * A simple wrapper around a contract address that is universally comparable
 * - Helps avoid padding issues
 */
declare class ContractAddr {
    readonly address: string;
    constructor(address: string);
    static from(address: string): ContractAddr;
    eq(other: ContractAddr): boolean;
    eqString(other: string): boolean;
    static standardise(address: string | bigint): string;
    static eqString(a: string, b: string): boolean;
}

interface PriceInfo {
    price: number;
    timestamp: Date;
}
declare class Pricer {
    readonly config: IConfig;
    readonly tokens: TokenInfo[];
    protected prices: {
        [key: string]: PriceInfo;
    };
    private methodToUse;
    /**
     * TOKENA and TOKENB are the two token names to get price of TokenA in terms of TokenB
     */
    protected PRICE_API: string;
    protected EKUBO_API: string;
    protected client: any;
    constructor(config: IConfig, tokens: TokenInfo[]);
    isReady(): boolean;
    waitTillReady(): Promise<void>;
    start(): void;
    isStale(timestamp: Date, tokenName: string): boolean;
    assertNotStale(timestamp: Date, tokenName: string): void;
    getPrice(tokenName: string): Promise<PriceInfo>;
    protected _loadPrices(onUpdate?: (tokenSymbol: string) => void): void;
    _getPrice(token: TokenInfo, defaultMethod?: string): Promise<number>;
    _getPriceCoinbase(token: TokenInfo): Promise<number>;
    _getPriceCoinMarketCap(token: TokenInfo): Promise<number>;
    _getPriceEkubo(token: TokenInfo, amountIn?: Web3Number, retry?: number): Promise<number>;
}

declare class Pragma {
    contractAddr: string;
    readonly contract: Contract;
    constructor(provider: RpcProvider);
    getPrice(tokenAddr: string): Promise<number>;
}

interface ILendingMetadata {
    name: string;
    logo: string;
}
declare enum MarginType {
    SHARED = "shared",
    NONE = "none"
}
interface ILendingPosition {
    tokenName: string;
    tokenSymbol: string;
    marginType: MarginType;
    debtAmount: Web3Number;
    debtUSD: Web3Number;
    supplyAmount: Web3Number;
    supplyUSD: Web3Number;
}
interface LendingToken extends TokenInfo {
    borrowFactor: Web3Number;
    collareralFactor: Web3Number;
}
declare abstract class ILending {
    readonly config: IConfig;
    readonly metadata: ILendingMetadata;
    readonly tokens: LendingToken[];
    protected initialised: boolean;
    constructor(config: IConfig, metadata: ILendingMetadata);
    /** Async function to init the class */
    abstract init(): Promise<void>;
    /** Wait for initialisation */
    waitForInitilisation(): Promise<void>;
    /**
     *
     * @param lending_tokens Array of tokens to consider for compute collateral value
     * @param debt_tokens Array of tokens to consider to compute debt values
     * @param user
     */
    abstract get_health_factor_tokenwise(lending_tokens: TokenInfo[], debt_tokens: TokenInfo[], user: ContractAddr): Promise<number>;
    abstract get_health_factor(user: ContractAddr): Promise<number>;
    abstract getPositionsSummary(user: ContractAddr): Promise<{
        collateralUSD: number;
        debtUSD: number;
    }>;
}

declare abstract class Initializable {
    protected initialized: boolean;
    constructor();
    abstract init(): Promise<void>;
    waitForInitilisation(): Promise<void>;
}

declare class ZkLend extends ILending implements ILending {
    readonly pricer: Pricer;
    static readonly POOLS_URL = "https://app.zklend.com/api/pools";
    private POSITION_URL;
    constructor(config: IConfig, pricer: Pricer);
    init(): Promise<void>;
    /**
     * @description Get the health factor of the user for given lending and debt tokens
     * @param lending_tokens
     * @param debt_tokens
     * @param user
     * @returns hf (e.g. returns 1.5 for 150% health factor)
     */
    get_health_factor_tokenwise(lending_tokens: TokenInfo[], debt_tokens: TokenInfo[], user: ContractAddr): Promise<number>;
    /**
     * @description Get the health factor of the user
     * - Considers all tokens for collateral and debt
     */
    get_health_factor(user: ContractAddr): Promise<number>;
    getPositionsSummary(user: ContractAddr): Promise<{
        collateralUSD: number;
        debtUSD: number;
    }>;
    /**
     * @description Get the token-wise collateral and debt positions of the user
     * @param user Contract address of the user
     * @returns Promise<ILendingPosition[]>
     */
    getPositions(user: ContractAddr): Promise<ILendingPosition[]>;
}

declare const logger: {
    verbose(message: string): void;
    assert(condition?: boolean, ...data: any[]): void;
    assert(value: any, message?: string, ...optionalParams: any[]): void;
    clear(): void;
    clear(): void;
    count(label?: string): void;
    count(label?: string): void;
    countReset(label?: string): void;
    countReset(label?: string): void;
    debug(...data: any[]): void;
    debug(message?: any, ...optionalParams: any[]): void;
    dir(item?: any, options?: any): void;
    dir(obj: any, options?: util.InspectOptions): void;
    dirxml(...data: any[]): void;
    dirxml(...data: any[]): void;
    error(...data: any[]): void;
    error(message?: any, ...optionalParams: any[]): void;
    group(...data: any[]): void;
    group(...label: any[]): void;
    groupCollapsed(...data: any[]): void;
    groupCollapsed(...label: any[]): void;
    groupEnd(): void;
    groupEnd(): void;
    info(...data: any[]): void;
    info(message?: any, ...optionalParams: any[]): void;
    log(...data: any[]): void;
    log(message?: any, ...optionalParams: any[]): void;
    table(tabularData?: any, properties?: string[]): void;
    table(tabularData: any, properties?: readonly string[]): void;
    time(label?: string): void;
    time(label?: string): void;
    timeEnd(label?: string): void;
    timeEnd(label?: string): void;
    timeLog(label?: string, ...data: any[]): void;
    timeLog(label?: string, ...data: any[]): void;
    timeStamp(label?: string): void;
    timeStamp(label?: string): void;
    trace(...data: any[]): void;
    trace(message?: any, ...optionalParams: any[]): void;
    warn(...data: any[]): void;
    warn(message?: any, ...optionalParams: any[]): void;
    Console: console.ConsoleConstructor;
    profile(label?: string): void;
    profileEnd(label?: string): void;
};
declare class FatalError extends Error {
    constructor(message: string, err?: Error);
}
/** Contains globally useful functions.
 * - fatalError: Things to do when a fatal error occurs
 */
declare class Global {
    static fatalError(message: string, err?: Error): void;
    static httpError(url: string, err: Error, message?: string): void;
    static getTokens(): Promise<TokenInfo[]>;
    static assert(condition: any, message: string): void;
}

declare class AutoCompounderSTRK {
    readonly config: IConfig;
    readonly addr: ContractAddr;
    readonly pricer: Pricer;
    private initialized;
    contract: Contract | null;
    readonly metadata: {
        decimals: number;
        underlying: {
            address: ContractAddr;
            name: string;
            symbol: string;
        };
        name: string;
    };
    constructor(config: IConfig, pricer: Pricer);
    init(): Promise<void>;
    waitForInitilisation(): Promise<void>;
    /** Returns shares of user */
    balanceOf(user: ContractAddr): Promise<Web3Number>;
    /** Returns underlying assets of user */
    balanceOfUnderlying(user: ContractAddr): Promise<Web3Number>;
    /** Returns usd value of assets */
    usdBalanceOfUnderlying(user: ContractAddr): Promise<{
        usd: Web3Number;
        assets: Web3Number;
    }>;
}

declare class TelegramNotif {
    private subscribers;
    readonly bot: TelegramBot;
    constructor(token: string, shouldPoll: boolean);
    activateChatBot(): void;
    sendMessage(msg: string): void;
}

/**
 * @description Config to manage storage of files on disk
 * @param SECRET_FILE_FOLDER - Folder to store secret files (default: ~/.starknet-store)
 * @param NETWORK - Network to use
 */
interface StoreConfig {
    SECRET_FILE_FOLDER?: string;
    NETWORK: Network;
    ACCOUNTS_FILE_NAME?: string;
    PASSWORD: string;
}
/**
 * @description Info of a particular account
 */
interface AccountInfo {
    address: string;
    pk: string;
}
/**
 * @description map of accounts of a network
 */
interface NetworkAccounts {
    [accountKey: string]: AccountInfo;
}
/**
 * @description map of all accounts of all networks
 */
interface AllAccountsStore {
    [networkKey: string]: NetworkAccounts;
}
/**
 * @description StoreConfig with optional fields marked required
 */
type RequiredStoreConfig = Required<StoreConfig>;
/**
 * @description Get the default store config
 * @param network
 * @returns StoreConfig
 */
declare function getDefaultStoreConfig(network: Network): RequiredStoreConfig;
/**
 * @description Store class to manage accounts
 */
declare class Store {
    readonly config: IConfig;
    readonly storeConfig: RequiredStoreConfig;
    private encryptor;
    constructor(config: IConfig, storeConfig: StoreConfig);
    static logPassword(password: string): void;
    getAccount(accountKey: string): Account;
    addAccount(accountKey: string, address: string, pk: string): void;
    private getAccountFilePath;
    private getAllAccounts;
    /**
     * @description Load all accounts of the network
     * @returns NetworkAccounts
     */
    loadAccounts(): NetworkAccounts;
    /**
     * @description List all accountKeys of the network
     * @returns string[]
     */
    listAccounts(): string[];
    static ensureFolder(folder: string): void;
}

declare class PasswordJsonCryptoUtil {
    private readonly algorithm;
    private readonly keyLength;
    private readonly saltLength;
    private readonly ivLength;
    private readonly tagLength;
    private readonly pbkdf2Iterations;
    private deriveKey;
    encrypt(data: any, password: string): string;
    decrypt(encryptedData: string, password: string): any;
}

type RequiredFields<T> = {
    [K in keyof T]-?: T[K];
};
type RequiredKeys<T> = {
    [K in keyof T]-?: {} extends Pick<T, K> ? never : K;
}[keyof T];

declare class PricerRedis extends Pricer {
    private redisClient;
    constructor(config: IConfig, tokens: TokenInfo[]);
    /** Reads prices from Pricer._loadPrices and uses a callback to set prices in redis */
    startWithRedis(redisUrl: string): Promise<void>;
    close(): Promise<void>;
    initRedis(redisUrl: string): Promise<void>;
    /** sets current local price in redis */
    private _setRedisPrices;
    /** Returns price from redis */
    getPrice(tokenSymbol: string): Promise<PriceInfo>;
}

export { type AccountInfo, type AllAccountsStore, AutoCompounderSTRK, ContractAddr, FatalError, Global, type IConfig, ILending, type ILendingMetadata, type ILendingPosition, Initializable, type LendingToken, MarginType, Network, PasswordJsonCryptoUtil, Pragma, type PriceInfo, Pricer, PricerRedis, type RequiredFields, type RequiredKeys, type RequiredStoreConfig, Store, type StoreConfig, TelegramNotif, type TokenInfo, Web3Number, ZkLend, getDefaultStoreConfig, getMainnetConfig, logger };
