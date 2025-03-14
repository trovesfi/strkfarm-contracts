use super::{pow};
use starknet::{ContractAddress};

// These two consts MUST be the same.
pub const SCALE_U256: u256 = 1000000000000000000000000000; // 10**27

fn mul_scale(a: u256, b: u256, scale: u256) -> u256 {
    a * b / scale
}

fn div_scale(a: u256, b: u256, scale: u256) -> u256 {
    (a * scale) / b
}

/// This function assumes `b` is scaled by `SCALE`
pub fn mul(a: u256, b: u256) -> u256 {
    mul_scale(a, b, SCALE_U256)
}

/// This function assumes `b` is scaled by `SCALE`
pub fn div(a: u256, b: u256) -> u256 {
    div_scale(a, b, SCALE_U256)
}

// rounds down
pub fn div_round_down(a: u256, b: u256) -> u256 {
    a / b
}

/// This function assumes `b` is scaled by `10 ^ b_decimals`
pub fn mul_decimals(a: u256, b: u256, b_decimals: u8) -> u256 {
    // `ten_pow` already handles overflow anyways
    let scale = pow::ten_pow(b_decimals.into());
    mul_scale(a, b, scale)
}

/// This function assumes `b` is scaled by `10 ^ b_decimals`
pub fn div_decimals(a: u256, b: u256, b_decimals: u8) -> u256 {
    // `ten_pow` already handles overflow anyways
    let scale = pow::ten_pow(b_decimals.into());
    div_scale(a, b, scale)
}

pub fn normalise(a: u256, actual_decimals: u8, required_decimals: u8) -> u256 {
    if actual_decimals == required_decimals {
        return a;
    }

    if (actual_decimals > required_decimals) {
        return mul_decimals(a, 1, actual_decimals - required_decimals);
    }

    div_decimals(a, 1, required_decimals - actual_decimals)
}

pub fn address_to_felt252(addr: ContractAddress) -> felt252 {
    addr.try_into().unwrap()
}

fn u256_to_address(token_id: u256) -> ContractAddress {
    let token_id_felt: felt252 = token_id.try_into().unwrap();
    token_id_felt.try_into().unwrap()
}

pub fn non_negative_sub(a: u256, b: u256) -> u256 {
    if a < b {
        return 0;
    }
    a - b
}

pub fn is_under_by_percent_bps(value: u256, base: u256, percent_bps: u256) -> bool {
    if (base == 0) {
        return value == 0;
    }
    let factor = value * 10000 / base;
    return factor <= percent_bps;
}

// converts absolute amount to wei amount
pub fn fei_to_wei(etherAmount: u256, decimals: u8) -> u256 {
    etherAmount * pow::ten_pow(decimals.into())
}

#[cfg(test)]
mod tests {
    #[test]
    fn test_mul() {
        assert_eq!(@super::mul(10, 2000000000000000000000000000), @20, "FAILED");
    }

    #[test]
    fn test_mul_decimals() {
        assert_eq!(@super::mul_decimals(10, 2000000000000000000000000000, 27), @20, "FAILED");
    }

    #[test]
    #[should_panic(expected: ('u256_mul Overflow',))]
    fn test_mul_overflow() {
        super::mul(
            0x400000000000000000000000000000000000000000000000000000000000000,
            2000000000000000000000000000
        );
    }

    #[test]
    #[should_panic(expected: ('u256_mul Overflow',))]
    fn test_mul_decimals_overflow() {
        super::mul_decimals(
            0x400000000000000000000000000000000000000000000000000000000000000,
            2000000000000000000000000000,
            27
        );
    }

    #[test]
    fn test_div() {
        assert_eq!(@super::div(10, 2000000000000000000000000000), @5, "FAILED");
    }

    #[test]
    fn test_div_decimals() {
        assert_eq!(@super::div_decimals(10, 2000000000000000000000000000, 27), @5, "FAILED");
    }
}
