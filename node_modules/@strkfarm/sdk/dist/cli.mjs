#!/usr/bin/env node
var __require = /* @__PURE__ */ ((x) => typeof require !== "undefined" ? require : typeof Proxy !== "undefined" ? new Proxy(x, {
  get: (a, b) => (typeof require !== "undefined" ? require : a)[b]
}) : x)(function(x) {
  if (typeof require !== "undefined") return require.apply(this, arguments);
  throw Error('Dynamic require of "' + x + '" is not supported');
});

// src/cli.ts
import { Command } from "commander";
import inquirer from "inquirer";

// src/utils/store.ts
import fs, { readFileSync, writeFileSync } from "fs";
import { Account } from "starknet";
import * as crypto2 from "crypto";

// src/utils/encrypt.ts
import * as crypto from "crypto";
var PasswordJsonCryptoUtil = class {
  constructor() {
    this.algorithm = "aes-256-gcm";
    this.keyLength = 32;
    // 256 bits
    this.saltLength = 16;
    // 128 bits
    this.ivLength = 12;
    // 96 bits for GCM
    this.tagLength = 16;
    // 128 bits
    this.pbkdf2Iterations = 1e5;
  }
  // Number of iterations for PBKDF2
  deriveKey(password, salt) {
    return crypto.pbkdf2Sync(password, salt, this.pbkdf2Iterations, this.keyLength, "sha256");
  }
  encrypt(data, password) {
    const jsonString = JSON.stringify(data);
    const salt = crypto.randomBytes(this.saltLength);
    const iv = crypto.randomBytes(this.ivLength);
    const key = this.deriveKey(password, salt);
    const cipher = crypto.createCipheriv(this.algorithm, key, iv, { authTagLength: this.tagLength });
    let encrypted = cipher.update(jsonString, "utf8", "hex");
    encrypted += cipher.final("hex");
    const tag = cipher.getAuthTag();
    return Buffer.concat([salt, iv, tag, Buffer.from(encrypted, "hex")]).toString("base64");
  }
  decrypt(encryptedData, password) {
    const data = Buffer.from(encryptedData, "base64");
    const salt = data.subarray(0, this.saltLength);
    const iv = data.subarray(this.saltLength, this.saltLength + this.ivLength);
    const tag = data.subarray(this.saltLength + this.ivLength, this.saltLength + this.ivLength + this.tagLength);
    const encrypted = data.subarray(this.saltLength + this.ivLength + this.tagLength);
    const key = this.deriveKey(password, salt);
    const decipher = crypto.createDecipheriv(this.algorithm, key, iv, { authTagLength: this.tagLength });
    decipher.setAuthTag(tag);
    try {
      let decrypted = decipher.update(encrypted.toString("hex"), "hex", "utf8");
      decrypted += decipher.final("utf8");
      return JSON.parse(decrypted);
    } catch (error) {
      throw new Error("Decryption failed. This could be due to an incorrect password or corrupted data.");
    }
  }
};

// src/modules/pricer.ts
import axios2 from "axios";

// src/global.ts
import axios from "axios";
var logger = {
  ...console,
  verbose(message) {
    console.log(`[VERBOSE] ${message}`);
  }
};
var FatalError = class extends Error {
  constructor(message, err) {
    super(message);
    logger.error(message);
    if (err)
      logger.error(err.message);
    this.name = "FatalError";
  }
};
var tokens = [];
var Global = class {
  static fatalError(message, err) {
    logger.error(message);
    console.error(message, err);
    if (err)
      console.error(err);
    process.exit(1);
  }
  static httpError(url, err, message) {
    logger.error(`${url}: ${message}`);
    console.error(err);
  }
  static async getTokens() {
    if (tokens.length) return tokens;
    const data = await axios.get("https://starknet.api.avnu.fi/v1/starknet/tokens");
    const tokensData = data.data.content;
    tokensData.forEach((token) => {
      if (!token.tags.includes("AVNU") || !token.tags.includes("Verified")) {
        return;
      }
      tokens.push({
        name: token.name,
        symbol: token.symbol,
        address: token.address,
        decimals: token.decimals,
        coingeckId: token.extensions.coingeckoId
      });
    });
    console.log(tokens);
    return tokens;
  }
  static assert(condition, message) {
    if (!condition) {
      throw new FatalError(message);
    }
  }
};

