import { Contract, RpcProvider } from "starknet";
import PragmaAbi from '@/data/pragma.abi.json';
import { logger } from "@/global";

export class Pragma {
    contractAddr = '0x023fb3afbff2c0e3399f896dcf7400acf1a161941cfb386e34a123f228c62832';
    readonly contract: Contract;

    constructor(provider: RpcProvider) {
        this.contract = new Contract(PragmaAbi, this.contractAddr, provider);
    }

    async getPrice(tokenAddr: string) {
        if (!tokenAddr) {
            throw new Error(`Pragma:getPrice - no token`)
        }
        const result: any = await this.contract.call('get_price', [tokenAddr]);
        const price = Number(result.price) / 10**8;
        logger.verbose(`Pragma:${tokenAddr}: ${price}`);
        return price;
    }
}