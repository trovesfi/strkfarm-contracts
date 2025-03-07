import { extractContractHashes, json } from "starknet";
import { getRpcProvider } from "./utils";
import { readFileSync, writeFileSync } from "fs";

function getClassHash(contract_name: string, package_name: "strkfarm_contracts") {
    const compiledSierra = json.parse(
        readFileSync(`./target/release/${package_name}_${contract_name}.contract_class.json`).toString("ascii")
    )
    const compiledCasm = json.parse(
    readFileSync(`./target/release/${package_name}_${contract_name}.compiled_contract_class.json`).toString("ascii")
    )
    
    const payload = {
        contract: compiledSierra,
        casm: compiledCasm
    };
    
    const result = extractContractHashes(payload);
    return result.classHash;
}

async function main() {
    // ! Add new contracts to the list
    const contracts = [
        'ConcLiquidityVault',
        'VesuRebalance',
        'AccessControl'
    ];

    const classHashes = contracts.map(contract => ({
        classhash: getClassHash(contract, 'strkfarm_contracts'),
        contract_name: contract
    }));
    console.log(classHashes);
    writeFileSync('./class_hashes.json', JSON.stringify(classHashes, null, 2));
}

if (require.main === module) {
    main().catch((err: any) => {
        console.error(err);
        process.exit(1);
    });
}