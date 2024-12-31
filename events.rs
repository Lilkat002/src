use anchor_lang::prelude::*;

#[event]
pub struct Contribution {
    pub contributor: Pubkey,
    pub amount: u64,
    pub timestamp: u64,
}

#[event]
pub struct UserLimitSet {
    pub user: Pubkey,
    pub max_contribution: u64,
    pub timestamp: u64,
}

#[event]
pub struct PresaleClosed {
    pub timestamp: u64,
    pub refunds_allowed: bool,
}

#[event]
pub struct FundsWithdrawn {
    pub amount: u64,
    pub timestamp: u64,
}

#[event]
pub struct Refund {
    pub contributor: Pubkey,
    pub amount: u64,
    pub timestamp: u64,
}

#[event]
pub struct UserRemoved {
    pub user: Pubkey,
    pub timestamp: u64,
}

#[event]
pub struct MinContributionUpdated {
    pub new_min_contribution: u64,
    pub timestamp: u64,
}

#[event]
pub struct HardCapUpdated {
    pub new_hard_cap: u64,
    pub timestamp: u64,
}

#[event]
pub struct PresalePaused {
    pub timestamp: u64,
}

#[event]
pub struct PresaleUnpaused {
    pub timestamp: u64,
} 
