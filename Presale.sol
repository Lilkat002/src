    // SPDX-License-Identifier: MIT
    pragma solidity ^0.8.20;

    import "@openzeppelin/contracts/access/Ownable.sol";
    import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
    import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
    import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
    import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
    import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

    contract Presale is Ownable, ReentrancyGuard {
        using ECDSA for bytes32;
        using MessageHashUtils for bytes32;
        using SafeERC20 for IERC20;

        // Token to be contributed (e.g., USDT or any ERC20 token)
        IERC20 public immutable USDT;

        // Presale parameters
        uint256 public MIN_CONTRIBUTION;  // in USDT (6 decimals)
        uint256 public MAX_CONTRIBUTION;  // in USDT (6 decimals) per user
        uint256 public HARD_CAP;          // in USDT (6 decimals)

        uint256 public totalContributions;
        mapping(address => uint256) public contributions;
        address public signerAddress; // The address used for signing whitelist messages
        bool public isActive;
        bool public isClosed;
        bool public refundsAllowed;

        mapping(address => bool) public refunded;

        address[] public contributors;

        // Events
        event Contribution(address indexed contributor, uint256 amount, uint256 timestamp);
        event PresaleClosed(uint256 timestamp, bool refundsAllowed);
        event FundsWithdrawn(uint256 amount, uint256 timestamp);
        event Refund(address indexed contributor, uint256 amount, uint256 timestamp);
        event MinContributionUpdated(uint256 newMinContribution, uint256 timestamp);
        event MaxContributionUpdated(uint256 newMaxContribution, uint256 timestamp);
        event HardCapUpdated(uint256 newHardCap, uint256 timestamp);

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

        function contribute(uint256 amount, bytes memory signature)
            external
            nonReentrant
        {
            require(isActive, "Presale not active");
            require(!isClosed, "Presale is closed");

            bytes32 messageHash = keccak256(abi.encodePacked(msg.sender, address(this)));
            bytes32 ethSignedMessageHash = messageHash.toEthSignedMessageHash();
            address recovered = ethSignedMessageHash.recover(signature);
            require(recovered == signerAddress, "Invalid signature");

            require(totalContributions + amount <= HARD_CAP, "Would exceed hard cap");

            uint256 newContribution = contributions[msg.sender] + amount;
            require(newContribution >= MIN_CONTRIBUTION, "Total contributions below minimum limit");
            require(newContribution <= MAX_CONTRIBUTION, "Above max contribution limit");

            if (contributions[msg.sender] == 0) {
                contributors.push(msg.sender);
            }
            contributions[msg.sender] = newContribution;
            totalContributions += amount;

            USDT.safeTransferFrom(msg.sender, address(this), amount);

            emit Contribution(msg.sender, amount, block.timestamp);
        }

        function closePresale(bool _refundsAllowed) external onlyOwner {
            require(isActive, "Presale not active");
            require(!isClosed, "Presale already closed");

            isClosed = true;
            isActive = false;
            refundsAllowed = _refundsAllowed;

            emit PresaleClosed(block.timestamp, refundsAllowed);
        }

        function withdrawFunds() external onlyOwner nonReentrant {
            require(isClosed, "Presale must be closed");

            uint256 balance = USDT.balanceOf(address(this));
            require(balance > 0, "No funds to withdraw");

            USDT.safeTransfer(owner(), balance);

            emit FundsWithdrawn(balance, block.timestamp);
        }

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

        function setMinContribution(uint256 _minContribution) external onlyOwner {
            require(_minContribution > 0, "Min contribution must be > 0");
            require(_minContribution <= MAX_CONTRIBUTION, "Min must be <= Max");
            MIN_CONTRIBUTION = _minContribution;
            emit MinContributionUpdated(_minContribution, block.timestamp);
        }

        function setMaxContribution(uint256 _maxContribution) external onlyOwner {
            require(_maxContribution >= MIN_CONTRIBUTION, "Max must be >= Min");
            
            for (uint256 i = 0; i < contributors.length; i++) {
                require(_maxContribution >= contributions[contributors[i]], "Cannot set max below existing contributions");
            }
            
            MAX_CONTRIBUTION = _maxContribution;
            emit MaxContributionUpdated(_maxContribution, block.timestamp);
        }

        function setHardCap(uint256 _hardCap) external onlyOwner {
            require(_hardCap > 0, "Hard cap must be > 0");
            require(_hardCap >= totalContributions, "Hard cap cannot be less than total contributions");
            
            HARD_CAP = _hardCap;
            emit HardCapUpdated(_hardCap, block.timestamp);
        }

        function getContribution(address contributor) external view returns (uint256) {
            return contributions[contributor];
        }

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

        function updateSigner(address newSigner) external onlyOwner {
            require(newSigner != address(0), "Invalid address");
            signerAddress = newSigner;
        }
    }
