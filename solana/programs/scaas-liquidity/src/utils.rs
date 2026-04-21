use anchor_lang::prelude::*;
use crate::errors::LiquidityError;

/// Normalizes an amount from source decimals to destination decimals.
/// Uses round-down (floor) strategy to favor the protocol.
///
/// # Rounding Behavior and Dust Retention
///
/// When scaling DOWN (higher decimals → lower decimals), integer division rounds down,
/// truncating precision that cannot be represented in the lower-decimal token. This
/// truncated remainder ("dust") is:
/// - NOT paid out to the user (cannot be represented in lower-decimal token)
/// - NOT sent to the fee recipient
/// - EFFECTIVELY retained by the pool as a tiny implicit spread
///
/// This is expected, protocol-favorable behavior that favors accuracy over user payout
/// in sub-atomic precision ranges.
///
/// # Arguments
/// * `amount` - The amount in source token decimals
/// * `from_decimals` - Source token decimal places
/// * `to_decimals` - Destination token decimal places
///
/// # Returns
/// * `Ok(normalized_amount)` - Amount converted to destination decimals (rounded down)
/// * `Err(DecimalNormalizationOverflow)` - If calculation would overflow
///
/// # Examples
/// ```
/// // Converting from 9 decimals to 6 decimals (scales down, creates dust)
/// let amount = 100_000_000_123; // 100.000000123 tokens (9 decimals)
/// let normalized = normalize_decimals(amount, 9, 6)?;
/// // Result: 100_000_000 (100.000000 tokens in 6 decimals)
/// // Dust: 123 units (0.000000123 in 9-decimal terms) retained by pool
///
/// // Converting from 6 decimals to 9 decimals (scales up, no dust)
/// let amount = 100_000_000; // 100.000000 tokens (6 decimals)
/// let normalized = normalize_decimals(amount, 6, 9)?;
/// // Result: 100_000_000_000 (100.000000000 tokens in 9 decimals, exact)
/// ```
pub fn normalize_decimals(amount: u64, from_decimals: u8, to_decimals: u8) -> Result<u64> {
    if from_decimals == to_decimals {
        // No conversion needed
        return Ok(amount);
    }

    if from_decimals < to_decimals {
        // Scaling up (e.g., 6 decimals -> 9 decimals)
        // Multiply by 10^(to_decimals - from_decimals)
        let decimal_diff = to_decimals - from_decimals;
        let multiplier = 10u64.checked_pow(decimal_diff as u32)
            .ok_or(LiquidityError::DecimalNormalizationOverflow)?;

        amount.checked_mul(multiplier)
            .ok_or(LiquidityError::DecimalNormalizationOverflow.into())
    } else {
        // Scaling down (e.g., 9 decimals -> 6 decimals)
        // Divide by 10^(from_decimals - to_decimals)
        // Division automatically rounds down (floor)
        let decimal_diff = from_decimals - to_decimals;
        let divisor = 10u64.checked_pow(decimal_diff as u32)
            .ok_or(LiquidityError::DecimalNormalizationOverflow)?;

        Ok(amount / divisor) // Integer division rounds down
    }
}
