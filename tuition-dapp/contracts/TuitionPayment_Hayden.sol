// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract TuitionPayment {

    // ─── State Variables ───────────────────────────────────────
    address public admin;
    uint256 public tuitionAmount; // in wei (we'll use MATIC for POC)

    // Whitelist: wallet address → is student?
    mapping(address => bool) public whitelist;

    // Track if student has already paid this semester
    mapping(address => bool) public hasPaid;

    // Student info storage
    mapping(address => string) public studentID; // wallet → student ID string

    // ─── Events ────────────────────────────────────────────────
    event StudentWhitelisted(address indexed studentWallet, string studentID);
    event StudentRemovedFromWhitelist(address indexed studentWallet);
    event TuitionPaid(address indexed studentWallet, string studentID, uint256 amount, uint256 timestamp);
    event FundsWithdrawn(address indexed admin, uint256 amount);

    // ─── Modifiers ─────────────────────────────────────────────
    modifier onlyAdmin() {
        require(msg.sender == admin, "Only admin can call this");
        _;
    }

    modifier onlyWhitelisted() {
        require(whitelist[msg.sender], "You are not a registered student");
        _;
    }

    // ─── Constructor ───────────────────────────────────────────
    constructor(uint256 _tuitionAmountInWei) {
        admin = msg.sender; // deployer becomes admin
        tuitionAmount = _tuitionAmountInWei;
    }

    // ─── Admin Functions ───────────────────────────────────────

    // Add a student to whitelist
    function whitelistStudent(address _studentWallet, string memory _studentID) external onlyAdmin {
        require(!whitelist[_studentWallet], "Student already whitelisted");
        whitelist[_studentWallet] = true;
        studentID[_studentWallet] = _studentID;
        emit StudentWhitelisted(_studentWallet, _studentID);
    }

    // Remove a student (e.g. graduated or expelled)
    function removeStudent(address _studentWallet) external onlyAdmin {
        require(whitelist[_studentWallet], "Student not in whitelist");
        whitelist[_studentWallet] = false;
        emit StudentRemovedFromWhitelist(_studentWallet);
    }

    // Reset payment status (e.g. new semester)
    function resetPaymentStatus(address _studentWallet) external onlyAdmin {
        hasPaid[_studentWallet] = false;
    }

    // Update tuition amount
    function setTuitionAmount(uint256 _newAmount) external onlyAdmin {
        tuitionAmount = _newAmount;
    }

    // ─── Student Functions ─────────────────────────────────────

    // Student pays tuition
    function payTuition() external payable onlyWhitelisted {
        require(!hasPaid[msg.sender], "You have already paid this semester");
        require(msg.value == tuitionAmount, "Incorrect payment amount");

        hasPaid[msg.sender] = true;

        emit TuitionPaid(
            msg.sender,
            studentID[msg.sender],
            msg.value,
            block.timestamp
        );
    }

    // ─── View Functions ────────────────────────────────────────

    function isWhitelisted(address _wallet) external view returns (bool) {
        return whitelist[_wallet];
    }

    function checkPaymentStatus(address _wallet) external view returns (bool) {
        return hasPaid[_wallet];
    }

    function getContractBalance() external view returns (uint256) {
        return address(this).balance;
    }

    // ─── Admin Withdraw ────────────────────────────────────────
    function withdraw() external onlyAdmin {
        uint256 balance = address(this).balance;
        require(balance > 0, "Nothing to withdraw");
        payable(admin).transfer(balance);
        emit FundsWithdrawn(admin, balance);
    }
}