// src/dataTypes/bignumber.ts
import BigNumber from "bignumber.js";
var Web3Number = class _Web3Number extends BigNumber {
  constructor(value, decimals) {
    super(value);
    this.decimals = decimals;
  }
  static fromWei(weiNumber, decimals) {
    const bn = new _Web3Number(weiNumber, decimals).dividedBy(10 ** decimals);
    return new _Web3Number(bn.toString(), decimals);
  }
  toWei() {
    return this.mul(10 ** this.decimals).toFixed(0);
  }
  multipliedBy(value) {
    return new _Web3Number(this.mul(value).toString(), this.decimals);
  }
  dividedBy(value) {
    return new _Web3Number(this.div(value).toString(), this.decimals);
  }
  plus(value) {
    return new _Web3Number(this.add(value).toString(), this.decimals);
  }
  minus(n, base) {
    return new _Web3Number(super.minus(n, base).toString(), this.decimals);
  }
  toString(base) {
    return super.toString(base);
  }
  // [customInspectSymbol](depth: any, inspectOptions: any, inspect: any) {
  // return this.toString();
  // }
};
BigNumber.config({ DECIMAL_PLACES: 18 });
Web3Number.config({ DECIMAL_PLACES: 18 });

// src/dataTypes/address.ts
import { num } from "starknet";

// src/modules/pricer.ts
var CoinMarketCap = __require("coinmarketcap-api");

// src/modules/pragma.ts
import { Contract } from "starknet";

// src/modules/zkLend.ts
import axios3 from "axios";

// src/interfaces/lending.ts
var ILending = class {
  constructor(config, metadata) {
    this.tokens = [];
    this.initialised = false;
    this.metadata = metadata;
    this.config = config;
    this.init();
  }
  /** Wait for initialisation */
  waitForInitilisation() {
    return new Promise((resolve, reject) => {
      const interval = setInterval(() => {
        logger.verbose(`Waiting for ${this.metadata.name} to initialise`);
        if (this.initialised) {
          logger.verbose(`${this.metadata.name} initialised`);
          clearInterval(interval);
          resolve();
        }
      }, 1e3);
    });
  }
};

