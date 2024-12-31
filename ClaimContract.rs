use anchor_lang::prelude::*;
use anchor_spl::token::{self, Token, TokenAccount, Transfer};

#[account]
#[derive(Default)]
pub struct DistributionState {
    pub owner: Pubkey,
    pub token_mint: Pubkey,
    pub total_raised: u64,
    pub allocation_calculated: bool,
    pub claim_enabled: bool,
    pub max_batch_size: u64,
    pub claim_period_open: bool,
    pub paused: bool,
    pub contributors: Vec<Contributor>,
}

#[derive(AnchorSerialize, AnchorDeserialize, Clone, Default)]
pub struct Contributor {
    pub user: Pubkey,
    pub contribution: u64,
    pub allocation: u64,
}

#[derive(Accounts)]
pub struct InitializeDistribution<'info> {
    #[account(mut)]
    pub payer: Signer<'info>,

    #[account(
        init,
        payer = payer,
        space = 8 + 32 + 32 + 8 + 1 + 1 + 8 + 1 + 1 + 4 + (2000 * (32 + 8 + 8))
    )]
    pub distribution_state: Account<'info, DistributionState>,

    pub system_program: Program<'info, System>,
}

#[program]
mod secure_distribution {
    use super::*;

    pub fn initialize_distribution(
        ctx: Context<InitializeDistribution>,
        owner: Pubkey,
        max_batch_size: u64,
    ) -> Result<()> {
        require!(max_batch_size > 0, DistributionError::InvalidBatchSize);

        let state = &mut ctx.accounts.distribution_state;
        state.owner = owner;
        state.token_mint = Pubkey::default();
        state.total_raised = 0;
        state.allocation_calculated = false;
        state.claim_enabled = false;
        state.max_batch_size = max_batch_size;
        state.claim_period_open = false;
        state.paused = false;
        state.contributors = vec![];
        
        emit!(DistributionEvent::Initialized { owner, max_batch_size });
        Ok(())
    }

    pub fn set_token(ctx: Context<SetToken>, token_mint: Pubkey) -> Result<()> {
        let state = &mut ctx.accounts.distribution_state;
        require_keys_eq!(state.owner, ctx.accounts.authority.key(), DistributionError::NotOwner);
        require!(!state.paused, DistributionError::ContractPaused);
        require!(!state.claim_period_open, DistributionError::ClaimPeriodActive);
        require!(!state.allocation_calculated, DistributionError::AllocationAlreadyCalculated);

        require!(token_mint != Pubkey::default(), DistributionError::InvalidTokenMint);
        state.token_mint = token_mint;
        emit!(DistributionEvent::TokenUpdated { token_mint });
        Ok(())
    }

    pub fn batch_set_contributions(
        ctx: Context<BatchSetContributions>,
        users: Vec<Pubkey>,
        amounts: Vec<u64>,
    ) -> Result<()> {
        let state = &mut ctx.accounts.distribution_state;
        require_keys_eq!(state.owner, ctx.accounts.authority.key(), DistributionError::NotOwner);
        require!(!state.paused, DistributionError::ContractPaused);
        require!(!state.allocation_calculated, DistributionError::AllocationAlreadyCalculated);
        require_eq!(users.len(), amounts.len(), DistributionError::ArrayLengthMismatch);
        require!(users.len() as u64 <= state.max_batch_size, DistributionError::BatchTooLarge);

        let mut seen_users = std::collections::HashSet::new();
        for (i, user) in users.iter().enumerate() {
            require!(seen_users.insert(user), DistributionError::DuplicateContributor);
            let amount = amounts[i];
            require!(amount > 0, DistributionError::InvalidAmount);

            if let Some(contributor) = state.contributors.iter_mut().find(|c| c.user == *user) {
                state.total_raised = state.total_raised - contributor.contribution + amount;
                contributor.contribution = amount;
            } else {
                state.contributors.push(Contributor {
                    user: *user,
                    contribution: amount,
                    allocation: 0,
                });
                state.total_raised += amount;
            }
        }

        emit!(DistributionEvent::ContributionsUpdated);
        Ok(())
    }

    pub fn calculate_allocations(ctx: Context<CalculateAllocations>) -> Result<()> {
        let state = &mut ctx.accounts.distribution_state;
        require_keys_eq!(state.owner, ctx.accounts.authority.key(), DistributionError::NotOwner);
        require!(!state.paused, DistributionError::ContractPaused);
        require!(state.token_mint != Pubkey::default(), DistributionError::InvalidTokenMint);
        require!(state.total_raised > 0, DistributionError::NoContributions);
        require!(!state.allocation_calculated, DistributionError::AllocationAlreadyCalculated);

        let token_account = &ctx.accounts.token_account;
        let total_tokens = token_account.amount;
        require!(total_tokens > 0, DistributionError::NoTokenBalance);

        let mut allocated_amount: u64 = 0;
        for contributor in state.contributors.iter_mut() {
            if contributor.contribution > 0 {
                let allocation = contributor
                    .contribution
                    .checked_mul(total_tokens)
                    .ok_or(DistributionError::Overflow)?
                    / state.total_raised;
                contributor.allocation = allocation;
                allocated_amount = allocated_amount
                    .checked_add(allocation)
                    .ok_or(DistributionError::Overflow)?;
            }
        }

        require!(allocated_amount <= total_tokens, DistributionError::AllocationExceedsBalance);

        state.allocation_calculated = true;
        emit!(DistributionEvent::AllocationsCalculated { total_raised: state.total_raised });
        Ok(())
    }

    pub fn claim(ctx: Context<Claim>) -> Result<()> {
        let state = &mut ctx.accounts.distribution_state;
        require!(!state.paused, DistributionError::ContractPaused);
        require!(state.claim_enabled, DistributionError::ClaimingNotEnabled);
        require!(state.claim_period_open, DistributionError::ClaimPeriodClosed);

        let authority_key = ctx.accounts.authority.key();
        let contributor = state
            .contributors
            .iter_mut()
            .find(|c| c.user == authority_key)
            .ok_or(DistributionError::NotContributor)?;
        
        let claim_amount = contributor.allocation;
        require!(claim_amount > 0, DistributionError::NothingToClaim);
        contributor.allocation = 0; // Reset before transferring

        let transfer_cpi_ctx = CpiContext::new(
            ctx.accounts.token_program.to_account_info(),
            Transfer {
                from: ctx.accounts.from.to_account_info(),
                to: ctx.accounts.to.to_account_info(),
                authority: ctx.accounts.from.to_account_info(),
            },
        );

        token::transfer(transfer_cpi_ctx, claim_amount)?;
        emit!(DistributionEvent::Claimed { user: authority_key, amount: claim_amount });
        Ok(())
    }
}
