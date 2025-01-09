    // SPDX-License-Identifier: MIT
    pragma solidity ^0.8.20;

    // Import required OpenZeppelin contracts
    import "@openzeppelin/contracts/access/Ownable.sol";          // Provides basic access control
    import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";  // Prevents re-entrancy attacks
    import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol"; // Utilities for message signing
    import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";           // For signature verification
    import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";       // Safe ERC20 operations
    import "@openzeppelin/contracts/token/ERC20/IERC20.sol";                // ERC20 interface

    /**
     * @title Presale
     * @dev A presale contract that allows whitelisted users to contribute USDT tokens
     * Features include:
     * - Whitelist verification through signatures
     * - Minimum and maximum contribution limits
     * - Hard cap
     * - Refund mechanism
     * - Owner controls for presale parameters
     */
    contract Presale is Ownable, ReentrancyGuard {
        // Library usage for cryptographic and safe token operations
        using ECDSA for bytes32;
        using MessageHashUtils for bytes32;
        using SafeERC20 for IERC20;

        // The ERC20 token used for contributions (e.g., USDT)
        IERC20 public immutable USDT;

        // Presale configuration parameters
        uint256 public MIN_CONTRIBUTION;  // Minimum amount user can contribute (in USDT with 6 decimals)
        uint256 public MAX_CONTRIBUTION;  // Maximum amount per user (in USDT with 6 decimals)
        uint256 public HARD_CAP;         // Maximum total contributions allowed (in USDT with 6 decimals)

        // Presale state variables
        uint256 public totalContributions;                    // Total amount contributed
        mapping(address => uint256) public contributions;     // Track contributions per address
        address public signerAddress;                         // Address authorized to sign whitelist messages
        bool public isActive;                                 // Whether the presale is currently active
        bool public isClosed;                                 // Whether the presale has been closed
        bool public refundsAllowed;                          // Whether refunds are enabled after closing

        // Refund tracking
        mapping(address => bool) public refunded;            // Track which addresses have been refunded

        // List of all contributors for iteration
        address[] public contributors;

        // Events for important state changes
        event Contribution(address indexed contributor, uint256 amount, uint256 timestamp);
        event PresaleClosed(uint256 timestamp, bool refundsAllowed);
        event FundsWithdrawn(uint256 amount, uint256 timestamp);
        event Refund(address indexed contributor, uint256 amount, uint256 timestamp);
        event MinContributionUpdated(uint256 newMinContribution, uint256 timestamp);
        event MaxContributionUpdated(uint256 newMaxContribution, uint256 timestamp);
        event HardCapUpdated(uint256 newHardCap, uint256 timestamp);

        /**
         * @dev Constructor to initialize the presale contract
         * @param _usdtAddress Address of the USDT token contract
         * @param _signerAddress Address authorized to sign whitelist messages
         * @param _minContribution Minimum contribution amount
         * @param _maxContribution Maximum contribution amount per user
         * @param _hardCap Maximum total contributions allowed
         */
        constructor(
            address _usdtAddress,
            address _signerAddress,
            uint256 _minContribution,
            uint256 _maxContribution,
            uint256 _hardCap
        ) Ownable(msg.sender) {
            require(_usdtAddress != address(0), "Invalid USDT address");
            require(_signerAddress != address(0), "Invalid signer address");
            require(_minContribution > 0, "Min contribution must be > 0");
            require(_maxContribution >= _minContribution, "Max must be >= min");
            require(_hardCap > 0, "Hard cap must be > 0");

            USDT = IERC20(_usdtAddress);
            signerAddress = _signerAddress;
            MIN_CONTRIBUTION = _minContribution;
            MAX_CONTRIBUTION = _maxContribution;
            HARD_CAP = _hardCap;
            isActive = true;
        }

        /**
         * @dev Allows whitelisted users to contribute USDT to the presale
         * @param amount Amount of USDT to contribute
         * @param signature Whitelist verification signature from authorized signer
         */
        function contribute(uint256 amount, bytes memory signature)
            external
            nonReentrant
        {
            // Check presale state
            require(isActive, "Presale not active");
            require(!isClosed, "Presale is closed");

            // Verify whitelist signature
            bytes32 messageHash = keccak256(abi.encodePacked(msg.sender, address(this)));
            bytes32 ethSignedMessageHash = messageHash.toEthSignedMessageHash();
            address recovered = ethSignedMessageHash.recover(signature);
            require(recovered == signerAddress, "Invalid signature");

            // Verify contribution limits
            require(totalContributions + amount <= HARD_CAP, "Would exceed hard cap");
            uint256 newContribution = contributions[msg.sender] + amount;
            require(newContribution >= MIN_CONTRIBUTION, "Total contributions below minimum limit");
            require(newContribution <= MAX_CONTRIBUTION, "Above max contribution limit");

            // Update state
            if (contributions[msg.sender] == 0) {
                contributors.push(msg.sender);
            }
            contributions[msg.sender] = newContribution;
            totalContributions += amount;

            // Transfer USDT from contributor
            USDT.safeTransferFrom(msg.sender, address(this), amount);

            emit Contribution(msg.sender, amount, block.timestamp);
        }

        /**
         * @dev Allows owner to close the presale and set refund availability
         * @param _refundsAllowed Whether refunds should be enabled after closing
         */
        function closePresale(bool _refundsAllowed) external onlyOwner {
            require(isActive, "Presale not active");
            require(!isClosed, "Presale already closed");

            isClosed = true;
            isActive = false;
            refundsAllowed = _refundsAllowed;

            emit PresaleClosed(block.timestamp, refundsAllowed);
        }

        /**
         * @dev Allows owner to withdraw collected USDT after presale closes
         */
        function withdrawFunds() external onlyOwner nonReentrant {
            require(isClosed, "Presale must be closed");

            uint256 balance = USDT.balanceOf(address(this));
            require(balance > 0, "No funds to withdraw");

            USDT.safeTransfer(owner(), balance);

            emit FundsWithdrawn(balance, block.timestamp);
        }

        /**
         * @dev Allows contributors to claim refunds if enabled
         */
        function refund() external nonReentrant {
            require(isClosed, "Presale is not closed");
            require(refundsAllowed, "Refunds are not allowed");
            uint256 contribution = contributions[msg.sender];
            require(contribution > 0, "No contributions to refund");
            require(!refunded[msg.sender], "Already refunded");

            contributions[msg.sender] = 0;
            refunded[msg.sender] = true;

            USDT.safeTransfer(msg.sender, contribution);

            emit Refund(msg.sender, contribution, block.timestamp);
        }

        // Admin functions to update presale parameters

        /**
         * @dev Updates minimum contribution amount
         * @param _minContribution New minimum contribution value
         */
        function setMinContribution(uint256 _minContribution) external onlyOwner {
            require(_minContribution > 0, "Min contribution must be > 0");
            require(_minContribution <= MAX_CONTRIBUTION, "Min must be <= Max");
            MIN_CONTRIBUTION = _minContribution;
            emit MinContributionUpdated(_minContribution, block.timestamp);
        }

        /**
         * @dev Updates maximum contribution amount
         * @param _maxContribution New maximum contribution value
         */
        function setMaxContribution(uint256 _maxContribution) external onlyOwner {
            require(_maxContribution >= MIN_CONTRIBUTION, "Max must be >= Min");
            
            // Ensure new max is not below any existing contributions
            for (uint256 i = 0; i < contributors.length; i++) {
                require(_maxContribution >= contributions[contributors[i]], 
                        "Cannot set max below existing contributions");
            }
            
            MAX_CONTRIBUTION = _maxContribution;
            emit MaxContributionUpdated(_maxContribution, block.timestamp);
        }

        /**
         * @dev Updates hard cap amount
         * @param _hardCap New hard cap value
         */
        function setHardCap(uint256 _hardCap) external onlyOwner {
            require(_hardCap > 0, "Hard cap must be > 0");
            require(_hardCap >= totalContributions, 
                    "Hard cap cannot be less than total contributions");
            
            HARD_CAP = _hardCap;
            emit HardCapUpdated(_hardCap, block.timestamp);
        }

        // View functions

        /**
         * @dev Returns contribution amount for a specific address
         * @param contributor Address to check
         * @return Amount contributed by the address
         */
        function getContribution(address contributor) external view returns (uint256) {
            return contributions[contributor];
        }

        /**
         * @dev Returns current presale status
         * @return total Total contributions
         * @return remaining Remaining amount until hard cap
         * @return active Whether presale is active
         * @return closed Whether presale is closed
         */
        function getPresaleStatus()
            external
            view
            returns (
                uint256 total,
                uint256 remaining,
                bool active,
                bool closed
            )
        {
            return (
                totalContributions,
                HARD_CAP - totalContributions,
                isActive,
                isClosed
            );
        }

        /**
         * @dev Updates the address authorized to sign whitelist messages
         * @param newSigner New signer address
         */
        function updateSigner(address newSigner) external onlyOwner {
            require(newSigner != address(0), "Invalid address");
            signerAddress = newSigner;
        }
    }
