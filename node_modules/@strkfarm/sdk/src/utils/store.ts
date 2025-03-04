import { IConfig, Network } from '@/interfaces/common';
import fs, { readFileSync, writeFileSync } from 'fs';
import { Account } from 'starknet';
import * as crypto from 'crypto';
import { PasswordJsonCryptoUtil } from './encrypt';
import { logger } from '..';
import { log } from 'winston';

/**
 * @description Config to manage storage of files on disk
 * @param SECRET_FILE_FOLDER - Folder to store secret files (default: ~/.starknet-store)
 * @param NETWORK - Network to use
 */
export interface StoreConfig {
    SECRET_FILE_FOLDER?: string,
    NETWORK: Network,
    ACCOUNTS_FILE_NAME?: string,
    PASSWORD: string
}

/**
 * @description Info of a particular account
 */
export interface AccountInfo {
    address: string,
    pk: string
}

/**
 * @description map of accounts of a network
 */
interface NetworkAccounts {
    [accountKey: string]: AccountInfo
}

/**
 * @description map of all accounts of all networks
 */
export interface AllAccountsStore {
    [networkKey: string]: NetworkAccounts
}

/** 
 * @description StoreConfig with optional fields marked required
 */
export type RequiredStoreConfig = Required<StoreConfig>;

/**
 * @description Get the default store config
 * @param network 
 * @returns StoreConfig
 */
export function getDefaultStoreConfig(network: Network): RequiredStoreConfig {
    if (!process.env.HOME) {
        throw new Error('StoreConfig: HOME environment variable not found');
    }
    return {
        SECRET_FILE_FOLDER: `${process.env.HOME}/.starknet-store`,
        NETWORK: network,
        ACCOUNTS_FILE_NAME: 'accounts.json',
        PASSWORD: crypto.randomBytes(16).toString('hex')
    }
}

/**
 * @description Store class to manage accounts
 */
export class Store {
    readonly config: IConfig;
    readonly storeConfig: RequiredStoreConfig;

    private encryptor = new PasswordJsonCryptoUtil();
    constructor(config: IConfig, storeConfig: StoreConfig) {
        this.config = config;

        const defaultStoreConfig = getDefaultStoreConfig(config.network);

        if (!storeConfig.PASSWORD) {
            Store.logPassword(defaultStoreConfig.PASSWORD);
        }

        this.storeConfig = {
            ...defaultStoreConfig,
            ...storeConfig
        };

        // Ensure the store secret folder exists
        Store.ensureFolder(this.storeConfig.SECRET_FILE_FOLDER);
    }

    static logPassword(password: string) {
        logger.warn(`⚠️=========================================⚠️`);
        logger.warn(`Generated a random password for store`);
        logger.warn(`⚠️ Password: ${password}`);
        logger.warn(`This not stored anywhere, please you backup this password for future use`);
        logger.warn(`⚠️=========================================⚠️`);
    }

    getAccount(accountKey: string) {
        const accounts = this.loadAccounts();
        logger.verbose(`nAccounts loaded for network: ${Object.keys(accounts).length}`);
        const data = accounts[accountKey];
        if (!data) {
            throw new Error(`Account not found: ${accountKey}`);
        }
        logger.verbose(`Account loaded: ${accountKey} from network: ${this.config.network}`);
        logger.verbose(`Address: ${data.address}`);
        return new Account(<any>this.config.provider, data.address, data.pk);
    }

    addAccount(accountKey: string, address: string, pk: string) {
        const allAccounts = this.getAllAccounts();
        if (!allAccounts[this.config.network]) {
            allAccounts[this.config.network] = {};
        }
        allAccounts[this.config.network][accountKey] = {
            address,
            pk
        };
        const encryptedData = this.encryptor.encrypt(allAccounts, this.storeConfig.PASSWORD);
        writeFileSync(this.getAccountFilePath(), encryptedData);
        logger.verbose(`Account added: ${accountKey} to network: ${this.config.network}`);
    }

    private getAccountFilePath() {
        const path = `${this.storeConfig.SECRET_FILE_FOLDER}/${this.storeConfig.ACCOUNTS_FILE_NAME}`;
        logger.verbose(`Path: ${path}`);
        return path
    }

    private getAllAccounts(): AllAccountsStore {
        const PATH = this.getAccountFilePath();
        if (!fs.existsSync(PATH)) {
            logger.verbose(`Accounts: files doesnt exist`)
            return {};
        }
        let encryptedData = readFileSync(PATH, {
            encoding: 'utf-8'
        });
        let data = this.encryptor.decrypt(encryptedData, this.storeConfig.PASSWORD);
        return data;
    }

    /**
     * @description Load all accounts of the network
     * @returns NetworkAccounts
     */
    loadAccounts(): NetworkAccounts {
        const allData: AllAccountsStore = this.getAllAccounts();
        logger.verbose(`Accounts loaded for network: ${this.config.network}`);
        if (!allData[this.config.network]) {
            allData[this.config.network] = {};
        }
        return allData[this.config.network];
    }

    /**
     * @description List all accountKeys of the network
     * @returns string[]
     */
    listAccounts(): string[] {
        return Object.keys(this.loadAccounts());
    }

    static ensureFolder(folder: string) {
        if (!fs.existsSync(folder)) {
            fs.mkdirSync(folder, { recursive: true });
        }
        if (!fs.existsSync(`${folder}`)) {
            throw new Error(`Store folder not found: ${folder}`);
        }
    }
}