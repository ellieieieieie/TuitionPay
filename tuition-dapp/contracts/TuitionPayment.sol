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
 *         Integrates Chainlink Price Feeds to provide a locked JPY/USD
 *         rate each semester, allowing students to see the JPY equivalent
 *         of their USDC fees. All payments are denominated in USDC.
 *
 *         Security: AccessControl (RBAC), ReentrancyGuard, Pausable,
 *         CEI pattern on all state-changing functions, bounded batch size.
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
    // CUSTOM ERRORS
    // ========================
    /// @dev Thrown when the Chainlink price feed has not updated recently enough
    error StalePriceFeed(uint256 currentTime, uint256 updatedAt, uint256 threshold);

    /// @dev Thrown when the Chainlink price feed returns a non-positive price
    error InvalidOraclePrice(int256 price);

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
    ///         Provides a consistent rate for all students to see the JPY
    ///         equivalent of their USDC fees on their fee statement.
    ///         Stored as uint256 since only positive rates are valid.
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
    event ExcessWithdrawn(address indexed student, uint256 amount);
    event Refund(address indexed student, uint256 amount);
    event UniversityWalletUpdated(address indexed oldWallet, address indexed newWallet);
    event FeePerUnitUpdated(uint256 oldFee, uint256 newFee);
    event PriceFeedUpdated(address indexed oldFeed, address indexed newFeed);
    event FxRateLocked(uint256 rate, uint256 timestamp);

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
     * @dev Reverts with a custom error if the feed has not been updated
     *      within STALENESS_THRESHOLD. Custom errors are cheaper than
     *      revert strings (~24 gas saved per deployment) and give the
     *      frontend structured data for user-friendly error messages.
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
        require(
            walletToStudentHash[student] == bytes32(0),
            "Wallet already registered"
        );

        _grantRole(STUDENT_ROLE, student);
        studentHashToWallet[studentHash] = student;
        walletToStudentHash[student] = studentHash;

        emit StudentWhitelisted(student, studentHash);
    }

    /**
     * @notice Batch-whitelist multiple students in a single transaction.
     *         Replicates the same validation logic as whitelistStudent()
     *         for each entry — zero-address, zero-hash, and duplicate-
     *         wallet checks included.
     *
     * @dev    Gas savings: pays the 21 000 base transaction gas only once
     *         instead of once per student. Uses calldata arrays (cheaper
     *         than memory) and unchecked loop increment. Bounded by
     *         MAX_BATCH_SIZE to prevent out-of-gas on large arrays.
     *
     * @param students      Array of student wallet addresses
     * @param studentHashes Parallel array of keccak256-hashed student IDs
     */
    function batchWhitelist(
        address[] calldata students,
        bytes32[] calldata studentHashes
    )
        external
        onlyRole(ADMIN_ROLE)
    {
        require(students.length == studentHashes.length, "Array length mismatch");
        require(students.length > 0, "Empty student array");
        require(students.length <= MAX_BATCH_SIZE, "Batch too large");

        for (uint256 i = 0; i < students.length; ) {
            address student = students[i];
            bytes32 studentHash = studentHashes[i];

            // Same validation as whitelistStudent() — no silent skips
            require(student != address(0), "Invalid student address");
            require(studentHash != bytes32(0), "Invalid student hash");
            require(
                studentHashToWallet[studentHash] == address(0),
                "Student hash already registered"
            );
            require(
                walletToStudentHash[student] == bytes32(0),
                "Wallet already registered"
            );

            _grantRole(STUDENT_ROLE, student);
            studentHashToWallet[studentHash] = student;
            walletToStudentHash[student] = studentHash;

            emit StudentWhitelisted(student, studentHash);

            unchecked { ++i; }
        }
    }

    /**
     * @notice Remove a student from the system entirely.
     *         Revokes STUDENT_ROLE, clears credit units, clears the
     *         hash-to-wallet mapping, and resets payment status.
     *
     * @dev    Requires escrow balance to be zero before removal. Admin
     *         must call refundStudent() first if the student has remaining
     *         funds. This prevents accidental fund-locking — once a
     *         student's role is revoked, they can no longer self-serve
     *         withdrawals, so we enforce the refund-first workflow.
     *
     * @param student Wallet address of the student to remove
     */
    function removeStudent(address student)
        external
        onlyRole(ADMIN_ROLE)
    {
        require(hasRole(STUDENT_ROLE, student), "Student not whitelisted");
        require(escrowBalance[student] == 0, "Refund student first");

        // Retrieve and clear the hash mapping (both directions)
        bytes32 studentHash = walletToStudentHash[student];
        if (studentHash != bytes32(0)) {
            delete studentHashToWallet[studentHash];
            delete walletToStudentHash[student];
        }

        // Revoke role, clear semester-specific data
        _revokeRole(STUDENT_ROLE, student);
        delete creditUnits[student];
        delete paymentCompleted[student];

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
        require(hasRole(STUDENT_ROLE, student), "Student not whitelisted");
        require(
            units >= MIN_CREDIT_UNITS && units <= MAX_CREDIT_UNITS,
            "Credit units out of range"
        );

        creditUnits[student] = units;
        emit CreditUnitsSet(student, units);
    }

    /**
     * @notice Batch-assign credit units to multiple whitelisted students
     *         in a single transaction. Useful at semester start when the
     *         admin needs to configure the entire cohort.
     *
     * @dev    Gas optimisation: instead of calling hasRole(STUDENT_ROLE, student)
     *         per element (~2 100 gas each for the AccessControl mapping SLOAD),
     *         we check walletToStudentHash[student] != bytes32(0) as a proxy.
     *         This mapping is only populated during whitelistStudent() /
     *         batchWhitelist() and cleared during removeStudent(), so it is
     *         always in sync with STUDENT_ROLE. The proxy check reads a
     *         mapping we already maintain (single SLOAD, same cost) but
     *         avoids the extra internal call overhead of hasRole().
     *
     *         If the admin passes a non-whitelisted address, the tx reverts
     *         with "Student not whitelisted" — same behaviour as before,
     *         just cheaper per iteration.
     *
     *         Uses calldata arrays, unchecked loop increment, and is bounded
     *         by MAX_BATCH_SIZE to prevent out-of-gas on large arrays.
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
        require(students.length == units.length, "Array length mismatch");
        require(students.length > 0, "Empty student array");
        require(students.length <= MAX_BATCH_SIZE, "Batch too large");

        for (uint256 i = 0; i < students.length; ) {
            address student = students[i];
            uint256 unitVal = units[i];

            // Proxy check: walletToStudentHash is only set for whitelisted
            // students, so a non-zero value guarantees STUDENT_ROLE.
            // Saves ~200 gas/iteration vs hasRole() internal call overhead.
            require(
                walletToStudentHash[student] != bytes32(0),
                "Student not whitelisted"
            );
            require(
                unitVal >= MIN_CREDIT_UNITS && unitVal <= MAX_CREDIT_UNITS,
                "Credit units out of range"
            );

            creditUnits[student] = unitVal;
            emit CreditUnitsSet(student, unitVal);

            unchecked { ++i; }
        }
    }

    /**
     * @notice Refund a student's full escrow balance without requiring
     *         the contract to be paused. Used when removing a student
     *         or correcting an overpayment.
     *
     * @dev    CEI pattern: zero the balance (effect) before transferring
     *         (interaction). Only callable by admin to prevent abuse.
     *         Unlike emergencyWithdraw(), this works while the contract
     *         is active — admin can refund individual students without
     *         disrupting the entire system.
     *
     * @param student Address of the student to refund
     */
    function refundStudent(address student)
        external
        onlyRole(ADMIN_ROLE)
        nonReentrant
    {
        uint256 balance = escrowBalance[student];
        require(balance > 0, "No funds to refund");

        // --- Effect (zero before transfer) ---
        escrowBalance[student] = 0;

        // --- Interaction ---
        require(
            usdc.transfer(student, balance),
            "USDC refund failed"
        );

        emit Refund(student, balance);
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
     *
     * @dev    Must be a JPY/USD feed (USD per 1 JPY, 8 decimals).
     *         Using a USD/JPY feed will invert calculateFeesInJPY().
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

    /**
     * @notice Lock the current Chainlink FX rate for the semester.
     *         All students see the same JPY equivalent on their fee
     *         statements. Can be re-locked if the admin needs to update.
     *
     * @dev    Reverts with StalePriceFeed or InvalidOraclePrice if the
     *         Chainlink feed is unhealthy. The frontend can catch these
     *         custom errors and display a user-friendly message (e.g.
     *         "Oracle is temporarily unavailable, try again later").
     */
    function lockFxRate() external onlyRole(ADMIN_ROLE) {
        (int256 price, ) = getLatestRate();
        // Safe cast: getLatestRate() already reverts if price <= 0
        uint256 rate = uint256(price);
        lockedFxRate = rate;
        emit FxRateLocked(rate, block.timestamp);
    }

    function pause() external onlyRole(ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }

    /**
     * @notice Reset a single student's payment status for a new semester.
     *         Allows the student to go through the deposit → pay cycle again.
     *
     * @param student Address of the student to reset
     */
    function resetPaymentStatus(address student)
        external
        onlyRole(ADMIN_ROLE)
    {
        require(hasRole(STUDENT_ROLE, student), "Student not whitelisted");
        require(paymentCompleted[student], "Payment not yet completed");

        paymentCompleted[student] = false;
        emit PaymentStatusReset(student);
    }

    /**
     * @notice Batch-reset payment status for multiple students at the
     *         start of a new semester. Silently skips students who have
     *         not paid (idempotent — safe to call with the full roster).
     *
     * @dev    Bounded by MAX_BATCH_SIZE. Uses unchecked increment.
     *         Each students[i] is cached into a local variable to
     *         avoid redundant calldata decoding on repeated access.
     *
     * @param students Array of student addresses to reset
     */
    function batchResetPayments(address[] calldata students)
        external
        onlyRole(ADMIN_ROLE)
    {
        require(students.length > 0, "Empty student array");
        require(students.length <= MAX_BATCH_SIZE, "Batch too large");

        for (uint256 i = 0; i < students.length; ) {
            address student = students[i];

            if (paymentCompleted[student]) {
                paymentCompleted[student] = false;
                emit PaymentStatusReset(student);
            }

            unchecked { ++i; }
        }
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
     *      - Students with 0 credit units are skipped to avoid a no-op
     *        transfer that would waste gas and falsely set paymentCompleted
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

        // Use the locked FX rate (set by admin for this semester)
        uint256 fxRate = lockedFxRate;
        require(fxRate > 0, "FX rate not locked");

        // Cache storage variable to save gas (avoid repeated SLOAD)
        uint256 _feePerUnit = feePerUnit;
        address _universityWallet = universityWallet;

        for (uint256 i = 0; i < students.length; ) {
            address student = students[i];
            uint256 required = creditUnits[student] * _feePerUnit;
            uint256 balance  = escrowBalance[student];

            if (required == 0) {
                // Credit units not assigned — skip (no-op transfer would
                // waste gas and falsely mark the student as paid)
            } else if (balance >= required && !paymentCompleted[student]) {
                // --- Effect (before interaction) ---
                escrowBalance[student] = balance - required;
                paymentCompleted[student] = true;

                // --- Interaction ---
                require(
                    usdc.transfer(_universityWallet, required),
                    "USDC transfer to university failed"
                );

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
     * @notice Withdraw any USDC deposited above the student's total fees.
     *         Allows students to self-serve recover overpayments without
     *         admin intervention or contract pausing.
     *
     * @dev    CEI pattern: reduce escrow balance (effect) before transfer
     *         (interaction). Only the excess above calculateFees() is
     *         withdrawable — the student cannot pull funds below the
     *         amount owed. If payment has already been completed this
     *         semester, the full remaining balance is considered excess.
     *
     *         Requires credit units to be assigned first. Without this
     *         guard, a student with 0 credit units would have owed = 0,
     *         making their entire deposit withdrawable — defeating the
     *         purpose of the escrow hold.
     *
     *         Example: student owes 1500 USDC, deposited 2000 USDC.
     *         withdrawExcess() sends 500 USDC back to the student.
     */
    function withdrawExcess()
        external
        onlyRole(STUDENT_ROLE)
        nonReentrant
        whenNotPaused
    {
        require(
            creditUnits[msg.sender] > 0 || paymentCompleted[msg.sender],
            "Credit units not assigned"
        );

        uint256 balance = escrowBalance[msg.sender];
        uint256 owed = paymentCompleted[msg.sender]
            ? 0
            : calculateFees(msg.sender);
        require(balance > owed, "No excess to withdraw");

        uint256 excess = balance - owed;

        // --- Effect (reduce balance before transfer) ---
        escrowBalance[msg.sender] = owed;

        // --- Interaction ---
        require(
            usdc.transfer(msg.sender, excess),
            "USDC withdrawal failed"
        );

        emit ExcessWithdrawn(msg.sender, excess);
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
     * @notice Convert a student's USDC fees to JPY using the locked FX rate.
     *         For frontend display — shows students how much JPY their
     *         tuition costs at the semester's locked rate.
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
     *           jpyAmount = usdcAmount / rate
     *         Adjusting for decimals (6 for USDC, 8 for feed):
     *           jpyAmount = (totalUsdc * 1e8) / (rate * 1e6)
     *
     *         Example: 1000 USDC (= 1_000_000_000 raw) at rate 670000:
     *           (1_000_000_000 * 1e8) / (670000 * 1e6) = 149,253 ≈ ¥149,253
     */
    function calculateFeesInJPY(address student) external view returns (uint256) {
        require(lockedFxRate > 0, "FX rate not locked");
        uint256 totalUsdc = creditUnits[student] * feePerUnit;
        return (totalUsdc * 1e8) / (lockedFxRate * 1e6);
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
     * @notice Return a student's combined status in a single call.
     *         Designed for frontend consumption — avoids multiple RPC
     *         round-trips to determine the student's lifecycle stage.
     *
     * @dev    View function — zero gas cost when called off-chain.
     *         Returns four values so the frontend can derive any
     *         combination of UI states without additional calls.
     *
     * @param student         Address of the student to query
     * @return isWhitelisted  True if the student holds STUDENT_ROLE
     * @return isDeposited    True if escrow balance >= total fees owed
     * @return isPaid         True if payment has been executed this semester
     * @return balance        Current escrow balance (USDC, 6 decimals)
     */
    function getStatus(address student)
        external
        view
        returns (
            bool isWhitelisted,
            bool isDeposited,
            bool isPaid,
            uint256 balance
        )
    {
        isWhitelisted = hasRole(STUDENT_ROLE, student);
        balance = escrowBalance[student];
        isDeposited = isWhitelisted && balance >= calculateFees(student);
        isPaid = paymentCompleted[student];
    }

    /**
     * @notice Return the total USDC held in this contract's escrow.
     *         Useful for admin dashboards to see aggregate escrow value.
     *
     * @dev    Queries the USDC ERC-20 balance (not native MATIC).
     *
     * @return Total USDC balance held by this contract (6 decimals)
     */
    function getContractBalance() external view returns (uint256) {
        return usdc.balanceOf(address(this));
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
