import BigNumber from "bignumber.js";
// import { inspect } from 'util';
// const customInspectSymbol = inspect.custom || Symbol.for('nodejs.util.inspect.custom');

function isNode() {
    // Check for the presence of the `window` object, which is undefined in Node.js
    return typeof window === 'undefined';
}

export class Web3Number extends BigNumber {
    decimals: number;

    constructor(value: string | number, decimals: number) {
        super(value);
        this.decimals = decimals;
    }

    static fromWei(weiNumber: string | number, decimals: number) {
        const bn = (new Web3Number(weiNumber, decimals)).dividedBy(10 ** decimals)
        return new Web3Number(bn.toString(), decimals);
    }

    toWei() {
        return this.mul(10 ** this.decimals).toFixed(0);
    }

    multipliedBy(value: string | number) {
        return new Web3Number(this.mul(value).toString(), this.decimals);
    }

    dividedBy(value: string | number) {
        return new Web3Number(this.div(value).toString(), this.decimals);
    }

    plus(value: string | number) {
        return new Web3Number(this.add(value).toString(), this.decimals);
    }

    minus(n: number | string, base?: number): Web3Number {
        return new Web3Number(super.minus(n, base).toString(), this.decimals);
    }

    toString(base?: number | undefined): string {
        return super.toString(base);
    }
    
    // [customInspectSymbol](depth: any, inspectOptions: any, inspect: any) {
    // return this.toString();
    // }
}

BigNumber.config({ DECIMAL_PLACES: 18 })
Web3Number.config({ DECIMAL_PLACES: 18 })
