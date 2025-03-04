import axios from "axios";
import BigNumber from "bignumber.js";
import { Web3Number } from "@/dataTypes/bignumber";
import { FatalError, Global, logger } from "@/global";
import { TokenInfo } from "@/interfaces";
import { ILending, ILendingPosition, LendingToken, MarginType } from "@/interfaces/lending";
import { ContractAddr } from "@/dataTypes/address";
import { IConfig } from "@/interfaces";
import { Pricer } from "./pricer";

export class ZkLend extends ILending implements ILending {
    readonly pricer: Pricer;
    static readonly POOLS_URL = 'https://app.zklend.com/api/pools';
    private POSITION_URL = 'https://app.zklend.com/api/users/{{USER_ADDR}}/all';

    constructor(config: IConfig, pricer: Pricer) {
        super(config, { 
            name: "zkLend",
            logo: 'https://app.zklend.com/favicon.ico'
        });
        this.pricer = pricer;
    }

    async init() {
        try {
            logger.verbose(`Initialising ${this.metadata.name}`);
            const result = await axios.get(ZkLend.POOLS_URL);
            const data: any[] = result.data;
            const savedTokens = await Global.getTokens()
            data.forEach((pool) => {
                let collareralFactor = new Web3Number(0, 0);
                if (pool.collateral_factor) {
                    collareralFactor = Web3Number.fromWei(pool.collateral_factor.value, pool.collateral_factor.decimals);
                }
                const savedTokenInfo = savedTokens.find(t => t.symbol == pool.token.symbol);
                const token: LendingToken = {
                    name: pool.token.name,
                    symbol: pool.token.symbol,
                    address: savedTokenInfo?.address || '',
                    decimals: pool.token.decimals,
                    borrowFactor: Web3Number.fromWei(pool.borrow_factor.value, pool.borrow_factor.decimals),
                    collareralFactor
                }
                this.tokens.push(token);
            });
            logger.info(`Initialised ${this.metadata.name} with ${this.tokens.length} tokens`);
            this.initialised = true;
        } catch (error: any) {
            return Global.httpError(ZkLend.POOLS_URL, error);
        }
    }

    /**
     * @description Get the health factor of the user for given lending and debt tokens
     * @param lending_tokens 
     * @param debt_tokens 
     * @param user 
     * @returns hf (e.g. returns 1.5 for 150% health factor)
     */
    async get_health_factor_tokenwise(lending_tokens: TokenInfo[], debt_tokens: TokenInfo[], user: ContractAddr): Promise<number> {
        const positions = await this.getPositions(user);
        logger.verbose(`${this.metadata.name}:: Positions: ${JSON.stringify(positions)}`);
        
        // Computes Sum of debt USD / borrow factor
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

        // Computs Sum of collateral USD * collateral factor
        let effectiveCollateral = new Web3Number(0, 6);
        positions.filter(pos => {
            const exp1 = lending_tokens.find((t) => t.symbol === pos.tokenSymbol);
            const exp2 = pos.marginType === MarginType.SHARED;
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

        // Health factor = Effective collateral / Effective debt
        const healthFactor = effectiveCollateral.dividedBy(effectiveDebt.toFixed(6)).toNumber();
        logger.verbose(`${this.metadata.name}:: Health factor: ${healthFactor}`);
        return healthFactor;
    }

    /**
     * @description Get the health factor of the user
     * - Considers all tokens for collateral and debt
     */
    async get_health_factor(user: ContractAddr): Promise<number> {
        return this.get_health_factor_tokenwise(this.tokens, this.tokens, user);
    }

    async getPositionsSummary(user: ContractAddr): Promise<{
        collateralUSD: number,
        debtUSD: number,
    }> {
        const pos = await this.getPositions(user);
        const collateralUSD = pos.reduce((acc, p) => acc + p.supplyUSD.toNumber(), 0);
        const debtUSD = pos.reduce((acc, p) => acc + p.debtUSD.toNumber(), 0);
        return {
            collateralUSD,
            debtUSD
        }
    }
    /**
     * @description Get the token-wise collateral and debt positions of the user 
     * @param user Contract address of the user
     * @returns Promise<ILendingPosition[]>
     */
    async getPositions(user: ContractAddr): Promise<ILendingPosition[]> {
        const url = this.POSITION_URL.replace('{{USER_ADDR}}', user.address);
        /**
         * Sample response:
            {"pools":[{"data":{"debt_amount":"0x0","is_collateral":false,"supply_amount":"0x0","wallet_balance":"0x0"},
            "token_symbol":"ETH"},{"data":{"debt_amount":"0x0","is_collateral":false,"supply_amount":"0x0",
            "wallet_balance":"0x0"},"token_symbol":"USDC"}]}
        */
        const result = await axios.get(url);
        const data: any = result.data;
        const lendingPosition: ILendingPosition[] = [];
        logger.verbose(`${this.metadata.name}:: Positions: ${JSON.stringify(data)}`);
        for(let i=0; i<data.pools.length; i++) {
            const pool = data.pools[i];
            const token = this.tokens.find((t) => {
                return t.symbol === pool.token_symbol
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
                marginType: pool.data.is_collateral ? MarginType.SHARED : MarginType.NONE,
                debtAmount,
                debtUSD: debtAmount.multipliedBy(price.toFixed(6)),
                supplyAmount,
                supplyUSD: supplyAmount.multipliedBy(price.toFixed(6))
            });
        };
        return lendingPosition;
    }
}