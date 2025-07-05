use snforge_std::{
    start_cheat_caller_address, stop_cheat_caller_address
};
use starknet::{ContractAddress, contract_address_const, get_contract_address};

// Import token and helper utilities
use strkfarm_contracts::helpers::constants;
use strkfarm_contracts::helpers::ERC20Helper;

// Import Ekubo interfaces
use strkfarm_contracts::interfaces::IEkuboCore::{
    PoolKey, Bounds
};
use strkfarm_contracts::interfaces::IEkuboPosition::{
    IEkuboDispatcher, IEkuboDispatcherTrait, GetTokenInfoResult
};

use ekubo::types::i129::i129;
use strkfarm_contracts::tests::ekubo::ekubo_utils;
use openzeppelin::token::erc20::interface::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};

// Random number generation (simple implementation)
fn get_random_amount(min: u256, max: u256, seed: u256) -> u256 {
    let range = max - min;
    min + (seed % range)
}

// Helper function to fund an address with tokens
fn fund_address_with_tokens(token_address: ContractAddress, receiver: ContractAddress, amount: u256) {
    let funder = if token_address == constants::STRK_ADDRESS() {
        contract_address_const::<0x076601136372fcdbbd914eea797082f7504f828e122288ad45748b0c8b0c9696>()
    } else if token_address == constants::XSTRK_ADDRESS() {
        contract_address_const::<0x0616350aa9964ba2e5fe60cc5f7f3ec4889473161a28b2202a3f8e4ee36ecab3>()
    } else {
        panic!("Unsupported token for funding")
    };

    start_cheat_caller_address(token_address, funder);
    ERC20Helper::transfer(token_address, receiver, amount);
    stop_cheat_caller_address(token_address);
}

// Function to create pool key for xSTRK/STRK with specific fee
fn get_pool_key_xstrk_strk(fee: u128, tick_spacing: u128) -> PoolKey {
    PoolKey {
        token0: constants::XSTRK_ADDRESS(),
        token1: constants::STRK_ADDRESS(),
        fee: fee.into(),
        tick_spacing: tick_spacing.into(),
        extension: contract_address_const::<0>()
    }
}

// Function to create bounds for a position
fn create_bounds(lower_tick: u128, upper_tick: u128) -> Bounds {
    Bounds {
        lower: i129 { sign: false, mag: lower_tick },
        upper: i129 { sign: false, mag: upper_tick }
    }
}

// Function to add liquidity to Ekubo pool and return position information
fn add_liquidity_to_pool(
    pool_key: PoolKey,
    bounds: Bounds,
    xstrk_amount: u256,
    strk_amount: u256,
    caller: ContractAddress
) -> (u256, u64) {
    // Fund the caller with tokens
    fund_address_with_tokens(constants::XSTRK_ADDRESS(), caller, xstrk_amount);
    fund_address_with_tokens(constants::STRK_ADDRESS(), caller, strk_amount);

    // Manually approve tokens using the dispatcher and cheat caller
    let xstrk_dispatcher = ERC20ABIDispatcher { 
        contract_address: constants::XSTRK_ADDRESS() 
    };
    let strk_dispatcher = ERC20ABIDispatcher { 
        contract_address: constants::STRK_ADDRESS() 
    };

    // Set the caller context and approve tokens for Ekubo positions contract
    start_cheat_caller_address(constants::XSTRK_ADDRESS(), caller);
    xstrk_dispatcher.approve(constants::EKUBO_POSITIONS(), xstrk_amount);
    stop_cheat_caller_address(constants::XSTRK_ADDRESS());

    start_cheat_caller_address(constants::STRK_ADDRESS(), caller);
    strk_dispatcher.approve(constants::EKUBO_POSITIONS(), strk_amount);
    stop_cheat_caller_address(constants::STRK_ADDRESS());

    // Deposit liquidity using ekubo_utils
    let (liquidity_added, nft_id) = ekubo_utils::deposit_liquidity(
        caller,
        xstrk_amount,
        strk_amount,
        caller,
        pool_key,
        bounds,
        0  // 0 means mint new NFT
    );

    println!("Liquidity added to pool:");
    println!("  Pool fee: {:?}", pool_key.fee);
    println!("  Range: {:?} to {:?}", bounds.lower.mag, bounds.upper.mag);
    println!("  xSTRK amount: {:?}", xstrk_amount);
    println!("  STRK amount: {:?}", strk_amount);
    println!("  Liquidity added: {:?}", liquidity_added);
    println!("  NFT ID: {:?}", nft_id);

    (liquidity_added, nft_id)
}

