import { ContractAddr, Web3Number } from "@/dataTypes";
import { IConfig } from "@/interfaces";
import { Contract, RpcProvider, uint256 } from "starknet";
import { Pricer } from "@/modules/pricer";

export class AutoCompounderSTRK {
    readonly config: IConfig;
    readonly addr = ContractAddr.from('0x541681b9ad63dff1b35f79c78d8477f64857de29a27902f7298f7b620838ea');
    readonly pricer: Pricer;
    private initialized: boolean = false;

    contract: Contract | null = null;

    readonly metadata = {
        decimals: 18,
        underlying: {
            // zSTRK
            address: ContractAddr.from('0x06d8fa671ef84f791b7f601fa79fea8f6ceb70b5fa84189e3159d532162efc21'),
            name: 'STRK',
            symbol: 'STRK',
        },
        name: 'AutoCompounderSTRK',
    }

    constructor(config: IConfig, pricer: Pricer) {
        this.config = config;
        this.pricer = pricer;
        this.init();
    }

    async init() {
        const provider: RpcProvider = this.config.provider;
        const cls = await provider.getClassAt(this.addr.address);
        this.contract = new Contract(cls.abi, this.addr.address, provider);
        this.initialized = true;
    }

    async waitForInitilisation() {
        return new Promise<void>((resolve, reject) => {
            const interval = setInterval(() => {
                if (this.initialized) {
                    clearInterval(interval);
                    resolve();
                }
            }, 1000);
        });
    }

    /** Returns shares of user */
    async balanceOf(user: ContractAddr) {
        const result = await this.contract!.balanceOf(user.address);
        return Web3Number.fromWei(result.toString(), this.metadata.decimals);
    }

    /** Returns underlying assets of user */
    async balanceOfUnderlying(user: ContractAddr) {
        const balanceShares = await this.balanceOf(user);
        const assets = await this.contract!.convert_to_assets(uint256.bnToUint256(balanceShares.toWei()));
        return Web3Number.fromWei(assets.toString(), this.metadata.decimals);
    }

    /** Returns usd value of assets */
    async usdBalanceOfUnderlying(user: ContractAddr) {
        const assets = await this.balanceOfUnderlying(user);
        const price = await this.pricer.getPrice(this.metadata.underlying.name);
        const usd = assets.multipliedBy(price.price.toFixed(6))
        return {
            usd,
            assets
        }
    }
}