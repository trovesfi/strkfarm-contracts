use starknet::ContractAddress;
use openzeppelin::token::erc20::interface::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};

pub fn balanceOf(token: ContractAddress, address: ContractAddress) -> u256 {
    dispatcher(token).balanceOf(address)
}

fn dispatcher(token: ContractAddress) -> ERC20ABIDispatcher {
    ERC20ABIDispatcher { contract_address: token }
}

pub fn approve(token: ContractAddress, spender: ContractAddress, amount: u256) {
    if (amount != 0) {
        let approved = dispatcher(token).approve(spender, amount);
        assert(approved, 'Approval failed');
    }
}

pub fn transfer_from(
    token: ContractAddress, from: ContractAddress, to: ContractAddress, amount: u256
) {
    if (amount != 0) {
        let transferred = dispatcher(token).transferFrom(from, to, amount);
        assert(transferred, 'Transfer  failed');
    }
}

pub fn strict_transfer_from(
    token: ContractAddress, from: ContractAddress, to: ContractAddress, amount: u256
) {
    assert(amount != 0, 'TransferFrm: Amt 0');
    transfer_from(token, from, to, amount);
}

pub fn transfer(token: ContractAddress, to: ContractAddress, amount: u256) {
    if (amount != 0) {
        let transferred = dispatcher(token).transfer(to, amount);
        assert(transferred, 'Transfer failed');
    }
}

pub fn strict_transfer(token: ContractAddress, to: ContractAddress, amount: u256) {
    assert(amount != 0, 'Transfer: Amt 0');
    transfer(token, to, amount);
}

pub fn decimals(token: ContractAddress) -> u8 {
    dispatcher(token).decimals()
}

pub fn total_supply(token: ContractAddress) -> u256 {
    dispatcher(token).total_supply()
}

pub fn allowance(token: ContractAddress, owner: ContractAddress, spender: ContractAddress) -> u256 {
    dispatcher(token).allowance(owner, spender)
}
