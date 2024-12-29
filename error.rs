use anchor_lang::prelude::*;

#[error_code]
pub enum PresaleError {
    #[msg("Presale is not active.")]
    PresaleNotActive,
    #[msg("Presale is closed.")]
    PresaleClosed,
    #[msg("User is not whitelisted.")]
    UserNotWhitelisted,
    #[msg("Tier does not exist.")]
    TierDoesNotExist,
    #[msg("Contribution exceeds hard cap.")]
    ExceedsHardCap,
    #[msg("Contribution below minimum limit.")]
    BelowMinContribution,
    #[msg("Contribution above maximum limit.")]
    AboveMaxContribution,
    #[msg("Tier data mismatch.")]
    TierDataMismatch,
    #[msg("Tier already exists.")]
    TierAlreadyExists,
    #[msg("Cannot assign to a non-existent tier.")]
    InvalidTierName,
    #[msg("Number of users and tiers do not match.")]
    MismatchUsersTiers,
    #[msg("User is already whitelisted.")]
    UserAlreadyWhitelisted,
    #[msg("No funds to withdraw.")]
    NoFundsToWithdraw,
    #[msg("Presale must be closed to withdraw funds.")]
    PresaleNotClosed,
    #[msg("Refunds are not allowed.")]
    RefundsNotAllowed,
    #[msg("No contributions to refund.")]
    NoContributionsToRefund,
    #[msg("Already refunded.")]
    AlreadyRefunded,
    #[msg("Invalid minimum contribution.")]
    InvalidMinContribution,
    #[msg("Invalid hard cap.")]
    InvalidHardCap,
    #[msg("Presale is already initialized.")]
    PresaleAlreadyInitialized,
    #[msg("Exceeds maximum number of tiers.")]
    ExceedsMaxTiers,
    #[msg("Exceeds maximum number of users.")]
    ExceedsMaxUsers,
    #[msg("Exceeds maximum bulk assign limit.")]
    ExceedsBulkAssignLimit,
    #[msg("Overflow occurred during calculation.")]
    Overflow,
    #[msg("User's new tier does not accommodate their current contributions.")]
    ExceedsNewTierMaxContribution,
    #[msg("Invalid user USDT account.")]
    InvalidUserUsdtAccount,
    #[msg("Tier name exceeds maximum allowed length.")]
    TierNameTooLong,
    #[msg("Presale is already paused.")]
    PresaleAlreadyPaused,
    #[msg("Presale is not paused.")]
    PresaleNotPaused,
    #[msg("Presale is paused.")]
    PresalePaused,
    #[msg("Contribution too small.")]
    ContributionTooSmall,
    #[msg("Invalid tier name format.")]
    InvalidTierNameFormat,
    #[msg("Hard cap must be greater than or equal to total contributions.")]
    HardCapLessThanTotal,
    #[msg("Arithmetic overflow occurred")]
    Overflow,
    #[msg("Hard cap must be less than tier maximum")]
    HardCapLessThanTierMax,
    #[msg("Invalid maximum contribution")]
    InvalidMaxContribution,
    #[msg("Presale is already closed")]
    PresaleAlreadyClosed,
}

pub fn validate_tier_name(name: &str) -> Result<()> {
    require!(
        name.chars().all(|c| c.is_ascii_alphanumeric() || c == '_'),
        PresaleError::InvalidTierNameFormat
    );
    Ok(())
} 