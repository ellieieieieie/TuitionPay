// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title TuitionPayment
 * @notice Escrow-based tuition payment system on Polygon PoS using USDC.
 *         Students deposit USDC into per-student escrow; admin executes
 *         batch payment to the university wallet on the due date.
 *
 *         This file contains ALL functions so the contract compiles as a
 *         single deployable unit. Student-facing logic (deposit, view,
 *         emergencyWithdraw) is by Zah + Ellie. Admin functions
 *         (whitelist, setCreditUnits, executePayment) are stubs for
 *         Hayden to flesh out.
 */
contract TuitionPayment is AccessControl, ReentrancyGuard, Pausable {

    // ========================
    // ROLES
    // ========================
    bytes32 public constant ADMIN_ROLE  = keccak256("ADMIN_ROLE");
    bytes32 public constant STUDENT_ROLE = keccak256("STUDENT_ROLE");

    // ========================
    // STATE
    // ========================
    IERC20  public immutable usdc;
    address public universityWallet;

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
    uint256 public constant MIN_CREDIT_UNITS = 1;
    uint256 public constant MAX_CREDIT_UNITS = 30;

    // ========================
    // EVENTS
    // ========================
    event StudentWhitelisted(address indexed student, bytes32 indexed studentHash);
    event CreditUnitsSet(address indexed student, uint256 units);
    event Deposit(address indexed student, uint256 amount);
    event PaymentExecuted(address indexed student, uint256 amount);
    event InsufficientBalance(address indexed student, uint256 required, uint256 actual);
    event PaymentDateSet(uint256 date);
    event EmergencyWithdrawal(address indexed student, uint256 amount);

    // ========================
    // CONSTRUCTOR
    // ========================
    constructor(
        address _usdc,
        address _admin,
        address _universityWallet,
        uint256 _feePerUnit
    ) {
        require(_usdc != address(0), "Invalid USDC address");
        require(_admin != address(0), "Invalid admin address");
        require(_universityWallet != address(0), "Invalid university wallet");
        require(_feePerUnit > 0, "Fee per unit must be > 0");

        usdc = IERC20(_usdc);
        universityWallet = _universityWallet;
        feePerUnit = _feePerUnit;

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ADMIN_ROLE, _admin);
    }

    // ================================================================
    //  ADMIN FUNCTIONS  (stubs — Hayden to expand)
    // ================================================================

    /**
     * @notice Whitelist a student and map their hashed ID to their wallet.
     * @param student   Wallet address of the student
     * @param studentHash  keccak256(abi.encodePacked(studentId)) — computed
     *                     off-chain so plaintext ID never touches the chain.
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
     */
    function setPaymentDate(uint256 _date)
        external
        onlyRole(ADMIN_ROLE)
    {
        require(_date > block.timestamp, "Date must be in the future");
        paymentDate = _date;
        emit PaymentDateSet(_date);
    }

    function pause() external onlyRole(ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }

    /**
     * @notice Execute batch payment for an array of students.
     *         Follows checks-effects-interactions per student.
     */
    function executePayment(address[] calldata students)
        external
        onlyRole(ADMIN_ROLE)
        nonReentrant
        whenNotPaused
    {
        require(block.timestamp >= paymentDate, "Payment date not reached");
        require(paymentDate > 0, "Payment date not set");

        for (uint256 i = 0; i < students.length; i++) {
            address student = students[i];
            uint256 required = calculateFees(student);
            uint256 balance  = escrowBalance[student];

            if (balance >= required) {
                // Effect first (CEI pattern)
                escrowBalance[student] -= required;
                // Interaction
                require(
                    usdc.transfer(universityWallet, required),
                    "USDC transfer to university failed"
                );
                emit PaymentExecuted(student, required);
            } else {
                emit InsufficientBalance(student, required, balance);
            }
        }
    }

    // ================================================================
    //  STUDENT FUNCTIONS  (Zah + Ellie — your scope)
    // ================================================================

    /**
     * @notice Deposit USDC into the student's escrow account.
     *         Student must first call usdc.approve(thisContract, amount).
     *
     * @dev    Uses transferFrom so the contract pulls USDC from the
     *         student's wallet. Balance is updated AFTER a successful
     *         transfer — this is safe because transferFrom will revert
     *         on failure (USDC follows the ERC-20 standard).
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

        // Interaction — pull USDC from student wallet
        require(
            usdc.transferFrom(msg.sender, address(this), amount),
            "USDC transfer failed"
        );

        // Effect — update escrow balance
        escrowBalance[msg.sender] += amount;

        emit Deposit(msg.sender, amount);
    }

    /**
     * @notice View the caller's escrow balance.
     */
    function getMyBalance() external view returns (uint256) {
        return escrowBalance[msg.sender];
    }

    /**
     * @notice Calculate total fees owed by a student.
     * @param student  Address of the student
     * @return Total USDC owed (creditUnits × feePerUnit)
     */
    function calculateFees(address student) public view returns (uint256) {
        return creditUnits[student] * feePerUnit;
    }

    /**
     * @notice Check whether a student has deposited enough to cover fees.
     * @param student  Address of the student
     * @return True if escrow balance >= total fees
     */
    function checkSufficient(address student) public view returns (bool) {
        return escrowBalance[student] >= calculateFees(student);
    }

    /**
     * @notice Emergency withdrawal — student can reclaim their full escrow
     *         balance, but ONLY when the contract is paused (oracle failure,
     *         stablecoin depeg, detected exploit).
     *
     * @dev    Follows CEI strictly: zero the balance before transferring.
     */
    function emergencyWithdraw()
        external
        nonReentrant
        whenPaused
    {
        uint256 balance = escrowBalance[msg.sender];
        require(balance > 0, "No funds to withdraw");

        // Effect — zero before transfer
        escrowBalance[msg.sender] = 0;

        // Interaction
        require(
            usdc.transfer(msg.sender, balance),
            "USDC withdrawal failed"
        );

        emit EmergencyWithdrawal(msg.sender, balance);
    }
}