// src/modules/zkLend.ts
var _ZkLend = class _ZkLend extends ILending {
  constructor(config, pricer) {
    super(config, {
      name: "zkLend",
      logo: "https://app.zklend.com/favicon.ico"
    });
    this.POSITION_URL = "https://app.zklend.com/api/users/{{USER_ADDR}}/all";
    this.pricer = pricer;
  }
  async init() {
    try {
      logger.verbose(`Initialising ${this.metadata.name}`);
      const result = await axios3.get(_ZkLend.POOLS_URL);
      const data = result.data;
      const savedTokens = await Global.getTokens();
      data.forEach((pool) => {
        let collareralFactor = new Web3Number(0, 0);
        if (pool.collateral_factor) {
          collareralFactor = Web3Number.fromWei(pool.collateral_factor.value, pool.collateral_factor.decimals);
        }
        const savedTokenInfo = savedTokens.find((t) => t.symbol == pool.token.symbol);
        const token = {
          name: pool.token.name,
          symbol: pool.token.symbol,
          address: savedTokenInfo?.address || "",
          decimals: pool.token.decimals,
          borrowFactor: Web3Number.fromWei(pool.borrow_factor.value, pool.borrow_factor.decimals),
          collareralFactor
        };
        this.tokens.push(token);
      });
      logger.info(`Initialised ${this.metadata.name} with ${this.tokens.length} tokens`);
      this.initialised = true;
    } catch (error) {
      return Global.httpError(_ZkLend.POOLS_URL, error);
    }
  }
  /**
   * @description Get the health factor of the user for given lending and debt tokens
   * @param lending_tokens 
   * @param debt_tokens 
   * @param user 
   * @returns hf (e.g. returns 1.5 for 150% health factor)
   */
  async get_health_factor_tokenwise(lending_tokens, debt_tokens, user) {
    const positions = await this.getPositions(user);
    logger.verbose(`${this.metadata.name}:: Positions: ${JSON.stringify(positions)}`);
    let effectiveDebt = new Web3Number(0, 6);
    positions.filter((pos) => {
      return debt_tokens.find((t) => t.symbol === pos.tokenSymbol);
    }).forEach((pos) => {
      const token = this.tokens.find((t) => t.symbol === pos.tokenSymbol);
      if (!token) {
        throw new FatalError(`Token ${pos.tokenName} not found in ${this.metadata.name}`);
      }
      effectiveDebt = effectiveDebt.plus(pos.debtUSD.dividedBy(token.borrowFactor.toFixed(6)).toString());
    });
    logger.verbose(`${this.metadata.name}:: Effective debt: ${effectiveDebt}`);
    if (effectiveDebt.isZero()) {
      return Infinity;
    }
    let effectiveCollateral = new Web3Number(0, 6);
    positions.filter((pos) => {
      const exp1 = lending_tokens.find((t) => t.symbol === pos.tokenSymbol);
      const exp2 = pos.marginType === "shared" /* SHARED */;
      return exp1 && exp2;
    }).forEach((pos) => {
      const token = this.tokens.find((t) => t.symbol === pos.tokenSymbol);
      if (!token) {
        throw new FatalError(`Token ${pos.tokenName} not found in ${this.metadata.name}`);
      }
      logger.verbose(`${this.metadata.name}:: Token: ${pos.tokenName}, Collateral factor: ${token.collareralFactor.toFixed(6)}`);
      effectiveCollateral = effectiveCollateral.plus(pos.supplyUSD.multipliedBy(token.collareralFactor.toFixed(6)).toString());
    });
    logger.verbose(`${this.metadata.name}:: Effective collateral: ${effectiveCollateral}`);
    const healthFactor = effectiveCollateral.dividedBy(effectiveDebt.toFixed(6)).toNumber();
    logger.verbose(`${this.metadata.name}:: Health factor: ${healthFactor}`);
    return healthFactor;
  }
  /**
   * @description Get the health factor of the user
   * - Considers all tokens for collateral and debt
   */
  async get_health_factor(user) {
    return this.get_health_factor_tokenwise(this.tokens, this.tokens, user);
  }
  async getPositionsSummary(user) {
    const pos = await this.getPositions(user);
    const collateralUSD = pos.reduce((acc, p) => acc + p.supplyUSD.toNumber(), 0);
    const debtUSD = pos.reduce((acc, p) => acc + p.debtUSD.toNumber(), 0);
    return {
      collateralUSD,
      debtUSD
    };
  }
  /**
   * @description Get the token-wise collateral and debt positions of the user 
   * @param user Contract address of the user
   * @returns Promise<ILendingPosition[]>
   */
  async getPositions(user) {
    const url = this.POSITION_URL.replace("{{USER_ADDR}}", user.address);
    const result = await axios3.get(url);
    const data = result.data;
    const lendingPosition = [];
    logger.verbose(`${this.metadata.name}:: Positions: ${JSON.stringify(data)}`);
    for (let i = 0; i < data.pools.length; i++) {
      const pool = data.pools[i];
      const token = this.tokens.find((t) => {
        return t.symbol === pool.token_symbol;
      });
      if (!token) {
        throw new FatalError(`Token ${pool.token_symbol} not found in ${this.metadata.name}`);
      }
      const debtAmount = Web3Number.fromWei(pool.data.debt_amount, token.decimals);
      const supplyAmount = Web3Number.fromWei(pool.data.supply_amount, token.decimals);
      const price = (await this.pricer.getPrice(token.symbol)).price;
      lendingPosition.push({
        tokenName: token.name,
        tokenSymbol: token.symbol,
        marginType: pool.data.is_collateral ? "shared" /* SHARED */ : "none" /* NONE */,
        debtAmount,
        debtUSD: debtAmount.multipliedBy(price.toFixed(6)),
        supplyAmount,
        supplyUSD: supplyAmount.multipliedBy(price.toFixed(6))
      });
    }
    ;
    return lendingPosition;
  }
};
_ZkLend.POOLS_URL = "https://app.zklend.com/api/pools";
var ZkLend = _ZkLend;

