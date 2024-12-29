use anchor_lang::prelude::*;
use anchor_spl::token;
use crate::{state::*, error::*, events::*, context::*};

#[program]
pub mod presale {
    use super::*;

    pub fn initialize(
        ctx: Context<Initialize>,
        tier_names: Vec<String>,
        tier_max_contributions: Vec<u64>,
        min_contribution: u64,
        hard_cap: u64,
    ) -> Result<()> {
        let presale = &mut ctx.accounts.presale;

        require!(
            !presale.is_initialized,
            PresaleError::PresaleAlreadyInitialized
        );

        require!(
            min_contribution > 0,
            PresaleError::InvalidMinContribution
        );
        require!(hard_cap > 0, PresaleError::InvalidHardCap);

        require!(
            tier_names.len() <= MAX_TIERS,
            PresaleError::ExceedsMaxTiers
        );

        require!(
            tier_names.len() == tier_max_contributions.len(),
            PresaleError::TierDataMismatch
        );

        let sum_tier_max: u64 = tier_max_contributions.iter().sum();
        require!(
            hard_cap >= sum_tier_max,
            PresaleError::HardCapLessThanTierMax
        );

        presale.owner = ctx.accounts.owner.key();
        presale.usdt_mint = ctx.accounts.usdt_mint.key();
        presale.min_contribution = min_contribution;
        presale.hard_cap = hard_cap;
        presale.total_contributions = 0;
        presale.is_active = true;
        presale.is_closed = false;
        presale.refunds_allowed = false;
        presale.paused = false;
        presale.is_initialized = true;

        for (i, tier_name) in tier_names.iter().enumerate() {
            let max_contribution = tier_max_contributions[i];

            require!(
                tier_name.len() <= MAX_TIER_NAME_LENGTH,
                PresaleError::TierNameTooLong
            );

            let normalized_tier = tier_name.trim().to_lowercase();

            require!(
                !presale.tiers.contains_key(&normalized_tier),
                PresaleError::TierAlreadyExists
            );

            require!(
                max_contribution > 0,
                PresaleError::InvalidMaxContribution
            );

            presale.tiers.insert(normalized_tier.clone(), max_contribution);
        }

        Ok(())
    }

    pub fn create_tier(
        ctx: Context<CreateTier>,
        tier_name: String,
        max_contribution: u64,
    ) -> Result<()> {
        validate_tier_name(&tier_name)?;
        let presale = &mut ctx.accounts.presale;

        require!(
            presale.tiers.len() < MAX_TIERS,
            PresaleError::ExceedsMaxTiers
        );

        require!(
            tier_name.len() <= MAX_TIER_NAME_LENGTH,
            PresaleError::TierNameTooLong
        );

        require!(
            max_contribution > 0,
            PresaleError::InvalidMaxContribution
        );

        let normalized_tier = tier_name.trim().to_lowercase();

        require!(
            !presale.tiers.contains_key(&normalized_tier),
            PresaleError::TierAlreadyExists
        );

        presale.tiers.insert(normalized_tier.clone(), max_contribution);

        emit!(UserLimitSet {
            user: ctx.accounts.owner.key(),
            max_contribution,
            timestamp: Clock::get()?.unix_timestamp as u64,
        });

        Ok(())
    }

    pub fn assign_tier(
        ctx: Context<AssignTier>,
        user: Pubkey,
        tier_name: String,
    ) -> Result<()> {
        let presale = &mut ctx.accounts.presale;

        require!(
            tier_name.len() <= MAX_TIER_NAME_LENGTH,
            PresaleError::TierNameTooLong
        );

        let normalized_tier = tier_name.trim().to_lowercase();

        require!(
            presale.tiers.contains_key(&normalized_tier),
            PresaleError::TierDoesNotExist
        );

        require!(
            !presale.whitelist.contains_key(&user),
            PresaleError::UserAlreadyWhitelisted
        );

        require!(
            presale.whitelist.len() < MAX_USERS,
            PresaleError::ExceedsMaxUsers
        );

        let max_contribution = presale.tiers.get(&normalized_tier).unwrap();
        presale.whitelist.insert(user, normalized_tier);

        emit!(UserLimitSet {
            user,
            max_contribution: *max_contribution,
            timestamp: Clock::get()?.unix_timestamp as u64,
        });

        Ok(())
    }

