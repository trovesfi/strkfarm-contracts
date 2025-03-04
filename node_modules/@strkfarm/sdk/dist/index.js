"use strict";
var __create = Object.create;
var __defProp = Object.defineProperty;
var __getOwnPropDesc = Object.getOwnPropertyDescriptor;
var __getOwnPropNames = Object.getOwnPropertyNames;
var __getProtoOf = Object.getPrototypeOf;
var __hasOwnProp = Object.prototype.hasOwnProperty;
var __export = (target, all) => {
  for (var name in all)
    __defProp(target, name, { get: all[name], enumerable: true });
};
var __copyProps = (to, from, except, desc) => {
  if (from && typeof from === "object" || typeof from === "function") {
    for (let key of __getOwnPropNames(from))
      if (!__hasOwnProp.call(to, key) && key !== except)
        __defProp(to, key, { get: () => from[key], enumerable: !(desc = __getOwnPropDesc(from, key)) || desc.enumerable });
  }
  return to;
};
var __toESM = (mod, isNodeMode, target) => (target = mod != null ? __create(__getProtoOf(mod)) : {}, __copyProps(
  // If the importer is in node compatibility mode or this is not an ESM
  // file that has been converted to a CommonJS file using a Babel-
  // compatible transform (i.e. "__esModule" has not been set), then set
  // "default" to the CommonJS "module.exports" for node compatibility.
  isNodeMode || !mod || !mod.__esModule ? __defProp(target, "default", { value: mod, enumerable: true }) : target,
  mod
));
var __toCommonJS = (mod) => __copyProps(__defProp({}, "__esModule", { value: true }), mod);

// src/index.ts
var src_exports = {};
__export(src_exports, {
  AutoCompounderSTRK: () => AutoCompounderSTRK,
  ContractAddr: () => ContractAddr,
  FatalError: () => FatalError,
  Global: () => Global,
  ILending: () => ILending,
  Initializable: () => Initializable,
  MarginType: () => MarginType,
  Network: () => Network,
  PasswordJsonCryptoUtil: () => PasswordJsonCryptoUtil,
  Pragma: () => Pragma,
  Pricer: () => Pricer,
  PricerRedis: () => PricerRedis,
  Store: () => Store,
  TelegramNotif: () => TelegramNotif,
  Web3Number: () => Web3Number,
  ZkLend: () => ZkLend,
  getDefaultStoreConfig: () => getDefaultStoreConfig,
  getMainnetConfig: () => getMainnetConfig,
  logger: () => logger
});
module.exports = __toCommonJS(src_exports);

// src/modules/pricer.ts
var import_axios2 = __toESM(require("axios"));

