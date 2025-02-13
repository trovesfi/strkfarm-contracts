use ekubo::interfaces::mathlib::{dispatcher, IMathLibDispatcher, IMathLibDispatcherTrait};
use ekubo::types::i129::i129;
use strkfarm_contracts::helpers::pow;
use core::integer::u512_safe_div_rem_by_u256;
use core::num::traits::WideMul;
use core::traits::{Into};

#[derive(Drop, Copy, Debug)]
pub enum Rounding {
  Floor, // Toward negative infinity
  Ceil, // Toward positive infinity
  Trunc, // Toward zero
  Expand // Away from zero
}

fn cast_rounding(rounding: Rounding) -> u8 {
  match rounding {
      Rounding::Floor => 0,
      Rounding::Ceil => 1,
      Rounding::Trunc => 2,
      Rounding::Expand => 3
  }
}

pub fn power<T, +Drop<T>, +PartialEq<T>, +TryInto<u256, T>, +Into<T, u256>, +Into<u8, T>>(
  base: T, exp: T
) -> T {
  assert!(base != 0_u8.into(), "Math: base cannot be zero");
  let base: u256 = base.into();
  let exp: u256 = exp.into();
  let mut result: u256 = 1;

  for _ in 0..exp {
      result *= base;
  };

  result.try_into().unwrap()
}

fn round_up(rounding: Rounding) -> bool {
  let u8_rounding = cast_rounding(rounding);
  u8_rounding % 2 == 1
}

pub fn u256_mul_div(x: u256, y: u256, denominator: u256, rounding: Rounding) -> u256 {
  let (q, r) = _raw_u256_mul_div(x, y, denominator);

  // Cast to felts for bitwise op
  let is_rounded_up: felt252 = round_up(rounding).into();
  let has_remainder: felt252 = (r > 0).into();

  q + (is_rounded_up.into() & has_remainder.into())
}

fn _raw_u256_mul_div(x: u256, y: u256, denominator: u256) -> (u256, u256) {
  assert(denominator != 0, 'Math: division by zero');
  let p = x.wide_mul(y);
  let (mut q, r) = u512_safe_div_rem_by_u256(p, denominator.try_into().unwrap());
  let q = q.try_into().expect('Math: quotient > u256');
  (q, r)
}

pub fn calculateXandY(liquidity: u256, tickA: u256, tickB: u256, tickCurrent: u256) -> (u256, u256) {
  let newTickCurrent: u256 = max(min(tickCurrent, tickB), tickA);
  println!("test1");
  let x: u256 = (liquidity * (tickB - newTickCurrent)) / newTickCurrent;
  let x_pass = x / tickB;
  println!("test2");
  let y: u256 = liquidity * (newTickCurrent - tickA);
  println!("test3");

  return(x_pass, y);
} 

pub fn calcEkuboXandY(liquidity: u128, sqa: u256, sqb: u256, sqc: u256) -> (u128, u128) {
  let ekubo_disp = dispatcher();
  let liq_delta = i129 {
    mag: liquidity,
    sign: false // @audit Why true?
  };

  let tok_amounts = ekubo_disp
  .liquidity_delta_to_amount_delta(
    sqc,
    liq_delta,
    sqa,
    sqb
  );  

  // println!("token A: {:?}", tok_amounts.amount0.mag);
  // println!("token B: {:?}", tok_amounts.amount1.mag);

  return (tok_amounts.amount0.mag, tok_amounts.amount1.mag);
}

pub fn getRatio(sqrt_lower: u256, sqrt_upper: u256, sqrt_current: u256) -> (u256, u256) {
  let liquidity1: u128 = (10 * pow::ten_pow(28)).try_into().unwrap();
  
  let (token1, token2) = calcEkuboXandY(liquidity1, sqrt_lower, sqrt_upper, sqrt_current); 
  let token1_u256: u256 = token1.into(); 
  let token2_u256: u256 = token2.into(); 
  let pow_const = pow::ten_pow(18); // @audit Why 7? 7 is a non-standard multiplier IMO (may be 18?)
  let ratio1 = (token1_u256 * pow_const) / token2_u256;

  (ratio1, pow_const)
}

