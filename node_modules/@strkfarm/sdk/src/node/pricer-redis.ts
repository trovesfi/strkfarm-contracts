import { FatalError, Global, logger } from '@/global';
import { IConfig, TokenInfo } from '@/interfaces';
import { PriceInfo, Pricer } from '@/modules/pricer';
import { createClient } from 'redis';
import type { RedisClientType } from 'redis'

export class PricerRedis extends Pricer {
    private redisClient: RedisClientType | null = null;
    constructor(config: IConfig, tokens: TokenInfo[]) {
        super(config, tokens)
    }

    /** Reads prices from Pricer._loadPrices and uses a callback to set prices in redis */
    async startWithRedis(redisUrl: string) {
        await this.initRedis(redisUrl);

        logger.info(`Starting Pricer with Redis`);
        this._loadPrices(this._setRedisPrices.bind(this));
        setInterval(() => {
            this._loadPrices(this._setRedisPrices.bind(this));
        }, 30000);
    }

    async close() {
        if (this.redisClient) {
            await this.redisClient.disconnect();
        }
    }

    async initRedis(redisUrl: string) {
        logger.info(`Initialising Redis Client`);
        this.redisClient = <RedisClientType>(await createClient({
            url: redisUrl
        }));
        this.redisClient.on('error', (err: any) => console.log('Redis Client Error', err))
        .connect();
        logger.info(`Redis Client Initialised`);
    }

    /** sets current local price in redis */
    private _setRedisPrices(tokenSymbol: string) {
        if (!this.redisClient) {
            throw new FatalError(`Redis client not initialised`);
        }
        this.redisClient.set(`Price:${tokenSymbol}`, JSON.stringify(this.prices[tokenSymbol]))
        .catch(err => {
            logger.warn(`Error setting price in redis for ${tokenSymbol}`);
        })
    }

    /** Returns price from redis */
    async getPrice(tokenSymbol: string) {
        const STALE_TIME = 60000;
        if (!this.redisClient) {
            throw new FatalError(`Redis client not initialised`);
        }
        const data = await this.redisClient.get(`Price:${tokenSymbol}`);
        if (!data) {
            throw new FatalError(`Redis:Price of ${tokenSymbol} not found`);
        }

        logger.verbose(`Redis:Price of ${tokenSymbol} is ${data}`);

        const priceInfo: PriceInfo = JSON.parse(data);
        priceInfo.timestamp = new Date(priceInfo.timestamp);
        const isStale = (new Date().getTime() - priceInfo.timestamp.getTime()) > STALE_TIME;
        Global.assert(!isStale, `Price of ${tokenSymbol} is stale`);
        return priceInfo;

    }
}