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

fn max(a: u256, b: u256) -> u256 {
    let mut max: u256 = 0;
    if (a >= b) {
        max = a;
    } else {
        max = b;
    }
    return max;
}

fn min(a: u256, b: u256) -> u256 {
    let mut min: u256 = 0;
    if (a <= b) {
        min = a;
    } else {
        min = b;
    }
    return min;
}

#[cfg(test)]
mod tests {
    use super::{max, min};

    #[test]
    fn test_max() {
        let a: u256 = 100;
        let b: u256 = 200;
        let ret = max(a, b);
        assert(ret == b, 'invalid max');
    }

    #[test]
    fn test_min() {
        let a: u256 = 100;
        let b: u256 = 200;
        let ret = min(a, b);
        assert(ret == a, 'invalid min');
    }
}