// Function to get position information and log it
fn get_and_log_position_info(nft_id: u64, pool_key: PoolKey, bounds: Bounds) -> GetTokenInfoResult {
    let positions_disp = IEkuboDispatcher { 
        contract_address: constants::EKUBO_POSITIONS() 
    };
    
    let token_info: GetTokenInfoResult = positions_disp.get_token_info(nft_id, pool_key, bounds);
    
    println!("Position Information:");
    println!("  NFT ID: {:?}", nft_id);
    println!("  Pool Price Tick: {:?}, sign: {:?}", token_info.pool_price.tick.mag, token_info.pool_price.tick.sign);
    println!("  Pool price: {:?}", get_price_from_sqrt(token_info.pool_price.sqrt_ratio));
    println!("  Position Liquidity: {:?}", token_info.liquidity);
    println!("  Token0 (xSTRK) Amount: {:?}", token_info.amount0);
    println!("  Token1 (STRK) Amount: {:?}", token_info.amount1);
    println!("  Token0 (xSTRK) Fees: {:?}", token_info.fees0);
    println!("  Token1 (STRK) Fees: {:?}", token_info.fees1);

    return token_info;
}

fn get_price_from_sqrt(sqrt_ratio: u256) -> (u256, u256) {
    // Convert sqrt_ratio to price in 10**16 terms
    let EIGHT_BASE = 100000000_u256;
    println!("sqrt: {:?}", sqrt_ratio);
    // 0x100000000000000000000000000000000 => 2**128
    let price = ((sqrt_ratio * EIGHT_BASE / 0x100000000000000000000000000000000) * (sqrt_ratio * EIGHT_BASE / 0x100000000000000000000000000000000)) / EIGHT_BASE;
    return (price, EIGHT_BASE);
}

fn convert_liquidity(
    inLiquidityInfo: GetTokenInfoResult, 
    outLiquitityInfo: GetTokenInfoResult, 
    poolKeyOut: PoolKey,
    lower_sqrt: u256,
    upper_sqrt: u256
) -> u256 {
    // consider the tokens in inLiquidityInfo to fully utilize them to convert into
    // out liquidity. 
    // approach: t0In, t1In account for liquidityIn
    // t0Out, t1Out account for liquidityOut

    // Step1: to get converted liquidity, we must adjust t0In and t1In to be in the ratio of t0Out/t1Out. 
    // Price is considered as token0_price / token1_price
    // so, multiplying t0In with price gives us the equivalent t1 amount;
    let (price, price_base) = get_price_from_sqrt(inLiquidityInfo.pool_price.sqrt_ratio);
    println!("Price: {:?}, Price Base: {:?}", price, price_base);
    let t0In: u256 = inLiquidityInfo.amount0.into();
    let t1In: u256 = inLiquidityInfo.amount1.into();
    let t0Out: u256 = outLiquitityInfo.amount0.into();
    let t1Out: u256 = outLiquitityInfo.amount1.into();
    let adjusted_t1In = t0In * price / price_base; // Adjust for 18 decimals
    let total_t1In = adjusted_t1In + t1In;
    println!("Adjusted Inputs:");
    println!("  t0In: {:?}, t1In: {:?}", t0In, adjusted_t1In);
    println!("Total t1In: {:?}", total_t1In);
    // Step 2: Divide total t1In as token0 and token 1 to meet the ratio of t0Out/t1Out
    // assuming Y as variable for t1, 
    // (total_t1In - y) / (y * price2) = t0Out / t1Out
    // Rearranging gives us:
    // => total_t1In - y = (t0Out * y * price2) / t1Out
    // => total_t1In * t1Out = y * (t0Out * price2 + t1Out);
    // => y = total_t1In * t1Out / (t0Out * price + t1Out);
    let y = total_t1In * t1Out / (t0Out * price / price_base + t1Out);
    println!("y: {:?}", y);
    
    let newT1Out = y;
    let newT0Out = (total_t1In - y) * price_base / price; // Adjust for 18 decimals
    println!("Converted Outputs: {:?}, {:?}", newT0Out, newT1Out);

    return ekubo_utils::max_liquidity(
        poolKeyOut,
        lower_sqrt,
        upper_sqrt,
        newT0Out,
        newT1Out
    );
}

