pub mod state;
pub mod instructions;
pub mod error;
pub mod events;
pub mod context;

pub use state::*;
pub use instructions::*;
pub use error::*;
pub use events::*;
pub use context::*;

use anchor_lang::prelude::*;
use anchor_spl::token::{self, Token, TokenAccount, Transfer, Mint};

declare_id!("YourProgramIDHere1234567890ABCDEFGH");

// Constants
pub const USDT_DECIMALS: u64 = 1_000_000;
pub const MAX_TIERS: usize = 10;
pub const MAX_USERS: usize = 1000;
pub const MAX_TIER_NAME_LENGTH: usize = 32;
pub const MAX_BULK_ASSIGN: usize = 50; 