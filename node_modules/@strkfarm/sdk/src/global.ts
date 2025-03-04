import axios from 'axios';
import { TokenInfo } from './interfaces';

const colors = {
    error: 'red',
    warn: 'yellow',
    info: 'blue',
    verbose: 'white',
    debug: 'white',
}

// Add custom colors to Winston
// winston.addColors(colors);

// export const logger = createLogger({
//   level: 'verbose', // Set the minimum logging level
//   format: format.combine(
//     format.colorize({ all: true }), // Apply custom colors
//     format.timestamp({ format: 'YYYY-MM-DD HH:mm:ss' }), // Add timestamp to log messages
//     format.printf(({ timestamp, level, message }) => {
//       return `${timestamp} ${level}: ${message}`;
//     })
//   ),
//   transports: [
//     // new transports.Console() // Output logs to the console
//   ]
// });


export const logger = {
    ...console,
    verbose(message: string) {
        console.log(`[VERBOSE] ${message}`);
    }
};


export class FatalError extends Error {
    constructor(message: string, err?: Error) {
        super(message);
        logger.error(message);
        if (err)
            logger.error(err.message);
        this.name = "FatalError";
    }
}

const tokens: TokenInfo[] = [];

/** Contains globally useful functions. 
 * - fatalError: Things to do when a fatal error occurs
 */
export class Global {
    static fatalError(message: string, err?: Error) {
        logger.error(message);
        console.error(message, err);
        if (err)
            console.error(err);
        process.exit(1);
    }

    static httpError(url: string, err: Error, message?: string) {
        logger.error(`${url}: ${message}`);
        console.error(err);
    }

    static async getTokens(): Promise<TokenInfo[]> {
        if (tokens.length) return tokens;

        // fetch from avnu API
        const data = await axios.get('https://starknet.api.avnu.fi/v1/starknet/tokens');
        const tokensData = data.data.content;

        // Array of the following is returned
        // {
        //     "name": "USD Coin",
        //     "address": "0x53c91253bc9682c04929ca02ed00b3e423f6710d2ee7e0d5ebb06f3ecf368a8",
        //     "symbol": "USDC",
        //     "decimals": 6,
        //     "logoUri": "https://raw.githubusercontent.com/trustwallet/assets/master/blockchains/ethereum/assets/0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48/logo.png",
        //     "lastDailyVolumeUsd": 2964287916.82621,
        //     "extensions": {
        //       "coingeckoId": "usd-coin"
        //     },
        //     "tags": [
        //       "AVNU",
        //       "Verified"
        //     ]
        // }

        tokensData.forEach((token: any) => {
            // if tags do not contain Avnu and verified, ignore
            // This would exclude meme coins for now
            if (!token.tags.includes('AVNU') || !token.tags.includes('Verified')) {
                return;
            }

            tokens.push({
                name: token.name,
                symbol: token.symbol,
                address: token.address,
                decimals: token.decimals,
                coingeckId: token.extensions.coingeckoId,
            });
        });
        console.log(tokens);
        return tokens;
    }

    static assert(condition: any, message: string) {
        if (!condition) {
            throw new FatalError(message);
        }
    }
}
