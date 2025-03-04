import { num } from "starknet";

/**
 * A simple wrapper around a contract address that is universally comparable
 * - Helps avoid padding issues
 */
export class ContractAddr {
    readonly address: string;

    constructor(address: string) {
        this.address = ContractAddr.standardise(address);
    }

    static from(address: string) {
        return new ContractAddr(address);
    }

    eq(other: ContractAddr) {
        return this.address === other.address;
    }

    eqString(other: string) {
        return this.address === ContractAddr.standardise(other);
    }

    static standardise(address: string | bigint) {
        let _a = address;
        if (!address) {
            _a = "0";
        }
        const a = num.getHexString(num.getDecimalString(_a.toString()));
        return a;
    }

    static eqString(a: string, b: string) {
        return ContractAddr.standardise(a) === ContractAddr.standardise(b);
    }
}