    pub fn bulk_assign_tiers(
        ctx: Context<BulkAssignTiers>,
        users: Vec<Pubkey>,
        tiers: Vec<String>,
    ) -> Result<()> {
        let presale = &mut ctx.accounts.presale;

        require!(
            users.len() == tiers.len(),
            PresaleError::MismatchUsersTiers
        );

        require!(
            users.len() <= MAX_BULK_ASSIGN,
            PresaleError::ExceedsBulkAssignLimit
        );

        require!(
            presale.whitelist.len() + users.len() <= MAX_USERS,
            PresaleError::ExceedsMaxUsers
        );

        for (tier_name, user) in tiers.iter().zip(users.iter()) {
            require!(
                tier_name.len() <= MAX_TIER_NAME_LENGTH,
                PresaleError::TierNameTooLong
            );

            let normalized_tier = tier_name.trim().to_lowercase();

            require!(
                presale.tiers.contains_key(&normalized_tier),
                PresaleError::TierDoesNotExist
            );

            require!(
                !presale.whitelist.contains_key(user),
                PresaleError::UserAlreadyWhitelisted
            );
        }

        for (user, tier) in users.iter().zip(tiers.iter()) {
            let normalized_tier = tier.trim().to_lowercase();
            let max_contribution = *presale.tiers.get(&normalized_tier).unwrap();
            
            presale.whitelist.insert(*user, normalized_tier);

            emit!(UserLimitSet {
                user: *user,
                max_contribution,
                timestamp: Clock::get()?.unix_timestamp as u64,
            });
        }

        Ok(())
    }

    pub fn remove_user_from_whitelist(
        ctx: Context<RemoveUser>,
        user: Pubkey,
    ) -> Result<()> {
        let presale = &mut ctx.accounts.presale;

        require!(
            presale.whitelist.contains_key(&user),
            PresaleError::UserNotWhitelisted
        );

        presale.whitelist.remove(&user);

        emit!(UserRemoved {
            user,
            timestamp: Clock::get()?.unix_timestamp as u64,
        });

        Ok(())
    }

    pub fn update_user_tier(
        ctx: Context<UpdateUserTier>,
        user: Pubkey,
        new_tier: String,
    ) -> Result<()> {
        let presale = &mut ctx.accounts.presale;

        require!(
            new_tier.len() <= MAX_TIER_NAME_LENGTH,
            PresaleError::TierNameTooLong
        );

        let normalized_tier = new_tier.trim().to_lowercase();

        require!(
            presale.tiers.contains_key(&normalized_tier),
            PresaleError::TierDoesNotExist
        );

        require!(
            presale.whitelist.contains_key(&user),
            PresaleError::UserNotWhitelisted
        );

        let current_tier = presale.whitelist.get(&user).ok_or(PresaleError::UserNotWhitelisted)?;
        
        if current_tier == &normalized_tier {
            return Ok(());
        }

        let user_contribution = presale.contributions.get(&user).copied().unwrap_or(0);
        let new_tier_max = presale.tiers.get(&normalized_tier).ok_or(PresaleError::TierDoesNotExist)?;

        require!(
            user_contribution <= *new_tier_max,
            PresaleError::ExceedsNewTierMaxContribution
        );

        if user_contribution > 0 {
            if let Some(old_tier_total) = presale.tier_total_contributions.get_mut(current_tier) {
                *old_tier_total = old_tier_total.checked_sub(user_contribution).ok_or(PresaleError::Overflow)?;
            }
            
            let new_tier_total = presale.tier_total_contributions
                .entry(normalized_tier.clone())
                .or_insert(0);
            *new_tier_total = new_tier_total.checked_add(user_contribution).ok_or(PresaleError::Overflow)?;
        }

        presale.whitelist.insert(user, normalized_tier.clone());

        emit!(UserLimitSet {
            user,
            max_contribution: *new_tier_max,
            timestamp: Clock::get()?.unix_timestamp as u64,
        });

        Ok(())
    }

