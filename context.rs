use anchor_lang::prelude::*;
use anchor_spl::token::{Token, TokenAccount, Mint};
use crate::state::*;

#[derive(Accounts)]
#[instruction(
    tier_names: Vec<String>,
    tier_max_contributions: Vec<u64>,
    min_contribution: u64,
    hard_cap: u64,
)]
pub struct Initialize<'info> {
    #[account(
        init,
        payer = owner,
        space = 8 + Presale::LEN,
        seeds = [b"presale", owner.key().as_ref()],
        bump
    )]
    pub presale: Account<'info, Presale>,
    #[account(mut)]
    pub owner: Signer<'info>,
    pub usdt_mint: Account<'info, Mint>,
    pub system_program: Program<'info, System>,
    pub token_program: Program<'info, Token>,
}

#[derive(Accounts)]
pub struct CreateTier<'info> {
    #[account(
        mut,
        has_one = owner,
        seeds = [b"presale", owner.key().as_ref()],
        bump
    )]
    pub presale: Account<'info, Presale>,
    pub owner: Signer<'info>,
}

#[derive(Accounts)]
pub struct AssignTier<'info> {
    #[account(
        mut,
        has_one = owner,
        seeds = [b"presale", owner.key().as_ref()],
        bump
    )]
    pub presale: Account<'info, Presale>,
    pub owner: Signer<'info>,
}

#[derive(Accounts)]
pub struct BulkAssignTiers<'info> {
    #[account(
        mut,
        has_one = owner,
        seeds = [b"presale", owner.key().as_ref()],
        bump
    )]
    pub presale: Account<'info, Presale>,
    pub owner: Signer<'info>,
}

#[derive(Accounts)]
pub struct RemoveUser<'info> {
    #[account(
        mut,
        has_one = owner,
        seeds = [b"presale", owner.key().as_ref()],
        bump
    )]
    pub presale: Account<'info, Presale>,
    pub owner: Signer<'info>,
}

#[derive(Accounts)]
pub struct UpdateUserTier<'info> {
    #[account(
        mut,
        has_one = owner,
        seeds = [b"presale", owner.key().as_ref()],
        bump
    )]
    pub presale: Account<'info, Presale>,
    pub owner: Signer<'info>,
}

#[derive(Accounts)]
pub struct Contribute<'info> {
    #[account(mut, seeds = [b"presale", owner.key().as_ref()], bump)]
    pub presale: Account<'info, Presale>,
    pub owner: UncheckedAccount<'info>,
    pub user: Signer<'info>,
    #[account(mut, constraint = user_usdt.mint == presale.usdt_mint)]
    pub user_usdt: Account<'info, TokenAccount>,
    #[account(mut, constraint = presale_usdt.owner == presale.key(), constraint = presale_usdt.mint == presale.usdt_mint)]
    pub presale_usdt: Account<'info, TokenAccount>,
    pub token_program: Program<'info, Token>,
}

#[derive(Accounts)]
pub struct ClosePresale<'info> {
    #[account(
        mut,
        has_one = owner,
        seeds = [b"presale", owner.key().as_ref()],
        bump
    )]
    pub presale: Account<'info, Presale>,
    pub owner: Signer<'info>,
}

#[derive(Accounts)]
pub struct WithdrawFunds<'info> {
    #[account(
        mut,
        has_one = owner,
        seeds = [b"presale", owner.key().as_ref()],
        bump
    )]
    pub presale: Account<'info, Presale>,
    #[account(mut, constraint = presale_usdt.owner == presale.key(), constraint = presale_usdt.mint == presale.usdt_mint)]
    pub presale_usdt: Account<'info, TokenAccount>,
    #[account(mut, constraint = owner_usdt.mint == presale.usdt_mint)]
    pub owner_usdt: Account<'info, TokenAccount>,
    pub owner: Signer<'info>,
    pub token_program: Program<'info, Token>,
}

#[derive(Accounts)]
pub struct Refund<'info> {
    #[account(
        mut,
        has_one = owner,
        seeds = [b"presale", owner.key().as_ref()],
        bump
    )]
    pub presale: Account<'info, Presale>,
    pub owner: UncheckedAccount<'info>,
    pub user: Signer<'info>,
    #[account(mut, constraint = presale_usdt.owner == presale.key(), constraint = presale_usdt.mint == presale.usdt_mint)]
    pub presale_usdt: Account<'info, TokenAccount>,
    #[account(mut, constraint = user_usdt.mint == presale.usdt_mint)]
    pub user_usdt: Account<'info, TokenAccount>,
    pub token_program: Program<'info, Token>,
}

#[derive(Accounts)]
pub struct UpdatePresale<'info> {
    #[account(
        mut,
        has_one = owner,
        seeds = [b"presale", owner.key().as_ref()],
        bump
    )]
    pub presale: Account<'info, Presale>,
    pub owner: Signer<'info>,
}

#[derive(Accounts)]
pub struct PausePresale<'info> {
    #[account(
        mut,
        has_one = owner,
        seeds = [b"presale", owner.key().as_ref()],
        bump
    )]
    pub presale: Account<'info, Presale>,
    pub owner: Signer<'info>,
}

#[derive(Accounts)]
pub struct UnpausePresale<'info> {
    #[account(
        mut,
        has_one = owner,
        seeds = [b"presale", owner.key().as_ref()],
        bump
    )]
    pub presale: Account<'info, Presale>,
    pub owner: Signer<'info>,
} 