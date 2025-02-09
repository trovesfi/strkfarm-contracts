use strkfarm_contracts::helpers::safe_decimal_math;
use starknet::ContractAddress;
use strkfarm_contracts::helpers::ERC20Helper;
use strkfarm_contracts::helpers::constants;

#[derive(Drop, Copy, Serde)]
pub struct BorrowData {
    pub token: ContractAddress,
    pub borrow_factor: u256 // 18 decimals
}

pub trait MMTokenTrait<T, TSettings> {
    // used for hf calculation
    fn collateral_value(self: @T, state: TSettings, user: ContractAddress) -> u256;
    fn required_value(self: @T, state: TSettings, user: ContractAddress) -> u256;
    // collateral value as required by HF
    fn calculate_collateral_value(self: @T, state: TSettings, amount: u256) -> u256;
    fn price(self: @T, state: TSettings) -> (u256, u8);
    fn underlying_asset(self: @T, state: TSettings) -> ContractAddress;
    fn get_borrow_data(self: @T, state: TSettings) -> BorrowData;
}

pub trait ILendMod<TSettings, T> {
    fn deposit(self: TSettings, token: ContractAddress, amount: u256) -> u256;
    fn withdraw(self: TSettings, token: ContractAddress, amount: u256) -> u256;
    fn borrow(self: TSettings, token: ContractAddress, amount: u256) -> u256;
    fn repay(self: TSettings, token: ContractAddress, amount: u256) -> u256;
    fn health_factor(
        self: @TSettings, user: ContractAddress, deposits: Array<T>, borrows: Array<T>
    ) -> u32;
    fn assert_valid(self: @TSettings);
    fn max_borrow_amount(
        self: @TSettings, deposit_token: T, deposit_amount: u256, borrow_token: T, min_hf: u32
    ) -> u256;
    fn min_borrow_required(self: @TSettings, token: ContractAddress,) -> u256;
    fn deposit_amount(self: @TSettings, asset: ContractAddress, user: ContractAddress) -> u256;
    fn borrow_amount(self: @TSettings, asset: ContractAddress, user: ContractAddress) -> u256;
    
    // returns the amount to repay given an amount we want to repay 
    // based on conditions like min borrow amount, etc
    fn get_repay_amount(self: @TSettings, token: ContractAddress, amount: u256) -> u256;
}


pub fn mm_health_factor<
    T,
    TSettings,
    impl TMMTokenTrait: MMTokenTrait<T, TSettings>,
    impl TCopy: Copy<T>,
    impl TDrop: Drop<T>,
    impl TCopy: Copy<TSettings>,
    impl TDrop: Drop<TSettings>,
>(
    self: @TSettings, user: ContractAddress, deposits: Array<T>, borrows: Array<T>
) -> u32 {
    let mut current_collateral_value: u256 = 0;
    let mut index: usize = 0;
    loop {
        if (index == deposits.len()) {
            break;
        }

        let token = deposits[index];
        current_collateral_value += TMMTokenTrait::collateral_value(token, *self, user);
        index += 1;
    };

    let mut required_collateral_value: u256 = 0;
    index = 0;
    loop {
        if (index == borrows.len()) {
            break;
        }

        let token = borrows[index];
        required_collateral_value += TMMTokenTrait::required_value(token, *self, user);
        index += 1;
    };

    if (required_collateral_value == 0) {
        return 10 * 10000; // 10 hf, some random high hf
    }

    safe_decimal_math::div_decimals(
        current_collateral_value, required_collateral_value, 4 // 4 decimals, 100%
    )
        .try_into()
        .unwrap()
}

pub fn max_borrow_amount<
    T,
    TSettings,
    impl TMMTokenTrait: MMTokenTrait<T, TSettings>,
    impl TCopy: Copy<T>,
    impl TDrop: Drop<T>,
    impl TCopy: Copy<TSettings>,
    impl TDrop: Drop<TSettings>,
>(
    self: @TSettings, deposit_token: T, deposit_amount: u256, borrow_token: T, min_hf: u32
) -> u256 {
    // max borrow = collateal amount * col price * col factor * borrow factor / (min hf * borrow
    // price)
    //// println!("Maxborrow: deposit_amount: {:?}", deposit_amount);
    // in 8 decimals as per pragma price
    let col_value_hf = TMMTokenTrait::calculate_collateral_value(
        @deposit_token, *self, deposit_amount
    );
    //// println!("Maxborrow: col_value: {:?}", col_value_hf);
    // even this price_decimals is also 8
    let (borrow_price, _price_decimals) = TMMTokenTrait::price(@borrow_token, *self);
    //// println!("Maxborrow: borrow_price: {:?}", borrow_price);
    let borrow_data = TMMTokenTrait::get_borrow_data(@borrow_token, *self);
    let numerator = safe_decimal_math::mul(col_value_hf, borrow_data.borrow_factor);
    //// println!("Maxborrow: numerator: {:?}", numerator);
    let borrow_underlying = TMMTokenTrait::underlying_asset(@borrow_token, *self);
    let borrow_decimals = ERC20Helper::decimals(borrow_underlying);

    // when numerator divided with (min_hf (in 4 decimals) * borrow_price (in 8 decimals))
    // it needs 4 decimals adjustment. price decimals are compensated with that off col pric
    // but to prevent loss of value, numerator must adjust to borrow token decimals first
    let numerator = safe_decimal_math::normalise(numerator, 0, borrow_decimals);
    //// println!("Maxborrow: numerator: {:?}", numerator);
    let denominator: u256 = min_hf.into() * borrow_price;
    //// println!("Maxborrow: denominator: {:?}", denominator);
    // now multiply with denominator with 4 decimals adjustment (HF units)
    safe_decimal_math::div_decimals(numerator, denominator, 4)
}
