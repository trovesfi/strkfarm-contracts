#!/usr/bin/env node

import { Command } from 'commander';
import inquirer from 'inquirer';
import { Store, getDefaultStoreConfig } from './utils/store';
import chalk from 'chalk';
import { IConfig, Network } from './interfaces';
import { RpcProvider } from 'starknet';

const program = new Command();

const getConfig = (network: Network) => {
    return {
        provider: new RpcProvider({
            nodeUrl: 'https://starknet-mainnet.public.blastapi.io',
        }),
        network: network,
        stage: 'production',
    }
}

async function createStore() {
    console.log(chalk.blue.bold('Welcome to the Account Secure project for Starknet!'));
    const networkAnswers = await (<any>inquirer).prompt([
        {
            type: 'list',
            name: 'network',
            message: chalk.yellow('What is the network?'),
            choices: ['mainnet', 'sepolia', 'devnet'],
        },
    ]);
    const network: Network = networkAnswers.network as Network;
    const defaultStoreConfig = getDefaultStoreConfig(network);

    const storeConfigAnswers = await (<any>inquirer).prompt([
        {
            type: 'input',
            name: 'secrets_folder',
            message: chalk.yellow(`What is your secrets folder? (${defaultStoreConfig.SECRET_FILE_FOLDER})`),
            default: defaultStoreConfig.SECRET_FILE_FOLDER,
            validate: (input: string) => true,
        },
        {
            type: 'input',
            name: 'accounts_file',
            message: chalk.yellow(`What is your accounts file? (${defaultStoreConfig.ACCOUNTS_FILE_NAME})`),
            default: defaultStoreConfig.ACCOUNTS_FILE_NAME,
            validate: (input: string) => true,
        },
        {
            type: 'input',
            name: 'encryption_password',
            message: chalk.yellow(`What is your decryption password? (To generate one, press enter)`),
            default: defaultStoreConfig.PASSWORD,
            validate: (input: string) => true,
        }
    ]);

    const config = getConfig(network);

    const secrets_folder = storeConfigAnswers.secrets_folder;
    const accounts_file = storeConfigAnswers.accounts_file;
    const encryption_password = storeConfigAnswers.encryption_password;

    const store = new Store(config, {
        SECRET_FILE_FOLDER: secrets_folder,
        ACCOUNTS_FILE_NAME: accounts_file,
        PASSWORD: storeConfigAnswers.encryption_password,
        NETWORK: network,
    });

    if (defaultStoreConfig.PASSWORD === encryption_password) {
        Store.logPassword(encryption_password);
    }

    return store;
}

program
  .version('1.0.0')
  .description('Manage accounts securely on your disk with encryption');

program
  .description('Add accounts securely to your disk with encryption')
  .command('add-account')
  .action(async (options) => {
        const store = await createStore();

        const existingAccountKeys = store.listAccounts();

        const accountAnswers = await (<any>inquirer).prompt([
            {
                type: 'input',
                name: 'account_key',
                message: chalk.yellow(`Provide a unique account key`),
                validate: (input: string) => (input.length > 0 && !existingAccountKeys.includes(input)) || 'Please enter a unique account key',
            },
            {
                type: 'input',
                name: 'address',
                message: chalk.yellow(`What is your account address?`),
                validate: (input: string) => input.length > 0 || 'Please enter a valid address',
            },
            {
                type: 'input',
                name: 'pk',
                message: chalk.yellow(`What is your account private key?`),
                validate: (input: string) => input.length > 0 || 'Please enter a valid pk',
            },
        ]);

        const address = accountAnswers.address;
        const pk = accountAnswers.pk;
        const account_key = accountAnswers.account_key;

        store.addAccount(account_key, address, pk);

        console.log(`${chalk.blue("Account added:")} ${account_key} to network: ${store.config.network}`);
    });

program
  .description('List account names of a network')
  .command('list-accounts')
  .action(async (options) => {
    const store = await createStore();
    const accounts = store.listAccounts();
    console.log(`${chalk.blue("Account keys:")} ${accounts.join(', ')}`);
  })

program
  .description('List account names of a network')
  .command('get-account')
  .action(async (options) => {
    const store = await createStore();
    const existingAccountKeys = store.listAccounts();
    const accountAnswers = await (<any>inquirer).prompt([
        {
            type: 'input',
            name: 'account_key',
            message: chalk.yellow(`Provide a unique account key`),
            validate: (input: string) => (input.length > 0 && existingAccountKeys.includes(input)) || 'Please enter a value account key',
        },
    ]);

    const account = store.getAccount(accountAnswers.account_key);
    console.log(`${chalk.blue("Account Address:")} ${account.address}`);
  })

// Default action if no command is provided
program
  .action(() => {
    program.help(); // Show help if no command is provided
  });

program.parse(process.argv);

// Show help if no command is provided
if (!process.argv.slice(2).length) {
  program.outputHelp();
}