// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// Import required OpenZeppelin contracts
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title PeacepalAIDistribution
 * @dev Contract for managing token distribution based on user contributions
 * Inherits from:
 * - Ownable: Manages contract ownership and access control
 * - ReentrancyGuard: Prevents reentrancy attacks
 * - Pausable: Allows pausing contract functionality in emergencies
 */
contract PeacepalAIDistribution is Ownable, ReentrancyGuard, Pausable {
    // State Variables
    IERC20 public token;              // The ERC20 token to be distributed
    uint256 public totalRaised;       // Total amount of contributions
    bool public allocationCalculated;  // Flag to track if allocations have been calculated
    bool public claimEnabled;         // Flag to enable/disable claiming
    uint256 public maxBatchSize;      // Maximum number of users in a batch operation
    bool public claimPeriodOpen;      // Flag to track if claim period is active
    
    // Data structures for tracking contributors and their allocations
    address[] public contributorList;                    // List of all contributors
    mapping(address => bool) public isContributor;       // Track if address is a contributor
    mapping(address => uint256) public contributions;    // Amount contributed by each address
    mapping(address => uint256) public allocations;      // Token allocation for each address

    // Events for tracking contract state changes
    event TokenSet(address indexed tokenAddress);
    event ContributionsUpdated(address[] users, uint256[] amounts);
    event ContributionUpdated(address indexed user, uint256 amount);
    event AllocationCalculated(uint256 totalRaised, uint256 totalTokensForDistribution);
    event TokensClaimed(address indexed user, uint256 amount);
    event ClaimEnabled();
    event UnclaimedTokensWithdrawn(uint256 amount);
    event MaxBatchSizeUpdated(uint256 newSize);
    event ClaimPeriodOpened();
    event ClaimPeriodClosed();

    // Custom errors for better gas efficiency and clearer error messages
    error ZeroAddress();
    error ZeroAmount();
    error BatchTooLarge();
    error ArrayLengthMismatch();
    error AllocationAlreadyCalculated();
    error NoContributions();
    error NoTokenBalance();
    error NotCalculated();
    error NothingToClaim();
    error TransferFailed();
    error AllocationExceedsBalance();
    error ClaimingNotEnabled();
    error NoTokensToWithdraw();
    error NotContributor();
    error ContributionsLocked();
    error ClaimPeriodActive();

    /**
     * @dev Constructor sets initial maxBatchSize and initializes Ownable
     */
    constructor() Ownable(msg.sender) {
        maxBatchSize = 500; // Default batch size
    }

    /**
     * @dev Sets the token address for distribution
     * @param _token Address of the ERC20 token
     * Requirements:
     * - Only owner can call
     * - Contract must not be paused
     * - Token address cannot be zero
     * - Claim period must not be active
     */
    function setToken(address _token) external onlyOwner whenNotPaused {
        if (_token == address(0)) revert ZeroAddress();
        if (claimPeriodOpen) revert ClaimPeriodActive();
        
        token = IERC20(_token);
        emit TokenSet(_token);
    }

    /**
     * @dev Updates the maximum batch size for contribution operations
     * @param newSize New maximum batch size
     * Requirements:
     * - Only owner can call
     * - New size cannot be zero
     */
    function setMaxBatchSize(uint256 newSize) external onlyOwner {
        if (newSize == 0) revert ZeroAmount();
        maxBatchSize = newSize;
        emit MaxBatchSizeUpdated(newSize);
    }

    /**
     * @dev Batch sets contributions for multiple users
     * @param users Array of user addresses
     * @param amounts Array of contribution amounts
     * Requirements:
     * - Only owner can call
     * - Contract must not be paused
     * - Allocations must not be already calculated
     * - Arrays must be same length and not exceed maxBatchSize
     */
    function batchSetContributions(
        address[] calldata users,
        uint256[] calldata amounts
    ) external onlyOwner whenNotPaused {
        if (allocationCalculated) revert AllocationAlreadyCalculated();
        if (users.length != amounts.length) revert ArrayLengthMismatch();
        if (users.length > maxBatchSize) revert BatchTooLarge();

        for (uint256 i = 0; i < users.length; i++) {
            if (users[i] == address(0)) revert ZeroAddress();
            if (amounts[i] == 0) revert ZeroAmount();
            
            // Add new contributor to list if not already present
            if (!isContributor[users[i]]) {
                isContributor[users[i]] = true;
                contributorList.push(users[i]);
            }
            
            // Update totalRaised by adding new amount and subtracting previous contribution
            totalRaised = totalRaised + amounts[i] - contributions[users[i]];
            
            // Set contribution and emit event
            contributions[users[i]] = amounts[i];
            emit ContributionUpdated(users[i], amounts[i]);
        }

        emit ContributionsUpdated(users, amounts);
    }

    /**
     * @dev Calculates token allocations based on contributions
     * Requirements:
     * - Only owner can call
     * - Contract must not be paused
     * - Token must be set
     * - Must have contributions
     * - Allocations must not be already calculated
     * - Contract must have token balance
     */
    function calculateAllocations() external onlyOwner whenNotPaused {
        if (address(token) == address(0)) revert ZeroAddress();
        if (totalRaised == 0) revert NoContributions();
        if (allocationCalculated) revert AllocationAlreadyCalculated();

        uint256 totalTokens = token.balanceOf(address(this));
        if (totalTokens == 0) revert NoTokenBalance();

        uint256 allocatedAmount;
        
        // Calculate proportional allocations for each contributor
        for (uint256 i = 0; i < contributorList.length; i++) {
            address user = contributorList[i];
            uint256 userContribution = contributions[user];
            
            if (userContribution > 0) {
                uint256 allocation = (userContribution * totalTokens) / totalRaised;
                allocations[user] = allocation;
                allocatedAmount += allocation;
            }
        }

        if (allocatedAmount > totalTokens) revert AllocationExceedsBalance();
        
        allocationCalculated = true;
        emit AllocationCalculated(totalRaised, totalTokens);
    }

    /**
     * @dev Enables token claiming
     * Requirements:
     * - Only owner can call
     * - Contract must not be paused
     * - Allocations must be calculated
     */
    function enableClaim() external onlyOwner whenNotPaused {
        if (!allocationCalculated) revert NotCalculated();
        claimEnabled = true;
        emit ClaimEnabled();
    }

    /**
     * @dev Opens the claim period
     * Requirements:
     * - Only owner can call
     * - Contract must not be paused
     * - Claiming must be enabled
     */
    function openClaimPeriod() external onlyOwner whenNotPaused {
        if (!claimEnabled) revert ClaimingNotEnabled();
        claimPeriodOpen = true;
        emit ClaimPeriodOpened();
    }

    /**
     * @dev Closes the claim period
     * Requirements:
     * - Only owner can call
     * - Contract must not be paused
     */
    function closeClaimPeriod() external onlyOwner whenNotPaused {
        claimPeriodOpen = false;
        emit ClaimPeriodClosed();
    }

    /**
     * @dev Allows users to claim their allocated tokens
     * Requirements:
     * - Contract must not be paused
     * - Claiming must be enabled and period must be open
     * - User must have allocation to claim
     * - Transfer must succeed
     */
    function claim() external nonReentrant whenNotPaused {
        if (!claimEnabled) revert ClaimingNotEnabled();
        if (!claimPeriodOpen) revert ClaimingNotEnabled();
        if (allocations[msg.sender] == 0) revert NothingToClaim();

        uint256 amount = allocations[msg.sender];
        allocations[msg.sender] = 0;
        
        bool success = token.transfer(msg.sender, amount);
        if (!success) revert TransferFailed();
        
        emit TokensClaimed(msg.sender, amount);
    }

    /**
     * @dev Allows owner to withdraw unclaimed tokens
     * Requirements:
     * - Only owner can call
     * - Contract must not be paused
     * - Allocations must be calculated
     * - Claim period must not be active
     * - Transfer must succeed
     */
    function withdrawUnclaimedTokens() external onlyOwner whenNotPaused {
        if (!allocationCalculated) revert NotCalculated();
        if (claimPeriodOpen) revert ClaimPeriodActive();
        uint256 balance = token.balanceOf(address(this));
        if (balance == 0) revert NoTokensToWithdraw();
        
        // Emit event before external call
        emit UnclaimedTokensWithdrawn(balance);
        
        // Make external call after event
        bool success = token.transfer(owner(), balance);
        if (!success) revert TransferFailed();
    }

    /**
     * @dev Removes a contributor and their contribution
     * @param user Address of contributor to remove
     * Requirements:
     * - Only owner can call
     * - Contract must not be paused
     * - Allocations must not be calculated
     * - Address must be a contributor
     */
    function removeContributor(address user) external onlyOwner whenNotPaused {
        if (allocationCalculated) revert ContributionsLocked();
        if (!isContributor[user]) revert NotContributor();
        
        // Remove from mapping and update total
        isContributor[user] = false;
        totalRaised -= contributions[user];
        contributions[user] = 0;

        // Remove from contributorList using swap and pop
        for (uint256 i = 0; i < contributorList.length; i++) {
            if (contributorList[i] == user) {
                contributorList[i] = contributorList[contributorList.length - 1];
                contributorList.pop();
                break;
            }
        }

        emit ContributionUpdated(user, 0);
    }

    /**
     * @dev Updates contribution amount for a specific user
     * @param user Address of contributor
     * @param newAmount New contribution amount
     * Requirements:
     * - Only owner can call
     * - Contract must not be paused
     * - Allocations must not be calculated
     * - Address must be a contributor
     * - New amount cannot be zero
     */
    function updateContribution(address user, uint256 newAmount) external onlyOwner whenNotPaused {
        if (allocationCalculated) revert ContributionsLocked();
        if (!isContributor[user]) revert NotContributor();
        if (newAmount == 0) revert ZeroAmount();

        // Update total raised and contribution
        totalRaised = totalRaised - contributions[user] + newAmount;
        contributions[user] = newAmount;

        emit ContributionUpdated(user, newAmount);
    }

    /**
     * @dev Returns list of all contributors
     * @return Array of contributor addresses
     */
    function getContributors() external view returns (address[] memory) {
        return contributorList;
    }

    /**
     * @dev Returns total number of contributors
     * @return Number of contributors
     */
    function getContributorCount() external view returns (uint256) {
        return contributorList.length;
    }

    /**
     * @dev Pauses all contract operations
     * Requirements:
     * - Only owner can call
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @dev Unpauses contract operations
     * Requirements:
     * - Only owner can call
     */
    function unpause() external onlyOwner {
        _unpause();
    }
} 