#[test]
#[fork("mainnet_1531861")]
fn test_multi_pool_liquidity_xstrk_strk() {
    println!("=== Testing Multi-Pool Liquidity for xSTRK/STRK ===");

    let caller = get_contract_address();

    // Pool 1: 0.01% fee, 0.02% tick spacing
    let pool1_fee = 34028236692093847977029636859101184_u128; // 0.01%
    let pool1_tick_spacing = 200_u128;
    let pool1_key = get_pool_key_xstrk_strk(pool1_fee, pool1_tick_spacing);

    // Pool 2: 0.05% fee, 0.1% tick spacing  
    let pool2_fee = 170141183460469235273462165868118016_u128; // 0.05%
    let pool2_tick_spacing = 1000_u128;
    let pool2_key = get_pool_key_xstrk_strk(pool2_fee, pool2_tick_spacing);

    // Random amounts for xSTRK (between 10-500)
    let seed1 = 12345_u256;
    let seed2 = 67890_u256;
    
    let xstrk_amount1 = get_random_amount(10_u256, 500_u256, seed1) * 1000000000000000000_u256; // Convert to 18 decimals
    let xstrk_amount2 = get_random_amount(10_u256, 500_u256, seed2) * 1000000000000000000_u256;

    // Use appropriate STRK amounts (roughly equal value)
    let strk_amount1 = xstrk_amount1; // For simplicity, using same amounts
    let strk_amount2 = xstrk_amount2;

    println!("Pool 1 (0.01% fee) - xSTRK amount: {:?}, STRK amount: {:?}", xstrk_amount1, strk_amount1);
    println!("Pool 2 (0.05% fee) - xSTRK amount: {:?}, STRK amount: {:?}", xstrk_amount2, strk_amount2);

    // Create bounds for positions
    let bounds1 = create_bounds(0, 100000);
    let bounds2 = create_bounds(20000, 50000);

    // Add liquidity to Pool 1
    println!("Adding liquidity to Pool 1 (range: 0-100000)...");
    let (liquidity1, nft_id1) = add_liquidity_to_pool(
        pool1_key,
        bounds1,
        xstrk_amount1,
        strk_amount1,
        caller
    );
    println!("Pool 1 liquidity created: {:?}", liquidity1);

    // Add liquidity to Pool 2
    println!("Adding liquidity to Pool 2 (range: 20000-50000)...");
    let (liquidity2, nft_id2) = add_liquidity_to_pool(
        pool2_key,
        bounds2,
        xstrk_amount2,
        strk_amount2,
        caller
    );
    println!("Pool 2 liquidity created: {:?}", liquidity2);

    // Verify liquidity was created
    assert!(liquidity1 > 0, "Pool 1 liquidity should be greater than 0");
    assert!(liquidity2 > 0, "Pool 2 liquidity should be greater than 0");

    // Query and log position information for both positions
    println!("=== Position 1 Info ===");
    let token_info_1 = get_and_log_position_info(nft_id1, pool1_key, bounds1);

    println!("=== Position 2 Info ===");
    let token_info_2 = get_and_log_position_info(nft_id2, pool2_key, bounds2);

    // convert liquidity of pool2 to pool1 denomination
    println!("=== Convert liquidity ===");
    let lower_sqrt = ekubo_utils::tick_to_sqrt_ratio(bounds1.lower);
    let upper_sqrt = ekubo_utils::tick_to_sqrt_ratio(bounds1.upper);
    let converted_liquidity = convert_liquidity(
        token_info_2,
        token_info_1,
        pool1_key,
        lower_sqrt,
        upper_sqrt
    );
    println!("Converted Liquidity from Pool 2 to Pool 1: {:?}", converted_liquidity);
    let total_liquidity = converted_liquidity + liquidity1;

    // withdraw and add liquidity in different range for pool2
    let new_bounds2 = create_bounds(30000, 70000);
    println!("Withdrawing liquidity from Pool 2 (range: 20000-50000)...");
    let pre_token0_bal = ERC20Helper::balanceOf(constants::XSTRK_ADDRESS(), caller);
    let pre_token1_bal = ERC20Helper::balanceOf(constants::STRK_ADDRESS(), caller);
    let (withdrawn_amount0, withdrawn_amount1) = ekubo_utils::withdraw_liquidity(
        nft_id2,
        pool2_key,
        bounds2,
        liquidity2,
        false
    );
    let post_token0_bal = ERC20Helper::balanceOf(constants::XSTRK_ADDRESS(), caller);
    let post_token1_bal = ERC20Helper::balanceOf(constants::STRK_ADDRESS(), caller);

    let withdrawn_token0 = post_token0_bal - pre_token0_bal;
    let withdrawn_token1 = post_token1_bal - pre_token1_bal;
    println!("Withdrawn xSTRK: {:?}, STRK: {:?}", withdrawn_token0, withdrawn_token1);

    // before we do precise calculations, use 0.1xSTRK and 0.1xSTRK amounts to add liquidity
    let xstrk_amount3 = 100000000000000000_u256; // 0.1 xSTRK
    let strk_amount3 = 100000000000000000_u256; // 0.1 STRK
    println!("Adding liquidity to Pool 2 (range: 30000-70000) with 0.1 xSTRK and STRK...");
    let (liquidity3, nft_id3) = add_liquidity_to_pool(
        pool2_key,
        new_bounds2,
        xstrk_amount3,
        strk_amount3,
        caller
    );
    println!("Pool 2 liquidity created: {:?}", liquidity3);
    assert!(liquidity3 > 0, "Pool 2 liquidity should be greater than 0 after adding new position");
    println!("=== Position 3 Info ===");
    let token_info_3 = get_and_log_position_info(nft_id3, pool2_key, new_bounds2);

    // use withdrawn token0 and token1 to convert them into ratio of token_info_3;
    let (price2, base_price) = get_price_from_sqrt(token_info_3.pool_price.sqrt_ratio);
    println!("Price2: {:?}, Base Price: {:?}", price2, base_price);
    let total_in_token1 = withdrawn_token0 * price2 / base_price + withdrawn_token1;
    println!("Total in token1 (xSTRK): {:?}", total_in_token1);
    // let y = total_t1In * t1Out / (t0Out * price / price_base + t1Out);
    let token_info_3_amount0: u256 = token_info_3.amount0.into();
    let token_info_3_amount1: u256 = token_info_3.amount1.into();
    let y: u256 = total_in_token1 * token_info_3_amount1 / (token_info_3_amount0 * price2 / base_price + token_info_3_amount1);
    let newT1Out = y;
    let newT0Out = (total_in_token1 - y) * base_price / price2; // Adjust for 18 decimals
    println!("Converted Outputs for new position: {:?}, {:?}", newT0Out, newT1Out);
    let (liquidity2_2, nft_id4) = add_liquidity_to_pool(
        pool2_key,
        new_bounds2,
        newT0Out,
        newT1Out,
        caller
    );
    println!("Liquidity for new position: {:?}", liquidity2_2);

    let token_info_3 = get_and_log_position_info(nft_id4, pool2_key, new_bounds2);
    let converted_liquidity2 = convert_liquidity(
        token_info_3,
        token_info_1,
        pool1_key,
        lower_sqrt,
        upper_sqrt
    );
    println!("Converted Liquidity from Pool 2 to Pool 1: {:?}", converted_liquidity2);
}

