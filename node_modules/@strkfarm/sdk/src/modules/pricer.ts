import axios from "axios";
import { FatalError, Global, logger } from "@/global";
import { TokenInfo } from "@/interfaces/common";
import { IConfig } from "@/interfaces/common";
import { Web3Number } from "@/dataTypes";
const CoinMarketCap = require('coinmarketcap-api')

export interface PriceInfo {
    price: number,
    timestamp: Date
}
export class Pricer {
    readonly config: IConfig;
    readonly tokens: TokenInfo[] = [];
    protected prices: {
        [key: string]: PriceInfo
    } = {}

    // code populates this map during runtime to determine which method to use for a given token
    // The method set will be the first one to try after first attempt
    private methodToUse: {[tokenSymbol: string]: 'Ekubo' | 'Coinbase' | 'Coinmarketcap'} = {};

    /**
     * TOKENA and TOKENB are the two token names to get price of TokenA in terms of TokenB
     */
    protected PRICE_API = `https://api.coinbase.com/v2/prices/{{PRICER_KEY}}/buy`;
    protected EKUBO_API = 'https://quoter-mainnet-api.ekubo.org/{{AMOUNT}}/{{TOKEN_ADDRESS}}/0x053c91253bc9682c04929ca02ed00b3e423f6710d2ee7e0d5ebb06f3ecf368a8'; // e.g. ETH/USDC

    // backup oracle001
    protected client = new CoinMarketCap(process.env.COINMARKETCAP_KEY!);
    
    constructor(config: IConfig, tokens: TokenInfo[]) {
        this.config = config;
        this.tokens = tokens;
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
        return new Promise<void>((resolve, reject) => {
            const interval = setInterval(() => {
                logger.verbose(`Waiting for pricer to initialise`);
                if (this.isReady()) {
                    logger.verbose(`Pricer initialised`);
                    clearInterval(interval);
                    resolve();
                }
            }, 1000);
        });
    }

    start() {
        this._loadPrices();
        setInterval(() => {
            this._loadPrices();
        }, 30000);
    }

    isStale(timestamp: Date, tokenName: string) {
        const STALE_TIME = 60000;
        return (new Date().getTime() - timestamp.getTime()) > STALE_TIME;
    }

    assertNotStale(timestamp: Date, tokenName: string) {
        Global.assert(!this.isStale(timestamp, tokenName), `Price of ${tokenName} is stale`);

    }
    async getPrice(tokenName: string) {
        Global.assert(this.prices[tokenName], `Price of ${tokenName} not found`);
       this.assertNotStale(this.prices[tokenName].timestamp, tokenName);
        return this.prices[tokenName];
    }

    protected _loadPrices(onUpdate: (tokenSymbol: string) => void = () => {}) {
        this.tokens.forEach(async (token) => {
            const MAX_RETRIES = 10;
            let retry = 0;
            while (retry < MAX_RETRIES) {
                try {
                    if (token.symbol === 'USDT') {
                        this.prices[token.symbol] = {
                            price: 1,
                            timestamp: new Date()
                        }
                        onUpdate(token.symbol);
                        return;
                    }
                    
                    const price = await this._getPrice(token);
                    this.prices[token.symbol] = {
                        price,
                        timestamp: new Date()
                    }
                    onUpdate(token.symbol);
                    logger.verbose(`Fetched price of ${token.name} as ${price}`);
                    break;
                } catch (error: any) {
                    if (retry < MAX_RETRIES) {
                        logger.warn(`Error fetching data from ${token.name}, retry: ${retry}`);
                        logger.warn(error);
                        retry++;
                        await new Promise((resolve) => setTimeout(resolve, retry * 2000));
                    } else {
                        throw new FatalError(`Error fetching data from ${token.name}`, error);
                    }
                }
            }
        })
        if (this.isReady() && this.config.heartbeatUrl) {
            console.log(`sending beat`)
            axios.get(this.config.heartbeatUrl).catch(err => {
                console.error('Pricer: Heartbeat err', err);
            })
        }
    }

    async _getPrice(token: TokenInfo, defaultMethod = 'all'): Promise<number> {
        const methodToUse: string = this.methodToUse[token.symbol] || defaultMethod; // default start with coinbase
        logger.info(`Fetching price of ${token.symbol} using ${methodToUse}`);
        switch (methodToUse) {
            case 'Coinbase':
                try {
                    const result = await this._getPriceCoinbase(token);
                    this.methodToUse[token.symbol] = 'Coinbase';
                    return result;
                } catch (error: any) {
                    console.warn(`Coinbase: price err: message [${token.symbol}]: `, error.message);
                    // do nothing, try next
                }
            case 'Coinmarketcap':
                try {
                    const result = await this._getPriceCoinMarketCap(token);
                    this.methodToUse[token.symbol] = 'Coinmarketcap';
                    return result;
                } catch (error: any) {
                    console.warn(`CoinMarketCap: price err [${token.symbol}]: `, Object.keys(error));
                    console.warn(`CoinMarketCap: price err [${token.symbol}]: `, error.message);
                }
            case 'Ekubo':
                try {
                    const result = await this._getPriceEkubo(token);
                    this.methodToUse[token.symbol] = 'Ekubo';
                    return result;
                } catch (error: any) {
                    console.warn(`Ekubo: price err [${token.symbol}]: `, error.message);
                    console.warn(`Ekubo: price err [${token.symbol}]: `, Object.keys(error));
                    // do nothing, try next
                }
        }

        // if methodToUse is the default one, pass Coinbase to try all from start
        if (defaultMethod == 'all') {
            // try again with coinbase
            return await this._getPrice(token, 'Coinbase');
        }

        throw new FatalError(`Price not found for ${token.symbol}`);
    }

    async _getPriceCoinbase(token: TokenInfo) {
        const url = this.PRICE_API.replace("{{PRICER_KEY}}", `${token.symbol}-USD`);
        const result = await axios.get(url)
        const data: any = result.data;
        return Number(data.data.amount);
    }

    async _getPriceCoinMarketCap(token: TokenInfo): Promise<number> {
        const result = await this.client.getQuotes({symbol: token.symbol});
        if (result.data)
            return result.data[token.symbol].quote.USD.price as number

        throw new Error(result);
    }

    async _getPriceEkubo(token: TokenInfo, amountIn = new Web3Number(1, token.decimals), retry = 0): Promise<number> {
        const url = this.EKUBO_API.replace("{{TOKEN_ADDRESS}}", token.address).replace("{{AMOUNT}}", amountIn.toWei());
        const result = await axios.get(url);
        const data: any = result.data;
        const outputUSDC = Number(Web3Number.fromWei(data.total_calculated, 6).toFixed(6));
        logger.verbose(`Ekubo: ${token.symbol} -> USDC: ${outputUSDC}, retry: ${retry}`);
        if (outputUSDC === 0 && retry < 3) {
            // try again with a higher amount
            const amountIn = new Web3Number(100, token.decimals); // 100 unit of token
            return await this._getPriceEkubo(token, amountIn, retry + 1);
        }

        // if usdc depegs, it will not longer be 1 USD
        // so we need to get the price of USDC in USD
        // and then convert the outputUSDC to USD
        const usdcPrice = 1; // (await this.getPrice('USDC')).price;
        logger.verbose(`USDC Price: ${usdcPrice}`);
        return outputUSDC * usdcPrice;
    }
}