// src/global.ts
var import_axios = __toESM(require("axios"));
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
    const data = await import_axios.default.get("https://starknet.api.avnu.fi/v1/starknet/tokens");
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
var import_bignumber = __toESM(require("bignumber.js"));
var Web3Number = class _Web3Number extends import_bignumber.default {
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
import_bignumber.default.config({ DECIMAL_PLACES: 18 });
Web3Number.config({ DECIMAL_PLACES: 18 });

// src/dataTypes/address.ts
var import_starknet = require("starknet");
var ContractAddr = class _ContractAddr {
  constructor(address) {
    this.address = _ContractAddr.standardise(address);
  }
  static from(address) {
    return new _ContractAddr(address);
  }
  eq(other) {
    return this.address === other.address;
  }
  eqString(other) {
    return this.address === _ContractAddr.standardise(other);
  }
  static standardise(address) {
    let _a = address;
    if (!address) {
      _a = "0";
    }
    const a = import_starknet.num.getHexString(import_starknet.num.getDecimalString(_a.toString()));
    return a;
  }
  static eqString(a, b) {
    return _ContractAddr.standardise(a) === _ContractAddr.standardise(b);
  }
};

// src/modules/pricer.ts
var CoinMarketCap = require("coinmarketcap-api");
var Pricer = class {
  constructor(config, tokens2) {
    this.tokens = [];
    this.prices = {};
    // code populates this map during runtime to determine which method to use for a given token
    // The method set will be the first one to try after first attempt
    this.methodToUse = {};
    /**
     * TOKENA and TOKENB are the two token names to get price of TokenA in terms of TokenB
     */
    this.PRICE_API = `https://api.coinbase.com/v2/prices/{{PRICER_KEY}}/buy`;
    this.EKUBO_API = "https://quoter-mainnet-api.ekubo.org/{{AMOUNT}}/{{TOKEN_ADDRESS}}/0x053c91253bc9682c04929ca02ed00b3e423f6710d2ee7e0d5ebb06f3ecf368a8";
    // e.g. ETH/USDC
    // backup oracle001
    this.client = new CoinMarketCap(process.env.COINMARKETCAP_KEY);
    this.config = config;
    this.tokens = tokens2;
  }
  isReady() {
    const allPricesExist = Object.keys(this.prices).length === this.tokens.length;
    if (!allPricesExist) return false;
    let atleastOneStale = false;
    for (let token of this.tokens) {
      const priceInfo = this.prices[token.symbol];
      const isStale = this.isStale(priceInfo.timestamp, token.symbol);
      if (isStale) {
        atleastOneStale = true;
        logger.warn(`Atleast one stale: ${token.symbol}: ${JSON.stringify(this.prices[token.symbol])}`);
        break;
      }
    }
    return allPricesExist && !atleastOneStale;
  }
  waitTillReady() {
    return new Promise((resolve, reject) => {
      const interval = setInterval(() => {
        logger.verbose(`Waiting for pricer to initialise`);
        if (this.isReady()) {
          logger.verbose(`Pricer initialised`);
          clearInterval(interval);
          resolve();
        }
      }, 1e3);
    });
  }
  start() {
    this._loadPrices();
    setInterval(() => {
      this._loadPrices();
    }, 3e4);
  }
  isStale(timestamp, tokenName) {
    const STALE_TIME = 6e4;
    return (/* @__PURE__ */ new Date()).getTime() - timestamp.getTime() > STALE_TIME;
  }
  assertNotStale(timestamp, tokenName) {
    Global.assert(!this.isStale(timestamp, tokenName), `Price of ${tokenName} is stale`);
  }
  async getPrice(tokenName) {
    Global.assert(this.prices[tokenName], `Price of ${tokenName} not found`);
    this.assertNotStale(this.prices[tokenName].timestamp, tokenName);
    return this.prices[tokenName];
  }
  _loadPrices(onUpdate = () => {
  }) {
    this.tokens.forEach(async (token) => {
      const MAX_RETRIES = 10;
      let retry = 0;
      while (retry < MAX_RETRIES) {
        try {
          if (token.symbol === "USDT") {
            this.prices[token.symbol] = {
              price: 1,
              timestamp: /* @__PURE__ */ new Date()
            };
            onUpdate(token.symbol);
            return;
          }
          const price = await this._getPrice(token);
          this.prices[token.symbol] = {
            price,
            timestamp: /* @__PURE__ */ new Date()
          };
          onUpdate(token.symbol);
          logger.verbose(`Fetched price of ${token.name} as ${price}`);
          break;
        } catch (error) {
          if (retry < MAX_RETRIES) {
            logger.warn(`Error fetching data from ${token.name}, retry: ${retry}`);
            logger.warn(error);
            retry++;
            await new Promise((resolve) => setTimeout(resolve, retry * 2e3));
          } else {
            throw new FatalError(`Error fetching data from ${token.name}`, error);
          }
        }
      }
    });
    if (this.isReady() && this.config.heartbeatUrl) {
      console.log(`sending beat`);
      import_axios2.default.get(this.config.heartbeatUrl).catch((err) => {
        console.error("Pricer: Heartbeat err", err);
      });
    }
  }
  async _getPrice(token, defaultMethod = "all") {
    const methodToUse = this.methodToUse[token.symbol] || defaultMethod;
    logger.info(`Fetching price of ${token.symbol} using ${methodToUse}`);
    switch (methodToUse) {
      case "Coinbase":
        try {
          const result = await this._getPriceCoinbase(token);
          this.methodToUse[token.symbol] = "Coinbase";
          return result;
        } catch (error) {
          console.warn(`Coinbase: price err: message [${token.symbol}]: `, error.message);
        }
      case "Coinmarketcap":
        try {
          const result = await this._getPriceCoinMarketCap(token);
          this.methodToUse[token.symbol] = "Coinmarketcap";
          return result;
        } catch (error) {
          console.warn(`CoinMarketCap: price err [${token.symbol}]: `, Object.keys(error));
          console.warn(`CoinMarketCap: price err [${token.symbol}]: `, error.message);
        }
      case "Ekubo":
        try {
          const result = await this._getPriceEkubo(token);
          this.methodToUse[token.symbol] = "Ekubo";
          return result;
        } catch (error) {
          console.warn(`Ekubo: price err [${token.symbol}]: `, error.message);
          console.warn(`Ekubo: price err [${token.symbol}]: `, Object.keys(error));
        }
    }
    if (defaultMethod == "all") {
      return await this._getPrice(token, "Coinbase");
    }
    throw new FatalError(`Price not found for ${token.symbol}`);
  }
  async _getPriceCoinbase(token) {
    const url = this.PRICE_API.replace("{{PRICER_KEY}}", `${token.symbol}-USD`);
    const result = await import_axios2.default.get(url);
    const data = result.data;
    return Number(data.data.amount);
  }
  async _getPriceCoinMarketCap(token) {
    const result = await this.client.getQuotes({ symbol: token.symbol });
    if (result.data)
      return result.data[token.symbol].quote.USD.price;
    throw new Error(result);
  }
  async _getPriceEkubo(token, amountIn = new Web3Number(1, token.decimals), retry = 0) {
    const url = this.EKUBO_API.replace("{{TOKEN_ADDRESS}}", token.address).replace("{{AMOUNT}}", amountIn.toWei());
    const result = await import_axios2.default.get(url);
    const data = result.data;
    const outputUSDC = Number(Web3Number.fromWei(data.total_calculated, 6).toFixed(6));
    logger.verbose(`Ekubo: ${token.symbol} -> USDC: ${outputUSDC}, retry: ${retry}`);
    if (outputUSDC === 0 && retry < 3) {
      const amountIn2 = new Web3Number(100, token.decimals);
      return await this._getPriceEkubo(token, amountIn2, retry + 1);
    }
    const usdcPrice = 1;
    logger.verbose(`USDC Price: ${usdcPrice}`);
    return outputUSDC * usdcPrice;
  }
};

// src/modules/pragma.ts
var import_starknet2 = require("starknet");

// src/data/pragma.abi.json
var pragma_abi_default = [
  {
    data: [
      {
        name: "previousOwner",
        type: "felt"
      },
      {
        name: "newOwner",
        type: "felt"
      }
    ],
    keys: [],
    name: "OwnershipTransferred",
    type: "event"
  },
  {
    data: [
      {
        name: "token",
        type: "felt"
      },
      {
        name: "source",
        type: "felt"
      }
    ],
    keys: [],
    name: "TokenSourceChanged",
    type: "event"
  },
  {
    name: "constructor",
    type: "constructor",
    inputs: [
      {
        name: "owner",
        type: "felt"
      }
    ],
    outputs: []
  },
  {
    name: "get_price",
    type: "function",
    inputs: [
      {
        name: "token",
        type: "felt"
      }
    ],
    outputs: [
      {
        name: "price",
        type: "felt"
      }
    ],
    stateMutability: "view"
  },
  {
    name: "get_price_with_time",
    type: "function",
    inputs: [
      {
        name: "token",
        type: "felt"
      }
    ],
    outputs: [
      {
        name: "price",
        type: "felt"
      },
      {
        name: "update_time",
        type: "felt"
      }
    ],
    stateMutability: "view"
  },
  {
    name: "set_token_source",
    type: "function",
    inputs: [
      {
        name: "token",
        type: "felt"
      },
      {
        name: "source",
        type: "felt"
      }
    ],
    outputs: []
  }
];

// src/modules/pragma.ts
var Pragma = class {
  constructor(provider) {
    this.contractAddr = "0x023fb3afbff2c0e3399f896dcf7400acf1a161941cfb386e34a123f228c62832";
    this.contract = new import_starknet2.Contract(pragma_abi_default, this.contractAddr, provider);
  }
  async getPrice(tokenAddr) {
    if (!tokenAddr) {
      throw new Error(`Pragma:getPrice - no token`);
    }
    const result = await this.contract.call("get_price", [tokenAddr]);
    const price = Number(result.price) / 10 ** 8;
    logger.verbose(`Pragma:${tokenAddr}: ${price}`);
    return price;
  }
};

// src/modules/zkLend.ts
var import_axios3 = __toESM(require("axios"));

// src/interfaces/lending.ts
var MarginType = /* @__PURE__ */ ((MarginType2) => {
  MarginType2["SHARED"] = "shared";
  MarginType2["NONE"] = "none";
  return MarginType2;
})(MarginType || {});
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
      const result = await import_axios3.default.get(_ZkLend.POOLS_URL);
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
    const result = await import_axios3.default.get(url);
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
var import_starknet3 = require("starknet");
var Network = /* @__PURE__ */ ((Network2) => {
  Network2["mainnet"] = "mainnet";
  Network2["sepolia"] = "sepolia";
  Network2["devnet"] = "devnet";
  return Network2;
})(Network || {});
function getMainnetConfig(rpcUrl = "https://starknet-mainnet.public.blastapi.io", blockIdentifier = "pending") {
  return {
    provider: new import_starknet3.RpcProvider({
      nodeUrl: rpcUrl,
      blockIdentifier
    }),
    stage: "production",
    network: "mainnet" /* mainnet */
  };
}

// src/interfaces/initializable.ts
var Initializable = class {
  constructor() {
    this.initialized = false;
  }
  async waitForInitilisation() {
    return new Promise((resolve, reject) => {
      const interval = setInterval(() => {
        if (this.initialized) {
          console.log("Initialised");
          clearInterval(interval);
          resolve();
        }
      }, 1e3);
    });
  }
};

// src/strategies/autoCompounderStrk.ts
var import_starknet4 = require("starknet");
var AutoCompounderSTRK = class {
  constructor(config, pricer) {
    this.addr = ContractAddr.from("0x541681b9ad63dff1b35f79c78d8477f64857de29a27902f7298f7b620838ea");
    this.initialized = false;
    this.contract = null;
    this.metadata = {
      decimals: 18,
      underlying: {
        // zSTRK
        address: ContractAddr.from("0x06d8fa671ef84f791b7f601fa79fea8f6ceb70b5fa84189e3159d532162efc21"),
        name: "STRK",
        symbol: "STRK"
      },
      name: "AutoCompounderSTRK"
    };
    this.config = config;
    this.pricer = pricer;
    this.init();
  }
  async init() {
    const provider = this.config.provider;
    const cls = await provider.getClassAt(this.addr.address);
    this.contract = new import_starknet4.Contract(cls.abi, this.addr.address, provider);
    this.initialized = true;
  }
  async waitForInitilisation() {
    return new Promise((resolve, reject) => {
      const interval = setInterval(() => {
        if (this.initialized) {
          clearInterval(interval);
          resolve();
        }
      }, 1e3);
    });
  }
  /** Returns shares of user */
  async balanceOf(user) {
    const result = await this.contract.balanceOf(user.address);
    return Web3Number.fromWei(result.toString(), this.metadata.decimals);
  }
  /** Returns underlying assets of user */
  async balanceOfUnderlying(user) {
    const balanceShares = await this.balanceOf(user);
    const assets = await this.contract.convert_to_assets(import_starknet4.uint256.bnToUint256(balanceShares.toWei()));
    return Web3Number.fromWei(assets.toString(), this.metadata.decimals);
  }
  /** Returns usd value of assets */
  async usdBalanceOfUnderlying(user) {
    const assets = await this.balanceOfUnderlying(user);
    const price = await this.pricer.getPrice(this.metadata.underlying.name);
    const usd = assets.multipliedBy(price.price.toFixed(6));
    return {
      usd,
      assets
    };
  }
};

// src/notifs/telegram.ts
var import_node_telegram_bot_api = __toESM(require("node-telegram-bot-api"));
var TelegramNotif = class {
  constructor(token, shouldPoll) {
    this.subscribers = [
      // '6820228303',
      "1505578076",
      // '5434736198', // maaza
      "1356705582",
      // langs
      "1388729514",
      // hwashere
      "6020162572",
      //minato
      "985902592"
    ];
    this.bot = new import_node_telegram_bot_api.default(token, { polling: shouldPoll });
  }
  // listen to start msgs, register chatId and send registered msg
  activateChatBot() {
    this.bot.on("message", (msg) => {
      const chatId = msg.chat.id;
      let text = msg.text.toLowerCase().trim();
      logger.verbose(`Tg: IncomingMsg: ID: ${chatId}, msg: ${text}`);
      if (text == "start") {
        this.bot.sendMessage(chatId, "Registered");
        this.subscribers.push(chatId);
        logger.verbose(`Tg: New subscriber: ${chatId}`);
      } else {
        this.bot.sendMessage(chatId, "Unrecognized command. Supported commands: start");
      }
    });
  }
  // send a given msg to all registered users
  sendMessage(msg) {
    logger.verbose(`Tg: Sending message: ${msg}`);
    for (let chatId of this.subscribers) {
      this.bot.sendMessage(chatId, msg).catch((err) => {
        logger.error(`Tg: Error sending msg to ${chatId}`);
        logger.error(`Tg: Error sending message: ${err.message}`);
      }).then(() => {
        logger.verbose(`Tg: Message sent to ${chatId}`);
      });
    }
  }
};

// src/utils/store.ts
var import_fs = __toESM(require("fs"));
var import_starknet5 = require("starknet");
var crypto2 = __toESM(require("crypto"));

// src/utils/encrypt.ts
var crypto = __toESM(require("crypto"));
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
    return new import_starknet5.Account(this.config.provider, data.address, data.pk);
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
    (0, import_fs.writeFileSync)(this.getAccountFilePath(), encryptedData);
    logger.verbose(`Account added: ${accountKey} to network: ${this.config.network}`);
  }
  getAccountFilePath() {
    const path = `${this.storeConfig.SECRET_FILE_FOLDER}/${this.storeConfig.ACCOUNTS_FILE_NAME}`;
    logger.verbose(`Path: ${path}`);
    return path;
  }
  getAllAccounts() {
    const PATH = this.getAccountFilePath();
    if (!import_fs.default.existsSync(PATH)) {
      logger.verbose(`Accounts: files doesnt exist`);
      return {};
    }
    let encryptedData = (0, import_fs.readFileSync)(PATH, {
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
    if (!import_fs.default.existsSync(folder)) {
      import_fs.default.mkdirSync(folder, { recursive: true });
    }
    if (!import_fs.default.existsSync(`${folder}`)) {
      throw new Error(`Store folder not found: ${folder}`);
    }
  }
};

// src/node/pricer-redis.ts
var import_redis = require("redis");
var PricerRedis = class extends Pricer {
  constructor(config, tokens2) {
    super(config, tokens2);
    this.redisClient = null;
  }
  /** Reads prices from Pricer._loadPrices and uses a callback to set prices in redis */
  async startWithRedis(redisUrl) {
    await this.initRedis(redisUrl);
    logger.info(`Starting Pricer with Redis`);
    this._loadPrices(this._setRedisPrices.bind(this));
    setInterval(() => {
      this._loadPrices(this._setRedisPrices.bind(this));
    }, 3e4);
  }
  async close() {
    if (this.redisClient) {
      await this.redisClient.disconnect();
    }
  }
  async initRedis(redisUrl) {
    logger.info(`Initialising Redis Client`);
    this.redisClient = await (0, import_redis.createClient)({
      url: redisUrl
    });
    this.redisClient.on("error", (err) => console.log("Redis Client Error", err)).connect();
    logger.info(`Redis Client Initialised`);
  }
  /** sets current local price in redis */
  _setRedisPrices(tokenSymbol) {
    if (!this.redisClient) {
      throw new FatalError(`Redis client not initialised`);
    }
    this.redisClient.set(`Price:${tokenSymbol}`, JSON.stringify(this.prices[tokenSymbol])).catch((err) => {
      logger.warn(`Error setting price in redis for ${tokenSymbol}`);
    });
  }
  /** Returns price from redis */
  async getPrice(tokenSymbol) {
    const STALE_TIME = 6e4;
    if (!this.redisClient) {
      throw new FatalError(`Redis client not initialised`);
    }
    const data = await this.redisClient.get(`Price:${tokenSymbol}`);
    if (!data) {
      throw new FatalError(`Redis:Price of ${tokenSymbol} not found`);
    }
    logger.verbose(`Redis:Price of ${tokenSymbol} is ${data}`);
    const priceInfo = JSON.parse(data);
    priceInfo.timestamp = new Date(priceInfo.timestamp);
    const isStale = (/* @__PURE__ */ new Date()).getTime() - priceInfo.timestamp.getTime() > STALE_TIME;
    Global.assert(!isStale, `Price of ${tokenSymbol} is stale`);
    return priceInfo;
  }
};
// Annotate the CommonJS export names for ESM import in node:
0 && (module.exports = {
  AutoCompounderSTRK,
  ContractAddr,
  FatalError,
  Global,
  ILending,
  Initializable,
  MarginType,
  Network,
  PasswordJsonCryptoUtil,
  Pragma,
  Pricer,
  PricerRedis,
  Store,
  TelegramNotif,
  Web3Number,
  ZkLend,
  getDefaultStoreConfig,
  getMainnetConfig,
  logger
});