// Converted Outputs for new position: 88824658220267415546, 185863381270664615143
//   Token1 (STRK) Amount: 279999999999999999999

// #[test]
// #[fork("mainnet_1531861")]
// fn test_different_ranges_same_pool() {
//     println!("=== Testing Different Ranges on Same Pool ===");

//     let caller = get_contract_address();

//     // Use the same pool but different ranges
//     let pool_fee = 34028236692093847977029636859101184_u128; // 0.01%
//     let pool_tick_spacing = 200_u128;
//     let pool_key = get_pool_key_xstrk_strk(pool_fee, pool_tick_spacing);

//     // Different random amounts
//     let seed3 = 11111_u256;
//     let seed4 = 22222_u256;
    
//     let xstrk_amount1 = get_random_amount(50_u256, 200_u256, seed3) * 1000000000000000000_u256;
//     let xstrk_amount2 = get_random_amount(100_u256, 300_u256, seed4) * 1000000000000000000_u256;

//     let strk_amount1 = xstrk_amount1;
//     let strk_amount2 = xstrk_amount2;

//     println!("Position 1 - xSTRK amount: {:?}, STRK amount: {:?}", xstrk_amount1, strk_amount1);
//     println!("Position 2 - xSTRK amount: {:?}, STRK amount: {:?}", xstrk_amount2, strk_amount2);

//     // Two different ranges on the same pool
//     let bounds1 = create_bounds(10000, 80000);
//     let bounds2 = create_bounds(30000, 70000);

//     // Add first position
//     println!("Adding Position 1 (range: 10000-80000)...");
//     let (liquidity1, nft_id1) = add_liquidity_to_pool(
//         pool_key,
//         bounds1,
//         xstrk_amount1,
//         strk_amount1,
//         caller
//     );
//     println!("Position 1 liquidity created: {:?}", liquidity1);

//     // Add second position (overlapping range)
//     println!("Adding Position 2 (range: 30000-70000)...");
//     let (liquidity2, nft_id2) = add_liquidity_to_pool(
//         pool_key,
//         bounds2,
//         xstrk_amount2,
//         strk_amount2,
//         caller
//     );
//     println!("Position 2 liquidity created: {:?}", liquidity2);

//     // Verify both positions were created
//     assert!(liquidity1 > 0, "Position 1 liquidity should be greater than 0");
//     assert!(liquidity2 > 0, "Position 2 liquidity should be greater than 0");

//     // Query and log position information for both positions
//     println!("=== Position 1 Info ===");
//     get_and_log_position_info(nft_id1, pool_key, bounds1);
    
//     println!("=== Position 2 Info ===");
//     get_and_log_position_info(nft_id2, pool_key, bounds2);

//     println!("=== Test completed successfully! ===");
//     println!("Both positions created on same pool with overlapping ranges");
// }
