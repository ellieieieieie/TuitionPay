// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/**
 * @title TuitionPayment
 * @notice Escrow-based tuition payment system on Polygon PoS using USDC.
 *         Students deposit USDC into per-student escrow; admin executes
 *         batch payment to the university wallet on the due date.
 *
 *         Integrates Chainlink Price Feeds for on-chain FX rate transparency.
 *         The FX rate is recorded in each payment receipt for auditability,
 *         though all payments are denominated in USDC.
 *
 *         Security: AccessControl (RBAC), ReentrancyGuard, Pausable,
 *         CEI pattern on all state-changing functions, bounded batch size.
 *
 * @dev    All monetary values use USDC's 6-decimal representation.
 *         Chainlink FX feeds return 8-decimal values.
 */
contract TuitionPayment is AccessControl, ReentrancyGuard, Pausable {

    // ========================
    // ROLES
    // ========================
    bytes32 public constant ADMIN_ROLE   = keccak256("ADMIN_ROLE");
    bytes32 public constant STUDENT_ROLE = keccak256("STUDENT_ROLE");

    // ========================
    // STATE
    // ========================
    IERC20  public immutable usdc;
    address public universityWallet;

    /// @notice Chainlink price feed for JPY/USD (or any base/USD pair)
    AggregatorV3Interface public priceFeed;

    /// @notice Per-student escrow balance (USDC, 6 decimals)
    mapping(address => uint256) public escrowBalance;

    /// @notice Credit units assigned to each student by admin
    mapping(address => uint256) public creditUnits;

    /// @notice Fee per credit unit in USDC (6 decimals)
    uint256 public feePerUnit;

    /// @notice Timestamp when payment will be pulled from escrow
    uint256 public paymentDate;

    /// @notice Privacy layer: hashed student ID -> wallet address
    ///         Keeps plaintext student IDs off-chain only.
    mapping(bytes32 => address) public studentHashToWallet;

    // ========================
    // CONSTANTS / BOUNDS
    // ========================
    uint256 public constant MIN_CREDIT_UNITS   = 1;
    uint256 public constant MAX_CREDIT_UNITS   = 30;
    uint256 public constant MAX_BATCH_SIZE     = 50;
    uint256 public constant STALENESS_THRESHOLD = 1 hours;

    // ========================
    // EVENTS
    // ========================
    event StudentWhitelisted(address indexed student, bytes32 indexed studentHash);
    event CreditUnitsSet(address indexed student, uint256 units);
    event Deposit(address indexed student, uint256 amount);
    event PaymentExecuted(
        address indexed student,
        uint256 amount,
        int256  fxRate,
        uint256 timestamp
    );
    event InsufficientBalance(address indexed student, uint256 required, uint256 actual);
    event PaymentDateSet(uint256 date);
    event EmergencyWithdrawal(address indexed student, uint256 amount);
    event UniversityWalletUpdated(address indexed oldWallet, address indexed newWallet);
    event FeePerUnitUpdated(uint256 oldFee, uint256 newFee);
    event PriceFeedUpdated(address indexed oldFeed, address indexed newFeed);

    // ========================
    // CONSTRUCTOR
    // ========================
    constructor(
        address _usdc,
        address _admin,
        address _universityWallet,
        uint256 _feePerUnit,
        address _priceFeed
    ) {
        require(_usdc != address(0), "Invalid USDC address");
        require(_admin != address(0), "Invalid admin address");
        require(_universityWallet != address(0), "Invalid university wallet");
        require(_feePerUnit > 0, "Fee per unit must be > 0");
        require(_priceFeed != address(0), "Invalid price feed address");

        usdc = IERC20(_usdc);
        universityWallet = _universityWallet;
        feePerUnit = _feePerUnit;
        priceFeed = AggregatorV3Interface(_priceFeed);

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ADMIN_ROLE, _admin);
    }

    // ================================================================
    //  CHAINLINK ORACLE
    // ================================================================

    /**
     * @notice Read the latest FX rate from Chainlink with a staleness check.
     * @return price     The latest price (8 decimals for FX feeds)
     * @return updatedAt Timestamp of the last update
     *
     * @dev Reverts if the feed has not been updated within STALENESS_THRESHOLD.
     *      This protects against using stale data during market closures or
     *      oracle outages.
     */
    function getLatestRate()
        public
        view
        returns (int256 price, uint256 updatedAt)
    {
        (, price, , updatedAt, ) = priceFeed.latestRoundData();
        require(price > 0, "Invalid price from oracle");
        require(
            block.timestamp - updatedAt < STALENESS_THRESHOLD,
            "Price feed is stale"
        );
    }

    // ================================================================
    //  ADMIN FUNCTIONS
    // ================================================================

    /**
     * @notice Whitelist a student and map their hashed ID to their wallet.
     * @param student     Wallet address of the student
     * @param studentHash keccak256(abi.encodePacked(studentId)) — computed
     *                    off-chain so plaintext ID never touches the chain.
     */
    function whitelistStudent(address student, bytes32 studentHash)
        external
        onlyRole(ADMIN_ROLE)
    {
        require(student != address(0), "Invalid student address");
        require(studentHash != bytes32(0), "Invalid student hash");
        require(
            studentHashToWallet[studentHash] == address(0),
            "Student hash already registered"
        );

        _grantRole(STUDENT_ROLE, student);
        studentHashToWallet[studentHash] = student;

        emit StudentWhitelisted(student, studentHash);
    }

    /**
     * @notice Assign credit units to a whitelisted student.
     * @param student Address of the student
     * @param units   Number of credit units (1–30)
     */
    function setCreditUnits(address student, uint256 units)
        external
        onlyRole(ADMIN_ROLE)
    {
        require(hasRole(STUDENT_ROLE, student), "Student not whitelisted");
        require(
            units >= MIN_CREDIT_UNITS && units <= MAX_CREDIT_UNITS,
            "Credit units out of range"
        );

        creditUnits[student] = units;
        emit CreditUnitsSet(student, units);
    }

    /**
     * @notice Set the date when batch payment will be executed.
     * @param _date Unix timestamp for the payment deadline (must be future)
     */
    function setPaymentDate(uint256 _date)
        external
        onlyRole(ADMIN_ROLE)
    {
        require(_date > block.timestamp, "Date must be in the future");
        paymentDate = _date;
        emit PaymentDateSet(_date);
    }

    /**
     * @notice Update the university receiving wallet.
     * @param _wallet New university wallet address
     */
    function setUniversityWallet(address _wallet)
        external
        onlyRole(ADMIN_ROLE)
    {
        require(_wallet != address(0), "Invalid address");
        address oldWallet = universityWallet;
        universityWallet = _wallet;
        emit UniversityWalletUpdated(oldWallet, _wallet);
    }

    /**
     * @notice Update the fee per credit unit.
     * @param _fee New fee in USDC (6 decimals)
     */
    function setFeePerUnit(uint256 _fee)
        external
        onlyRole(ADMIN_ROLE)
    {
        require(_fee > 0, "Fee must be > 0");
        uint256 oldFee = feePerUnit;
        feePerUnit = _fee;
        emit FeePerUnitUpdated(oldFee, _fee);
    }

    /**
     * @notice Update the Chainlink price feed address.
     * @param _priceFeed New AggregatorV3Interface address
     */
    function setPriceFeed(address _priceFeed)
        external
        onlyRole(ADMIN_ROLE)
    {
        require(_priceFeed != address(0), "Invalid price feed address");
        address oldFeed = address(priceFeed);
        priceFeed = AggregatorV3Interface(_priceFeed);
        emit PriceFeedUpdated(oldFeed, _priceFeed);
    }

    function pause() external onlyRole(ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }

    /**
     * @notice Execute batch payment for an array of students.
     *         Follows CEI (Checks-Effects-Interactions) per student.
     *
     * @dev Gas optimisations applied:
     *      - Bounded batch size prevents out-of-gas on large arrays
     *      - feePerUnit cached in memory to avoid repeated SLOAD
     *      - Unchecked loop increment (cannot overflow with bounded size)
     *      - FX rate fetched once and recorded in each payment event
     *
     * @param students Array of student addresses to process (max 50)
     */
    function executePayment(address[] calldata students)
        external
        onlyRole(ADMIN_ROLE)
        nonReentrant
        whenNotPaused
    {
        // --- Checks ---
        require(paymentDate > 0, "Payment date not set");
        require(block.timestamp >= paymentDate, "Payment date not reached");
        require(students.length > 0, "Empty student array");
        require(students.length <= MAX_BATCH_SIZE, "Batch too large");

        // Fetch FX rate once for the entire batch (informational, for receipts)
        (int256 fxRate, ) = getLatestRate();

        // Cache storage variable to save gas (avoid repeated SLOAD)
        uint256 _feePerUnit = feePerUnit;
        address _universityWallet = universityWallet;

        for (uint256 i = 0; i < students.length; ) {
            address student = students[i];
            uint256 required = creditUnits[student] * _feePerUnit;
            uint256 balance  = escrowBalance[student];

            if (balance >= required) {
                // --- Effect (before interaction) ---
                escrowBalance[student] = balance - required;

                // --- Interaction ---
                require(
                    usdc.transfer(_universityWallet, required),
                    "USDC transfer to university failed"
                );

                emit PaymentExecuted(student, required, fxRate, block.timestamp);
            } else {
                emit InsufficientBalance(student, required, balance);
            }

            // Gas-optimised increment: safe because i < students.length <= 50
            unchecked { ++i; }
        }
    }

    // ================================================================
    //  STUDENT FUNCTIONS
    // ================================================================

    /**
     * @notice Deposit USDC into the student's escrow account.
     *         Student must first call usdc.approve(thisContract, amount).
     *
     * @dev    CEI pattern: update escrow balance (effect) BEFORE calling
     *         transferFrom (interaction). Although transferFrom reverts on
     *         failure (so the effect would be rolled back), placing the
     *         effect first is defensive and follows best practices.
     *
     *         If transferFrom reverts, the entire transaction reverts,
     *         including the balance update — so no inconsistent state.
     *
     * @param amount  USDC amount in 6-decimal units
     *                (e.g. 1000 USDC = 1000 * 10**6 = 1_000_000_000)
     */
    function deposit(uint256 amount)
        external
        onlyRole(STUDENT_ROLE)
        nonReentrant
        whenNotPaused
    {
        require(amount > 0, "Deposit amount must be > 0");

        // --- Effect (update state before external call) ---
        escrowBalance[msg.sender] += amount;

        // --- Interaction (pull USDC from student wallet) ---
        require(
            usdc.transferFrom(msg.sender, address(this), amount),
            "USDC transfer failed"
        );

        emit Deposit(msg.sender, amount);
    }

    /**
     * @notice View the caller's escrow balance.
     * @return The caller's escrowed USDC amount (6 decimals)
     */
    function getMyBalance() external view returns (uint256) {
        return escrowBalance[msg.sender];
    }

    /**
     * @notice Calculate total fees owed by a student.
     * @param student  Address of the student
     * @return Total USDC owed (creditUnits * feePerUnit)
     */
    function calculateFees(address student) public view returns (uint256) {
        return creditUnits[student] * feePerUnit;
    }

    /**
     * @notice Check whether a student has deposited enough to cover fees.
     * @param student  Address of the student
     * @return True if escrow balance >= total fees
     */
    function checkSufficient(address student) external view returns (bool) {
        return escrowBalance[student] >= calculateFees(student);
    }

    /**
     * @notice Emergency withdrawal — student can reclaim their full escrow
     *         balance, but ONLY when the contract is paused (oracle failure,
     *         stablecoin depeg, detected exploit).
     *
     * @dev    CEI pattern: zero the balance (effect) before transferring
     *         (interaction). If transfer fails, the entire tx reverts.
     */
    function emergencyWithdraw()
        external
        nonReentrant
        whenPaused
    {
        uint256 balance = escrowBalance[msg.sender];
        require(balance > 0, "No funds to withdraw");

        // --- Effect (zero before transfer) ---
        escrowBalance[msg.sender] = 0;

        // --- Interaction ---
        require(
            usdc.transfer(msg.sender, balance),
            "USDC withdrawal failed"
        );

        emit EmergencyWithdrawal(msg.sender, balance);
    }
}
