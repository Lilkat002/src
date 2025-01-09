// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

contract PeacepalAIDistribution is Ownable, ReentrancyGuard, Pausable {
    IERC20 public token;
    uint256 public totalRaised;
    bool public allocationCalculated;
    bool public claimEnabled;
    uint256 public maxBatchSize;
    bool public claimPeriodOpen;
    
    // Track contributors explicitly
    address[] public contributorList;
    mapping(address => bool) public isContributor;
    mapping(address => uint256) public contributions;
    mapping(address => uint256) public allocations;

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

    constructor() Ownable(msg.sender) {
        maxBatchSize = 500; // Default batch size
    }

    function setToken(address _token) external onlyOwner whenNotPaused {
        if (_token == address(0)) revert ZeroAddress();
        if (claimPeriodOpen) revert ClaimPeriodActive();
        
        token = IERC20(_token);
        emit TokenSet(_token);
    }

    function setMaxBatchSize(uint256 newSize) external onlyOwner {
        if (newSize == 0) revert ZeroAmount();
        maxBatchSize = newSize;
        emit MaxBatchSizeUpdated(newSize);
    }

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
            
            // Add new contributor to list
            if (!isContributor[users[i]]) {
                isContributor[users[i]] = true;
                contributorList.push(users[i]);
            }
            
            // Update totalRaised by adding new amount and subtracting previous contribution
            totalRaised = totalRaised + amounts[i] - contributions[users[i]];
            
            // Set contribution
            contributions[users[i]] = amounts[i];

            emit ContributionUpdated(users[i], amounts[i]);
        }

        emit ContributionsUpdated(users, amounts);
    }

    function calculateAllocations() external onlyOwner whenNotPaused {
        if (address(token) == address(0)) revert ZeroAddress();
        if (totalRaised == 0) revert NoContributions();
        if (allocationCalculated) revert AllocationAlreadyCalculated();

        uint256 totalTokens = token.balanceOf(address(this));
        if (totalTokens == 0) revert NoTokenBalance();

        uint256 allocatedAmount;
        
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

    function enableClaim() external onlyOwner whenNotPaused {
        if (!allocationCalculated) revert NotCalculated();
        claimEnabled = true;
        emit ClaimEnabled();
    }

    function openClaimPeriod() external onlyOwner whenNotPaused {
        if (!claimEnabled) revert ClaimingNotEnabled();
        claimPeriodOpen = true;
        emit ClaimPeriodOpened();
    }

    function closeClaimPeriod() external onlyOwner whenNotPaused {
        claimPeriodOpen = false;
        emit ClaimPeriodClosed();
    }

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

    function removeContributor(address user) external onlyOwner whenNotPaused {
        if (allocationCalculated) revert ContributionsLocked();
        if (!isContributor[user]) revert NotContributor();
        
        // Remove from mapping
        isContributor[user] = false;
        totalRaised -= contributions[user];
        contributions[user] = 0;

        // Remove from contributorList
        for (uint256 i = 0; i < contributorList.length; i++) {
            if (contributorList[i] == user) {
                // Move the last element to this position and pop
                contributorList[i] = contributorList[contributorList.length - 1];
                contributorList.pop();
                break;
            }
        }

        emit ContributionUpdated(user, 0);
    }

    function updateContribution(address user, uint256 newAmount) external onlyOwner whenNotPaused {
        if (allocationCalculated) revert ContributionsLocked();
        if (!isContributor[user]) revert NotContributor();
        if (newAmount == 0) revert ZeroAmount();

        // Update total raised
        totalRaised = totalRaised - contributions[user] + newAmount;
        contributions[user] = newAmount;

        emit ContributionUpdated(user, newAmount);
    }

    // View functions
    function getContributors() external view returns (address[] memory) {
        return contributorList;
    }

    function getContributorCount() external view returns (uint256) {
        return contributorList.length;
    }

    // Emergency functions
    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
} 