// src/interfaces/common.ts
import { RpcProvider as RpcProvider2 } from "starknet";

// src/strategies/autoCompounderStrk.ts
import { Contract as Contract2, uint256 } from "starknet";

// src/notifs/telegram.ts
import TelegramBot from "node-telegram-bot-api";

// src/node/pricer-redis.ts
import { createClient } from "redis";

// src/utils/store.ts
function getDefaultStoreConfig(network) {
  if (!process.env.HOME) {
    throw new Error("StoreConfig: HOME environment variable not found");
  }
  return {
    SECRET_FILE_FOLDER: `${process.env.HOME}/.starknet-store`,
    NETWORK: network,
    ACCOUNTS_FILE_NAME: "accounts.json",
    PASSWORD: crypto2.randomBytes(16).toString("hex")
  };
}
var Store = class _Store {
  constructor(config, storeConfig) {
    this.encryptor = new PasswordJsonCryptoUtil();
    this.config = config;
    const defaultStoreConfig = getDefaultStoreConfig(config.network);
    if (!storeConfig.PASSWORD) {
      _Store.logPassword(defaultStoreConfig.PASSWORD);
    }
    this.storeConfig = {
      ...defaultStoreConfig,
      ...storeConfig
    };
    _Store.ensureFolder(this.storeConfig.SECRET_FILE_FOLDER);
  }
  static logPassword(password) {
    logger.warn(`\u26A0\uFE0F=========================================\u26A0\uFE0F`);
    logger.warn(`Generated a random password for store`);
    logger.warn(`\u26A0\uFE0F Password: ${password}`);
    logger.warn(`This not stored anywhere, please you backup this password for future use`);
    logger.warn(`\u26A0\uFE0F=========================================\u26A0\uFE0F`);
  }
  getAccount(accountKey) {
    const accounts = this.loadAccounts();
    logger.verbose(`nAccounts loaded for network: ${Object.keys(accounts).length}`);
    const data = accounts[accountKey];
    if (!data) {
      throw new Error(`Account not found: ${accountKey}`);
    }
    logger.verbose(`Account loaded: ${accountKey} from network: ${this.config.network}`);
    logger.verbose(`Address: ${data.address}`);
    return new Account(this.config.provider, data.address, data.pk);
  }
  addAccount(accountKey, address, pk) {
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
  getAccountFilePath() {
    const path = `${this.storeConfig.SECRET_FILE_FOLDER}/${this.storeConfig.ACCOUNTS_FILE_NAME}`;
    logger.verbose(`Path: ${path}`);
    return path;
  }
  getAllAccounts() {
    const PATH = this.getAccountFilePath();
    if (!fs.existsSync(PATH)) {
      logger.verbose(`Accounts: files doesnt exist`);
      return {};
    }
    let encryptedData = readFileSync(PATH, {
      encoding: "utf-8"
    });
    let data = this.encryptor.decrypt(encryptedData, this.storeConfig.PASSWORD);
    return data;
  }
  /**
   * @description Load all accounts of the network
   * @returns NetworkAccounts
   */
  loadAccounts() {
    const allData = this.getAllAccounts();
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
  listAccounts() {
    return Object.keys(this.loadAccounts());
  }
  static ensureFolder(folder) {
    if (!fs.existsSync(folder)) {
      fs.mkdirSync(folder, { recursive: true });
    }
    if (!fs.existsSync(`${folder}`)) {
      throw new Error(`Store folder not found: ${folder}`);
    }
  }
};

// src/cli.ts
import chalk from "chalk";
import { RpcProvider as RpcProvider4 } from "starknet";
var program = new Command();
var getConfig = (network) => {
  return {
    provider: new RpcProvider4({
      nodeUrl: "https://starknet-mainnet.public.blastapi.io"
    }),
    network,
    stage: "production"
  };
};
async function createStore() {
  console.log(chalk.blue.bold("Welcome to the Account Secure project for Starknet!"));
  const networkAnswers = await inquirer.prompt([
    {
      type: "list",
      name: "network",
      message: chalk.yellow("What is the network?"),
      choices: ["mainnet", "sepolia", "devnet"]
    }
  ]);
  const network = networkAnswers.network;
  const defaultStoreConfig = getDefaultStoreConfig(network);
  const storeConfigAnswers = await inquirer.prompt([
    {
      type: "input",
      name: "secrets_folder",
      message: chalk.yellow(`What is your secrets folder? (${defaultStoreConfig.SECRET_FILE_FOLDER})`),
      default: defaultStoreConfig.SECRET_FILE_FOLDER,
      validate: (input) => true
    },
    {
      type: "input",
      name: "accounts_file",
      message: chalk.yellow(`What is your accounts file? (${defaultStoreConfig.ACCOUNTS_FILE_NAME})`),
      default: defaultStoreConfig.ACCOUNTS_FILE_NAME,
      validate: (input) => true
    },
    {
      type: "input",
      name: "encryption_password",
      message: chalk.yellow(`What is your decryption password? (To generate one, press enter)`),
      default: defaultStoreConfig.PASSWORD,
      validate: (input) => true
    }
  ]);
  const config = getConfig(network);
  const secrets_folder = storeConfigAnswers.secrets_folder;
  const accounts_file = storeConfigAnswers.accounts_file;
  const encryption_password = storeConfigAnswers.encryption_password;
  const store = new Store(config, {
    SECRET_FILE_FOLDER: secrets_folder,
    ACCOUNTS_FILE_NAME: accounts_file,
    PASSWORD: storeConfigAnswers.encryption_password,
    NETWORK: network
  });
  if (defaultStoreConfig.PASSWORD === encryption_password) {
    Store.logPassword(encryption_password);
  }
  return store;
}
program.version("1.0.0").description("Manage accounts securely on your disk with encryption");
program.description("Add accounts securely to your disk with encryption").command("add-account").action(async (options) => {
  const store = await createStore();
  const existingAccountKeys = store.listAccounts();
  const accountAnswers = await inquirer.prompt([
    {
      type: "input",
      name: "account_key",
      message: chalk.yellow(`Provide a unique account key`),
      validate: (input) => input.length > 0 && !existingAccountKeys.includes(input) || "Please enter a unique account key"
    },
    {
      type: "input",
      name: "address",
      message: chalk.yellow(`What is your account address?`),
      validate: (input) => input.length > 0 || "Please enter a valid address"
    },
    {
      type: "input",
      name: "pk",
      message: chalk.yellow(`What is your account private key?`),
      validate: (input) => input.length > 0 || "Please enter a valid pk"
    }
  ]);
  const address = accountAnswers.address;
  const pk = accountAnswers.pk;
  const account_key = accountAnswers.account_key;
  store.addAccount(account_key, address, pk);
  console.log(`${chalk.blue("Account added:")} ${account_key} to network: ${store.config.network}`);
});
program.description("List account names of a network").command("list-accounts").action(async (options) => {
  const store = await createStore();
  const accounts = store.listAccounts();
  console.log(`${chalk.blue("Account keys:")} ${accounts.join(", ")}`);
});
program.description("List account names of a network").command("get-account").action(async (options) => {
  const store = await createStore();
  const existingAccountKeys = store.listAccounts();
  const accountAnswers = await inquirer.prompt([
    {
      type: "input",
      name: "account_key",
      message: chalk.yellow(`Provide a unique account key`),
      validate: (input) => input.length > 0 && existingAccountKeys.includes(input) || "Please enter a value account key"
    }
  ]);
  const account = store.getAccount(accountAnswers.account_key);
  console.log(`${chalk.blue("Account Address:")} ${account.address}`);
});
program.action(() => {
  program.help();
});
program.parse(process.argv);
if (!process.argv.slice(2).length) {
  program.outputHelp();
}