    pub fn contribute(
        ctx: Context<Contribute>,
        amount: u64,
    ) -> Result<()> {
        let presale = &mut ctx.accounts.presale;
        let user = ctx.accounts.user.key();

        require!(!presale.paused, PresaleError::PresalePaused);
        require!(presale.is_active, PresaleError::PresaleNotActive);
        require!(!presale.is_closed, PresaleError::PresaleClosed);

        let user_tier = presale.whitelist.get(&user).ok_or(PresaleError::UserNotWhitelisted)?;
        let tier_max = presale.tiers.get(user_tier).ok_or(PresaleError::TierDoesNotExist)?;

        require!(
            presale.total_contributions.checked_add(amount).ok_or(PresaleError::Overflow)? <= presale.hard_cap,
            PresaleError::ExceedsHardCap
        );

        let previous_contribution = *presale.contributions.get(&user).unwrap_or(&0);
        let user_contribution = previous_contribution.checked_add(amount).ok_or(PresaleError::Overflow)?;

        require!(
            user_contribution >= presale.min_contribution,
            PresaleError::BelowMinContribution
        );
        require!(
            user_contribution <= *tier_max,
            PresaleError::AboveMaxContribution
        );

        require!(
            ctx.accounts.user_usdt.owner == ctx.accounts.user.key(),
            PresaleError::InvalidUserUsdtAccount
        );

        if previous_contribution == 0 {
            presale.contributors.push(user);
        }
        presale.contributions.insert(user, user_contribution);
        presale.total_contributions = presale
            .total_contributions
            .checked_add(amount)
            .ok_or(PresaleError::Overflow)?;

        let cpi_accounts = token::Transfer {
            from: ctx.accounts.user_usdt.to_account_info(),
            to: ctx.accounts.presale_usdt.to_account_info(),
            authority: ctx.accounts.user.to_account_info(),
        };
        let cpi_program = ctx.accounts.token_program.to_account_info();
        let cpi_ctx = CpiContext::new(cpi_program, cpi_accounts);
        token::transfer(cpi_ctx, amount)?;

        emit!(Contribution {
            contributor: user,
            amount,
            timestamp: Clock::get()?.unix_timestamp as u64,
        });

        Ok(())
    }

    pub fn close_presale(
        ctx: Context<ClosePresale>,
        refunds_allowed: bool,
    ) -> Result<()> {
        let presale = &mut ctx.accounts.presale;

        require!(!presale.paused, PresaleError::PresalePaused);
        require!(presale.is_active, PresaleError::PresaleNotActive);
        require!(!presale.is_closed, PresaleError::PresaleAlreadyClosed);

        presale.is_closed = true;
        presale.is_active = false;
        presale.refunds_allowed = refunds_allowed;

        emit!(PresaleClosed {
            timestamp: Clock::get()?.unix_timestamp as u64,
            refunds_allowed,
        });

        Ok(())
    }

    pub fn withdraw_funds(ctx: Context<WithdrawFunds>) -> Result<()> {
        let presale = &ctx.accounts.presale;

        require!(!presale.paused, PresaleError::PresalePaused);
        require!(presale.is_closed, PresaleError::PresaleNotClosed);

        let usdt_balance = ctx.accounts.presale_usdt.amount;
        require!(usdt_balance > 0, PresaleError::NoFundsToWithdraw);

        let seeds = &[b"presale", &[ctx.bumps.get("presale").unwrap()]];
        let signer = &[&seeds[..]];

        let cpi_accounts = token::Transfer {
            from: ctx.accounts.presale_usdt.to_account_info(),
            to: ctx.accounts.owner_usdt.to_account_info(),
            authority: ctx.accounts.presale.to_account_info(),
        };
        let cpi_program = ctx.accounts.token_program.to_account_info();
        let cpi_ctx = CpiContext::new_with_signer(cpi_program, cpi_accounts, signer);
        token::transfer(cpi_ctx, usdt_balance)?;

        emit!(FundsWithdrawn {
            amount: usdt_balance,
            timestamp: Clock::get()?.unix_timestamp as u64,
        });

        Ok(())
    }