pub fn calculateFeesXandY(
  x: u256, 
  y: u256, 
  sqrtA: u128,
  sqrtB: u128, 
  sqrtCurrent: u128, 
  priceA: u256, 
  priceB: u256
) -> (u256, u256) {
  let sqrtA_u256: u256 = sqrtA.into();
  let sqrtB_u256: u256 = sqrtB.into();
  let sqrtCurrent_u256: u256 = sqrtCurrent.into();

  let din_x = priceA + ((( sqrtB_u256 * sqrtCurrent_u256) * (sqrtCurrent_u256 - sqrtA_u256) * priceB ) / ( sqrtB_u256 - sqrtCurrent_u256 ));
  let x1 = (( x * priceA ) + ( y * priceB )) / din_x;

  let din_y = priceB + (((sqrtB_u256 - sqrtCurrent_u256) * priceA ) / (sqrtCurrent_u256 * sqrtB_u256) * (sqrtCurrent_u256 - sqrtA_u256 ));
  let y1 = (( x * priceA ) + ( y * priceB )) / din_y;

  return(x1, y1);
}

fn max(a: u256, b: u256) -> u256 {
  let mut max: u256 = 0;
  if(a >= b) {
    max = a;
  } else {
    max = b;
  }
  return max;
}

fn min(a: u256, b: u256) -> u256 {
  let mut min: u256 = 0;
  if(a <= b) {
    min = a;
  } else {
    min = b;
  }
  return min;
}

#[cfg(test)]
mod tests {
    use starknet::{
        ContractAddress, get_contract_address, get_block_timestamp,
        contract_address::contract_address_const
    };
    use strkfarm_contracts::helpers::pow;
    use core::num::traits::Zero;
    use strkfarm_contracts::helpers::constants;
    use strkfarm_contracts::helpers::ERC20Helper;
    use super::{calculateXandY, max , min, calcEkuboXandY, getRatio};

    #[test]
    fn test_x_y_calc() {
      let lower_mag: u256 = 370471204618336304916847084198533763812;
      let upper_mag: u256 = 372328198328473278775782393609035295332;
      let curr_mag: u256 = 371046065479383041693243879021795550736;
      let liquidity: u256 = 1000000000000000;  
      let calc_amount = calculateXandY(liquidity, lower_mag, upper_mag, curr_mag);
      println!("amount: {:?}", calc_amount);
    }

    // #[test]
    // #[fork("mainnet_latest")]
    // fn test_ekubo_x_and_y() {
    //   let liquidity: u128 = 99209107691145427163307;
    //   let sqc: u256 = 368343793771586852276447761125701844992;
    //   let sqa: u256 = 368328691993182910673180535464776433664;
    //   let sqb: u256 = 368336058637005041313369477979394015232;
    //   let (token1, token2) = calcEkuboXandY(
    //     liquidity,
    //     sqa,
    //     sqb,
    //     sqc
    //   );

    //   let pow_128: u128 = pow::ten_pow(14).try_into().unwrap();
    //   let check_token_2 = token2 / pow_128;

    //   assert(token1 == 0, 'math::ekubo::invalid token1');
    //   assert(check_token_2 == 21477, 'math::ekubo::invalid token1');
    // }

    // #[test]
    // #[fork("mainnet_latest")]
    // fn test_fees_math() {
    //   let liquidity1: u128 = (10 * pow::ten_pow(28)).try_into().unwrap();
    //   let liquidity2: u128 = (10 * pow::ten_pow(12)).try_into().unwrap();
    //   let sqc: u256 = 368329793771586852276447761125701844992;
    //   let sqa: u256 = 368328691993182910673180535464776433664;
    //   let sqb: u256 = 368336058637005041313369477979394015232;

    //   let (token1, token2) = calcEkuboXandY(liquidity1, sqa, sqb, sqc); 
    //   let token1_u256: u256 = token1.into(); 
    //   let token2_u256: u256 = token2.into(); 
    //   let pow_const = pow::ten_pow(7);
    //   let ratio1 = (token1_u256 * pow_const) / token2_u256;
    //   println!("ratio1: {:?}", ratio1);
      
    //   let (token11, token21) = calcEkuboXandY(liquidity2, sqa, sqb, sqc);
    //   let token11_u256: u256 = token11.into(); 
    //   let token21_u256: u256 = token21.into(); 
    //   let ratio2 = (token11_u256 * pow_const ) / token21_u256;
    //   println!("ratio2: {:?}", ratio2);

    //   assert(ratio1 == ratio2, 'invalid liquidity ratio');
    // }

    // #[test]
    // #[fork("mainnet_latest")]
    // fn test_ratio() {
    //   let ratio = getRatio();
    //   println!("ratio: {:?}", ratio);
    // }

    // #[test]
    // fn test_max() {
    //   let a: u128 = 100;
    //   let b: u128 = 200;
    //   let ret = max(a,b);
    //   assert(ret == b, 'invalid max');
    // }

    // #[test]
    // fn test_min() {
    //   let a: u128 = 100;
    //   let b: u128 = 200;
    //   let ret = min(a,b);
    //   assert(ret == a, 'invalid min');
    // }
}