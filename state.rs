use anchor_lang::prelude::*;
use std::collections::BTreeMap;

#[account]
#[derive(Default)]
pub struct Presale {
    pub is_initialized: bool,
    pub owner: Pubkey,
    pub usdt_mint: Pubkey,
    pub min_contribution: u64,
    pub hard_cap: u64,
    pub total_contributions: u64,
    pub is_active: bool,
    pub is_closed: bool,
    pub refunds_allowed: bool,
    pub paused: bool,
    pub whitelist: BTreeMap<Pubkey, String>,
    pub tiers: BTreeMap<String, u64>,
    pub contributions: BTreeMap<Pubkey, u64>,
    pub refunded: BTreeMap<Pubkey, bool>,
    pub contributors: Vec<Pubkey>,
    pub tier_total_contributions: BTreeMap<String, u64>,
}

impl Presale {
    pub const LEN: usize = 8 +  // Discriminator
        1 + // is_initialized
        32 + // owner
        32 + // usdt_mint
        8 +  // min_contribution
        8 +  // hard_cap
        8 +  // total_contributions
        1 +  // is_active
        1 +  // is_closed
        1 +  // refunds_allowed
        1 +  // paused
        4 +  // whitelist map length
        (MAX_USERS * (32 + MAX_TIER_NAME_LENGTH)) + 
        4 +  // tiers map length
        (MAX_TIERS * (MAX_TIER_NAME_LENGTH + 8)) + 
        4 +  // contributions map length
        (MAX_USERS * (32 + 8)) + 
        4 +  // refunded map length
        (MAX_USERS * (32 + 1)) + 
        4 + (MAX_USERS * 32); // contributors list
} 