    pub fn refund(ctx: Context<Refund>) -> Result<()> {
        let presale = &mut ctx.accounts.presale;
        let user = ctx.accounts.user.key();

        require!(!presale.paused, PresaleError::PresalePaused);
        require!(presale.is_closed, PresaleError::PresaleNotClosed);
        require!(presale.refunds_allowed, PresaleError::RefundsNotAllowed);

        let contribution = presale.contributions.get(&user).copied().unwrap_or(0);
        require!(contribution > 0, PresaleError::NoContributionsToRefund);
        require!(
            !presale.refunded.get(&user).copied().unwrap_or(false),
            PresaleError::AlreadyRefunded
        );

        presale.contributions.insert(user, 0);
        presale.refunded.insert(user, true);

        let seeds = &[b"presale", &[ctx.bumps.get("presale").unwrap()]];
        let signer = &[&seeds[..]];

        let cpi_accounts = token::Transfer {
            from: ctx.accounts.presale_usdt.to_account_info(),
            to: ctx.accounts.user_usdt.to_account_info(),
            authority: ctx.accounts.presale.to_account_info(),
        };
        let cpi_program = ctx.accounts.token_program.to_account_info();
        let cpi_ctx = CpiContext::new_with_signer(cpi_program, cpi_accounts, signer);
        token::transfer(cpi_ctx, contribution)?;

        emit!(Refund {
            contributor: user,
            amount: contribution,
            timestamp: Clock::get()?.unix_timestamp as u64,
        });

        Ok(())
    }

    pub fn set_min_contribution(
        ctx: Context<UpdatePresale>,
        new_min: u64,
    ) -> Result<()> {
        let presale = &mut ctx.accounts.presale;
        require!(new_min > 0, PresaleError::InvalidMinContribution);

        presale.min_contribution = new_min;

        emit!(MinContributionUpdated {
            new_min_contribution: new_min,
            timestamp: Clock::get()?.unix_timestamp as u64,
        });

        Ok(())
    }

    pub fn set_hard_cap(
        ctx: Context<UpdatePresale>,
        new_hard_cap: u64,
    ) -> Result<()> {
        let presale = &mut ctx.accounts.presale;
        require!(new_hard_cap > 0, PresaleError::InvalidHardCap);
        require!(
            new_hard_cap >= presale.total_contributions,
            PresaleError::HardCapLessThanTotal
        );

        presale.hard_cap = new_hard_cap;

        emit!(HardCapUpdated {
            new_hard_cap,
            timestamp: Clock::get()?.unix_timestamp as u64,
        });

        Ok(())
    }

    pub fn pause_presale(ctx: Context<PausePresale>) -> Result<()> {
        let presale = &mut ctx.accounts.presale;
        require!(!presale.paused, PresaleError::PresaleAlreadyPaused);

        presale.paused = true;

        emit!(PresalePaused {
            timestamp: Clock::get()?.unix_timestamp as u64,
        });

        Ok(())
    }

    pub fn unpause_presale(ctx: Context<UnpausePresale>) -> Result<()> {
        let presale = &mut ctx.accounts.presale;
        require!(presale.paused, PresaleError::PresaleNotPaused);

        presale.paused = false;

        emit!(PresaleUnpaused {
            timestamp: Clock::get()?.unix_timestamp as u64,
        });

        Ok(())
    }
} 