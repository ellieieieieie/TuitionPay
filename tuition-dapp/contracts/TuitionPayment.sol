// S// SPDX-License-Identifier: MIT
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
 *         Integrates Chainlink Price Feeds to provide a locked JPY/USD
 *         rate each semester, allowing students to see the JPY equivalent
 *         of their USDC fees. All payments are denominated in USDC.
 *
 *         Security: AccessControl (RBAC), ReentrancyGuard, Pausable,
 *         CEI pattern on all state-changing functions, bounded batch size,
 *         deposit rate limiting, deposit cap, oracle staleness check.
 *
 * @dev    All monetary values use USDC's 6-decimal representation.
 *         Chainlink FX feeds return 8-decimal values.
 *
 *         FX feed direction: This contract expects a JPY/USD feed
 *         (i.e. "how many USD per 1 JPY"). Chainlink's JPY/USD feed
 *         on Polygon returns values like 670000 (= 0.00670000 USD/JPY
 *         at 8 decimals). Do NOT use a USD/JPY feed — the conversion
 *         math in calculateFeesInJPY() would be inverted.
 */
contract TuitionPayment is AccessControl, ReentrancyGuard, Pausable {

    // ========================
    // ROLES
    // ========================
    bytes32 public constant ADMIN_ROLE   = keccak256("ADMIN_ROLE");
    bytes32 public constant STUDENT_ROLE = keccak256("STUDENT_ROLE");

    // ========================
    // CUSTOM ERRORS (gas-efficient, structured data for frontend)
    // ========================
    error StalePriceFeed(uint256 currentTime, uint256 updatedAt, uint256 threshold);
    error InvalidOraclePrice(int256 price);
    error DepositCooldownActive(address student, uint256 nextAllowedTime);
    error DepositExceedsFees(address student, uint256 newBalance, uint256 maxAllowed);
    error ZeroAddress();
    error ZeroHash();
    error HashAlreadyRegistered(bytes32 studentHash);
    error WalletAlreadyRegistered(address student);
    error StudentNotWhitelisted(address student);
    error CreditUnitsOutOfRange(uint256 units);
    error EmptyArray();
    error ArrayLengthMismatch();
    error BatchTooLarge(uint256 size);
    error ZeroAmount();
    error NoFundsAvailable(address student);
    error FxRateNotLocked();
    error PaymentDateNotSet();
    error PaymentDateNotReached(uint256 paymentDate, uint256 currentTime);
    error PaymentDateMustBeFuture();
    error FeesMustBePositive();
    error PaymentsAlreadyExecuted();
    error TransferFailed();

    // ========================
    // STATE
    // ========================
    IERC20  public immutable usdc;
    address public universityWallet;

    /// @notice Chainlink price feed — must be a JPY/USD feed (USD per 1 JPY)
    AggregatorV3Interface public priceFeed;

    /// @notice Per-student escrow balance (USDC, 6 decimals)
    mapping(address => uint256) public escrowBalance;

    /// @notice Credit units assigned to each student by admin
    mapping(address => uint256) public creditUnits;

    /// @notice Fee per credit unit in USDC (6 decimals)
    uint256 public feePerUnit;

    /// @notice Timestamp when payment will be pulled from escrow
    uint256 public paymentDate;

    /// @notice JPY/USD rate (8 decimals) locked by admin for the semester.
    ///         Stored as uint256 (the oracle staleness check in getLatestRate
    ///         guarantees the raw int256 value is positive before casting).
    uint256 public lockedFxRate;

    /// @notice Privacy layer: hashed student ID -> wallet address
    ///         Keeps plaintext student IDs off-chain only.
    mapping(bytes32 => address) public studentHashToWallet;

    /// @notice Reverse lookup: wallet address -> student hash
    ///         Required for cleanup when removing a student.
    mapping(address => bytes32) public walletToStudentHash;

    /// @notice Tracks whether a student's tuition has been paid for the
    ///         current semester. Set to true inside executePayment(),
    ///         reset by admin at the start of each new semester.
    mapping(address => bool) public paymentCompleted;

    /// @notice Rate limiting: tracks the last deposit timestamp per student.
    ///         Prevents deposit spam by enforcing a minimum cooldown period
    ///         between successive deposits from the same wallet.
    mapping(address => uint256) public lastDepositTime;

    /// @notice Tracks whether executePayment has been called this semester.
    ///         Used to guard setPaymentDate against post-execution changes.
    bool public paymentsExecutedThisSemester;

    // ========================
    // CONSTANTS / BOUNDS
    // ========================
    uint256 public constant MIN_CREDIT_UNITS    = 1;
    uint256 public constant MAX_CREDIT_UNITS    = 30;
    uint256 public constant MAX_BATCH_SIZE      = 50;
    uint256 public constant STALENESS_THRESHOLD = 1 hours;

    /// @notice Minimum time (in seconds) a student must wait between
    ///         successive deposit() calls. Prevents transaction spam.
    ///
    /// @dev    Set to 1 minute for the demo/POC. In production, this could
    ///         be adjusted based on operational needs — tuition deposits are
    ///         infrequent by nature, so even a longer cooldown (e.g. 10 min)
    ///         would not impact legitimate usage.
    uint256 public constant DEPOSIT_COOLDOWN = 1 minutes;

    // ========================
    // EVENTS
    // ========================
    event StudentWhitelisted(address indexed student, bytes32 indexed studentHash);
    event StudentRemoved(address indexed student, bytes32 indexed studentHash);
    event CreditUnitsSet(address indexed student, uint256 units);
    event Deposit(address indexed student, uint256 amount);
    event PaymentExecuted(
        address indexed student,
        uint256 amount,
        uint256 fxRate,
        uint256 timestamp
    );
    event InsufficientBalance(address indexed student, uint256 required, uint256 actual);
    event PaymentDateSet(uint256 date);
    event PaymentStatusReset(address indexed student);
    event EmergencyWithdrawal(address indexed student, uint256 amount);
    event Refund(address indexed student, uint256 amount);
    event UniversityWalletUpdated(address indexed oldWallet, address indexed newWallet);
    event FeePerUnitUpdated(uint256 oldFee, uint256 newFee);
    event PriceFeedUpdated(address indexed oldFeed, address indexed newFeed);
    event FxRateLocked(uint256 rate, uint256 timestamp);
    event FxRateReset(uint256 previousRate);

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
        if (_usdc == address(0))             revert ZeroAddress();
        if (_admin == address(0))            revert ZeroAddress();
        if (_universityWallet == address(0)) revert ZeroAddress();
        if (_feePerUnit == 0)                revert FeesMustBePositive();
        if (_priceFeed == address(0))        revert ZeroAddress();

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
     *
     * @return price     The latest price (8 decimals for FX feeds)
     * @return updatedAt Timestamp of the last update
     *
     * @dev Reverts with a custom error if the feed has not been updated
     *      within STALENESS_THRESHOLD or returns a non-positive value.
     *
     *      Expected feed: JPY/USD (returns USD per 1 JPY, 8 decimals).
     */
    function getLatestRate()
        public
        view
        returns (int256 price, uint256 updatedAt)
    {
        (, price, , updatedAt, ) = priceFeed.latestRoundData();

        if (price <= 0) {
            revert InvalidOraclePrice(price);
        }
        if (block.timestamp - updatedAt >= STALENESS_THRESHOLD) {
            revert StalePriceFeed(block.timestamp, updatedAt, STALENESS_THRESHOLD);
        }
    }

    // ================================================================
    //  ADMIN FUNCTIONS
    // ================================================================

    /**
     * @notice Whitelist a student and map their hashed ID to their wallet.
     * @param student     Wallet address of the student
     * @param studentHash keccak256(abi.encodePacked(studentId)) — computed
     *                    off-chain so plaintext ID never touches the chain.
     *
     * @dev    Guards against both duplicate hash AND duplicate wallet.
     *         Without the wallet check, calling whitelistStudent(alice, hashB)
     *         after whitelistStudent(alice, hashA) would orphan hashA in the
     *         studentHashToWallet mapping.
     */
    function whitelistStudent(address student, bytes32 studentHash)
        external
        onlyRole(ADMIN_ROLE)
    {
        if (student == address(0))                          revert ZeroAddress();
        if (studentHash == bytes32(0))                      revert ZeroHash();
        if (studentHashToWallet[studentHash] != address(0)) revert HashAlreadyRegistered(studentHash);
        if (walletToStudentHash[student] != bytes32(0))     revert WalletAlreadyRegistered(student);

        _grantRole(STUDENT_ROLE, student);
        studentHashToWallet[studentHash] = student;
        walletToStudentHash[student] = studentHash;

        emit StudentWhitelisted(student, studentHash);
    }

    /**
     * @notice Batch-whitelist multiple students in a single transaction.
     *
     * @dev    Gas savings: pays the 21 000 base transaction gas only once.
     *         Uses calldata arrays and unchecked loop increment. Bounded
     *         by MAX_BATCH_SIZE. Includes both hash and wallet duplicate guards.
     *
     * @param students Array of student wallet addresses
     * @param hashes   Parallel array of keccak256 hashes of student IDs
     */
    function batchWhitelist(
        address[] calldata students,
        bytes32[] calldata hashes
    )
        external
        onlyRole(ADMIN_ROLE)
    {
        if (students.length != hashes.length) revert ArrayLengthMismatch();
        if (students.length == 0)             revert EmptyArray();
        if (students.length > MAX_BATCH_SIZE) revert BatchTooLarge(students.length);

        for (uint256 i = 0; i < students.length; ) {
            address student = students[i];
            bytes32 studentHash = hashes[i];

            if (student == address(0))                          revert ZeroAddress();
            if (studentHash == bytes32(0))                      revert ZeroHash();
            if (studentHashToWallet[studentHash] != address(0)) revert HashAlreadyRegistered(studentHash);
            if (walletToStudentHash[student] != bytes32(0))     revert WalletAlreadyRegistered(student);

            _grantRole(STUDENT_ROLE, student);
            studentHashToWallet[studentHash] = student;
            walletToStudentHash[student] = studentHash;

            emit StudentWhitelisted(student, studentHash);

            unchecked { ++i; }
        }
    }

    /**
     * @notice Remove a whitelisted student from the system.
     *         Revokes STUDENT_ROLE, clears credit units, payment status,
     *         hash mappings, and rate limiting state.
     *
     * @dev    Does NOT refund escrowed USDC — admin should call
     *         refundStudent() first if the student has a remaining
     *         escrow balance.
     *
     *         Also deletes lastDepositTime[student] to prevent stale
     *         cooldown state if the same wallet is re-whitelisted.
     *
     * @param student Wallet address of the student to remove
     */
    function removeStudent(address student)
        external
        onlyRole(ADMIN_ROLE)
    {
        if (!hasRole(STUDENT_ROLE, student)) revert StudentNotWhitelisted(student);

        // Retrieve and clear the hash mapping (both directions)
        bytes32 studentHash = walletToStudentHash[student];
        if (studentHash != bytes32(0)) {
            delete studentHashToWallet[studentHash];
            delete walletToStudentHash[student];
        }

        // Revoke role, clear ALL semester-specific and rate-limit data
        _revokeRole(STUDENT_ROLE, student);
        delete creditUnits[student];
        delete paymentCompleted[student];
        delete lastDepositTime[student];

        emit StudentRemoved(student, studentHash);
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
        if (!hasRole(STUDENT_ROLE, student)) revert StudentNotWhitelisted(student);
        if (units < MIN_CREDIT_UNITS || units > MAX_CREDIT_UNITS) {
            revert CreditUnitsOutOfRange(units);
        }

        creditUnits[student] = units;
        emit CreditUnitsSet(student, units);
    }

    /**
     * @notice Batch-assign credit units to multiple whitelisted students
     *         in a single transaction.
     *
     * @dev    Gas savings: pays the 21 000 base transaction gas only once.
     *         Uses calldata arrays and unchecked loop increment. Bounded
     *         by MAX_BATCH_SIZE.
     *
     * @param students Array of student wallet addresses
     * @param units    Parallel array of credit unit values (1–30 each)
     */
    function batchSetCreditUnits(
        address[] calldata students,
        uint256[] calldata units
    )
        external
        onlyRole(ADMIN_ROLE)
    {
        if (students.length != units.length) revert ArrayLengthMismatch();
        if (students.length == 0)            revert EmptyArray();
        if (students.length > MAX_BATCH_SIZE) revert BatchTooLarge(students.length);

        for (uint256 i = 0; i < students.length; ) {
            address student = students[i];
            uint256 unitVal = units[i];

            if (!hasRole(STUDENT_ROLE, student)) revert StudentNotWhitelisted(student);
            if (unitVal < MIN_CREDIT_UNITS || unitVal > MAX_CREDIT_UNITS) {
                revert CreditUnitsOutOfRange(unitVal);
            }

            creditUnits[student] = unitVal;
            emit CreditUnitsSet(student, unitVal);

            unchecked { ++i; }
        }
    }

    /**
     * @notice Refund a student's full escrow balance without requiring
     *         the contract to be paused.
     *
     * @dev    CEI pattern: zero the balance (effect) before transferring
     *         (interaction). Only callable by admin.
     *
     * @param student Address of the student to refund
     */
    function refundStudent(address student)
        external
        onlyRole(ADMIN_ROLE)
        nonReentrant
    {
        uint256 balance = escrowBalance[student];
        if (balance == 0) revert NoFundsAvailable(student);

        // --- Effect (zero before transfer) ---
        escrowBalance[student] = 0;

        // --- Interaction ---
        if (!usdc.transfer(student, balance)) revert TransferFailed();

        emit Refund(student, balance);
    }

    /**
     * @notice Set the date when batch payment will be executed.
     * @param _date Unix timestamp for the payment deadline (must be future)
     *
     * @dev    Reverts if payments have already been executed this semester.
     *         Admin must call batchResetPayments first to reset semester
     *         state before setting a new payment date.
     */
    function setPaymentDate(uint256 _date)
        external
        onlyRole(ADMIN_ROLE)
    {
        if (_date <= block.timestamp)     revert PaymentDateMustBeFuture();
        if (paymentsExecutedThisSemester) revert PaymentsAlreadyExecuted();

        paymentDate = _date;
        emit PaymentDateSet(_date);
    }

    /**
     * @notice Update the university receiving wallet.
     * @param _newWallet New university wallet address
     */
    function setUniversityWallet(address _newWallet)
        external
        onlyRole(ADMIN_ROLE)
    {
        if (_newWallet == address(0)) revert ZeroAddress();
        address oldWallet = universityWallet;
        universityWallet = _newWallet;
        emit UniversityWalletUpdated(oldWallet, _newWallet);
    }

    /**
     * @notice Update the fee charged per credit unit.
     * @param _newFee New fee in USDC (6 decimals, must be > 0)
     *
     * @dev    Reverts if payments have already been executed this semester.
     *         Changing feePerUnit mid-semester would shift the deposit cap
     *         (calculateFees) for all students — those who deposited to the
     *         old cap would be silently underfunded or over-capped. Admin
     *         should configure fees before the deposit window opens.
     */
    function setFeePerUnit(uint256 _newFee)
        external
        onlyRole(ADMIN_ROLE)
    {
        if (_newFee == 0) revert FeesMustBePositive();
        if (paymentsExecutedThisSemester) revert PaymentsAlreadyExecuted();
        uint256 oldFee = feePerUnit;
        feePerUnit = _newFee;
        emit FeePerUnitUpdated(oldFee, _newFee);
    }

    /**
     * @notice Update the Chainlink price feed address.
     *
     * @dev    IMPORTANT: The new feed MUST be a JPY/USD feed (USD per 1 JPY).
     *         Plugging in a USD/JPY feed will invert all conversion math.
     *
     * @param _newFeed Address of the new AggregatorV3Interface contract
     */
    function setPriceFeed(address _newFeed)
        external
        onlyRole(ADMIN_ROLE)
    {
        if (_newFeed == address(0)) revert ZeroAddress();
        address oldFeed = address(priceFeed);
        priceFeed = AggregatorV3Interface(_newFeed);
        emit PriceFeedUpdated(oldFeed, _newFeed);
    }

    /**
     * @notice Lock the current FX rate for the semester.
     *         Reads getLatestRate() (which includes staleness check),
     *         then stores the rate so all students see the same JPY
     *         equivalent on their fee statements.
     *
     * @dev    Called once per semester by admin, typically before the
     *         payment window opens. The rate is safely cast from int256
     *         to uint256 — getLatestRate() reverts if price <= 0,
     *         guaranteeing the cast is safe.
     */
    function lockFxRate()
        external
        onlyRole(ADMIN_ROLE)
    {
        (int256 rate, ) = getLatestRate();

        // Safe cast: getLatestRate() reverts if rate <= 0
        uint256 positiveRate = uint256(rate);
        lockedFxRate = positiveRate;
        emit FxRateLocked(positiveRate, block.timestamp);
    }

    /**
     * @notice Clear the locked FX rate between semesters.
     *         Prevents stale rates from being silently reused if admin
     *         forgets to re-lock before the next payment cycle.
     *
     * @dev    After calling this, calculateFeesInJPY() and executePayment()
     *         will revert until lockFxRate() is called again, which is the
     *         desired fail-safe behaviour.
     */
    function resetLockedFxRate()
        external
        onlyRole(ADMIN_ROLE)
    {
        uint256 previousRate = lockedFxRate;
        lockedFxRate = 0;
        emit FxRateReset(previousRate);
    }

    /**
     * @notice Reset payment status for a batch of students at the start
     *         of a new semester. Also resets the paymentsExecutedThisSemester
     *         flag so setPaymentDate can be called for the new semester.
     *
     * @dev    Bounded by MAX_BATCH_SIZE. Only writes + emits for students
     *         whose paymentCompleted is currently true, avoiding wasted
     *         SSTORE gas (~2,900 per no-op write) and misleading events
     *         for students who were never paid.
     *
     * @param students Array of student addresses to reset
     */
    function batchResetPayments(address[] calldata students)
        external
        onlyRole(ADMIN_ROLE)
    {
        if (students.length == 0)             revert EmptyArray();
        if (students.length > MAX_BATCH_SIZE) revert BatchTooLarge(students.length);

        for (uint256 i = 0; i < students.length; ) {
            address student = students[i];
            if (!hasRole(STUDENT_ROLE, student)) revert StudentNotWhitelisted(student);

            // Only write + emit if actually paid (avoids wasted SSTORE + misleading event)
            if (paymentCompleted[student]) {
                paymentCompleted[student] = false;
                emit PaymentStatusReset(student);
            }

            unchecked { ++i; }
        }

        // Reset semester flag so setPaymentDate can be called again
        paymentsExecutedThisSemester = false;
    }

    /**
     * @notice Execute batch tuition payment from student escrow to university.
     *         Follows CEI (Checks-Effects-Interactions) per student.
     *
     * @dev Gas optimisations applied:
     *      - Bounded batch size prevents out-of-gas on large arrays
     *      - feePerUnit cached in memory to avoid repeated SLOAD
     *      - Unchecked loop increment (cannot overflow with bounded size)
     *      - FX rate fetched once and recorded in each payment event
     *
     *      Skips students with 0 credit units (required == 0) to prevent
     *      marking them as "paid" and emitting a phantom PaymentExecuted
     *      event for 0 USDC.
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
        if (paymentDate == 0)                  revert PaymentDateNotSet();
        if (block.timestamp < paymentDate)     revert PaymentDateNotReached(paymentDate, block.timestamp);
        if (students.length == 0)              revert EmptyArray();
        if (students.length > MAX_BATCH_SIZE)  revert BatchTooLarge(students.length);

        // Use the locked FX rate (set by admin for this semester)
        uint256 fxRate = lockedFxRate;
        if (fxRate == 0) revert FxRateNotLocked();

        // Cache storage variables to save gas (avoid repeated SLOAD)
        uint256 _feePerUnit = feePerUnit;
        address _universityWallet = universityWallet;

        // Mark that payments have been executed this semester
        paymentsExecutedThisSemester = true;

        for (uint256 i = 0; i < students.length; ) {
            address student = students[i];
            uint256 required = creditUnits[student] * _feePerUnit;
            uint256 balance  = escrowBalance[student];

            // Skip students with 0 credit units (prevents phantom 0-USDC payments)
            if (required == 0) {
                unchecked { ++i; }
                continue;
            }

            if (balance >= required && !paymentCompleted[student]) {
                // --- Effect (before interaction) ---
                escrowBalance[student] = balance - required;
                paymentCompleted[student] = true;

                // --- Interaction ---
                if (!usdc.transfer(_universityWallet, required)) revert TransferFailed();

                emit PaymentExecuted(student, required, fxRate, block.timestamp);
            } else if (paymentCompleted[student]) {
                // Already paid this semester — skip silently
            } else {
                emit InsufficientBalance(student, required, balance);
            }

            // Gas-optimised increment: safe because i < students.length <= 50
            unchecked { ++i; }
        }
    }

    /**
     * @notice Pause the contract. Disables deposits and payment execution.
     *         Enables emergencyWithdraw() for students to reclaim funds.
     */
    function pause() external onlyRole(ADMIN_ROLE) {
        _pause();
    }

    /**
     * @notice Unpause the contract. Re-enables normal operations.
     */
    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }

    // ================================================================
    //  STUDENT FUNCTIONS
    // ================================================================

    /**
     * @notice Deposit USDC into the student's escrow account.
     *         Student must first call usdc.approve(thisContract, amount).
     *
     * @dev    CEI pattern: update escrow balance (effect) BEFORE calling
     *         transferFrom (interaction).
     *
     *         Rate limiting: enforces DEPOSIT_COOLDOWN between successive
     *         deposits from the same wallet. Uses a custom error
     *         (DepositCooldownActive) to return the exact timestamp when
     *         the next deposit is allowed, enabling the frontend to display
     *         a countdown timer.
     *
     *         Deposit cap: the student's new escrow balance after deposit
     *         cannot exceed their calculated fees (creditUnits * feePerUnit).
     *         Prevents accidental over-deposits from a compromised key or
     *         frontend bug. Students who need to deposit the exact amount
     *         can call calculateFees() first to check.
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
        if (amount == 0) revert ZeroAmount();

        // --- Rate limiting check ---
        uint256 nextAllowed = lastDepositTime[msg.sender] + DEPOSIT_COOLDOWN;
        if (block.timestamp < nextAllowed) {
            revert DepositCooldownActive(msg.sender, nextAllowed);
        }

        // --- Deposit cap check ---
        uint256 maxAllowed = calculateFees(msg.sender);
        uint256 newBalance = escrowBalance[msg.sender] + amount;
        if (newBalance > maxAllowed) {
            revert DepositExceedsFees(msg.sender, newBalance, maxAllowed);
        }

        // --- Effects (update state before external call) ---
        lastDepositTime[msg.sender] = block.timestamp;
        escrowBalance[msg.sender] = newBalance;

        // --- Interaction (pull USDC from student wallet) ---
        if (!usdc.transferFrom(msg.sender, address(this), amount)) revert TransferFailed();

        emit Deposit(msg.sender, amount);
    }

    // ================================================================
    //  VIEW FUNCTIONS
    // ================================================================

    /**
     * @notice Calculate total fees owed by a student.
     * @param student  Address of the student
     * @return Total USDC owed (creditUnits * feePerUnit)
     */
    function calculateFees(address student) public view returns (uint256) {
        return creditUnits[student] * feePerUnit;
    }

    /**
     * @notice Convert a student's USDC fees to JPY using the locked FX rate.
     *         For frontend display only.
     *
     * @param student  Address of the student
     * @return JPY equivalent (whole yen, e.g. 150000 = ¥150,000)
     *
     * @dev    USDC uses 6 decimals, Chainlink JPY/USD feed uses 8 decimals.
     *
     *         The feed returns "USD per 1 JPY". For example, if 1 JPY = 0.00670000 USD,
     *         the feed returns 670000 (at 8 decimals).
     *
     *         To convert USDC → JPY:
     *           jpyAmount = (totalUsdc * 1e8) / (rate * 1e6)
     *
     *         Example: 1000 USDC (= 1_000_000_000 raw) at rate 670000:
     *           (1_000_000_000 * 1e8) / (670000 * 1e6) = 149,253 ≈ ¥149,253
     */
    function calculateFeesInJPY(address student) external view returns (uint256) {
        if (lockedFxRate == 0) revert FxRateNotLocked();
        uint256 totalUsdc = creditUnits[student] * feePerUnit;
        return (totalUsdc * 1e8) / (lockedFxRate * 1e6);
    }

    /**
     * @notice Return a student's combined status in a single call.
     *         Designed for frontend consumption — avoids multiple RPC
     *         round-trips to determine the student's lifecycle stage.
     *
     * @param student              Address of the student to query
     * @return isWhitelisted       True if the student holds STUDENT_ROLE
     * @return isDeposited         True if escrow balance >= total fees owed
     * @return isPaid              True if payment has been executed this semester
     * @return balance             Current escrow balance (USDC, 6 decimals)
     * @return nextDepositAllowed  Timestamp when the student can next call deposit()
     */
    function getStatus(address student)
        external
        view
        returns (
            bool isWhitelisted,
            bool isDeposited,
            bool isPaid,
            uint256 balance,
            uint256 nextDepositAllowed
        )
    {
        isWhitelisted = hasRole(STUDENT_ROLE, student);
        balance = escrowBalance[student];
        isDeposited = isWhitelisted && balance >= calculateFees(student);
        isPaid = paymentCompleted[student];
        nextDepositAllowed = lastDepositTime[student] + DEPOSIT_COOLDOWN;
    }

    /**
     * @notice Emergency withdrawal — student can reclaim their full escrow
     *         balance, but ONLY when the contract is paused (oracle failure,
     *         stablecoin depeg, detected exploit).
     *
     * @dev    CEI pattern: zero the balance (effect) before transferring
     *         (interaction). If transfer fails, the entire tx reverts.
     *
     *         Note: emergencyWithdraw is NOT rate-limited. When the contract
     *         is paused, the priority is allowing students to recover funds
     *         as quickly as possible.
     */
    function emergencyWithdraw()
        external
        nonReentrant
        whenPaused
    {
        uint256 balance = escrowBalance[msg.sender];
        if (balance == 0) revert NoFundsAvailable(msg.sender);

        // --- Effect (zero before transfer) ---
        escrowBalance[msg.sender] = 0;

        // --- Interaction ---
        if (!usdc.transfer(msg.sender, balance)) revert TransferFailed();

        emit EmergencyWithdrawal(msg.sender, balance);
    }
}
