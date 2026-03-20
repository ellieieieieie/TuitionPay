// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract TuitionPaymentV2 {

    // ─── Constants ─────────────────────────────────────────────
    // Status flags packed into uint8 (1 byte) — saves gas vs two bool mappings
    // 0 = not a student
    // 1 = whitelisted, not paid
    // 2 = whitelisted, paid
    uint8 private constant NOT_STUDENT = 0;
    uint8 private constant WHITELISTED  = 1;
    uint8 private constant PAID         = 2;

    // ─── State Variables ───────────────────────────────────────
    address public immutable admin;      // immutable = no storage read, baked into bytecode
    uint256 public tuitionAmount;

    // Single mapping: address → packed status (saves one full mapping vs original)
    mapping(address => uint8) private studentStatus;

    // bytes32 instead of string — fixed size, no dynamic allocation
    mapping(address => bytes32) private studentIDHash;

    // ─── Events ────────────────────────────────────────────────
    // No string in events — bytes32 is fixed size and much cheaper to emit
    event StudentWhitelisted(address indexed studentWallet, bytes32 studentID);
    event StudentRemoved(address indexed studentWallet);
    event TuitionPaid(address indexed studentWallet, uint256 amount);
    event FundsWithdrawn(uint256 amount);

    // ─── Constructor ───────────────────────────────────────────
    constructor(uint256 _tuitionAmount) {
        admin = msg.sender;
        tuitionAmount = _tuitionAmount;
    }

    // ─── Modifiers ─────────────────────────────────────────────
    modifier onlyAdmin() {
        require(msg.sender == admin, "Not admin");
        _;
    }

    // ─── Admin Functions ───────────────────────────────────────

    /**
     * @dev Whitelist a single student
     * @param _wallet Student wallet address
     * @param _studentID Student ID as bytes32 (convert off-chain before calling)
     */
    function whitelistStudent(address _wallet, bytes32 _studentID) external onlyAdmin {
        require(studentStatus[_wallet] == NOT_STUDENT, "Already listed");
        studentStatus[_wallet] = WHITELISTED;
        studentIDHash[_wallet] = _studentID;
        emit StudentWhitelisted(_wallet, _studentID);
    }

    /**
     * @dev Batch whitelist — most gas efficient for onboarding many students at once
     * Instead of N separate txns, pay base gas (21000) only ONCE
     */
    function batchWhitelist(
        address[] calldata _wallets,    // calldata not memory = cheaper
        bytes32[] calldata _studentIDs
    ) external onlyAdmin {
        require(_wallets.length == _studentIDs.length, "Length mismatch");
        
        uint256 len = _wallets.length;
        unchecked {                     // safe: i can never overflow uint256 for array loop
            for (uint256 i = 0; i < len; i++) {
                if (studentStatus[_wallets[i]] == NOT_STUDENT) {
                    studentStatus[_wallets[i]] = WHITELISTED;
                    studentIDHash[_wallets[i]] = _studentIDs[i];
                    emit StudentWhitelisted(_wallets[i], _studentIDs[i]);
                }
            }
        }
    }

    /**
     * @dev Remove student from whitelist
     */
    function removeStudent(address _wallet) external onlyAdmin {
        require(studentStatus[_wallet] != NOT_STUDENT, "Not listed");
        studentStatus[_wallet] = NOT_STUDENT;
        emit StudentRemoved(_wallet);
    }

    /**
     * @dev Reset payment status for new semester
     */
    function resetPaymentStatus(address _wallet) external onlyAdmin {
        require(studentStatus[_wallet] == PAID, "Not paid");
        studentStatus[_wallet] = WHITELISTED;
    }

    /**
     * @dev Batch reset — for new semester, reset all at once
     */
    function batchResetPayments(address[] calldata _wallets) external onlyAdmin {
        uint256 len = _wallets.length;
        unchecked {
            for (uint256 i = 0; i < len; i++) {
                if (studentStatus[_wallets[i]] == PAID) {
                    studentStatus[_wallets[i]] = WHITELISTED;
                }
            }
        }
    }

    function setTuitionAmount(uint256 _newAmount) external onlyAdmin {
        tuitionAmount = _newAmount;
    }

    function withdraw() external onlyAdmin {
        uint256 bal = address(this).balance;
        require(bal > 0, "Empty");
        payable(admin).transfer(bal);
        emit FundsWithdrawn(bal);
    }

    // ─── Student Functions ─────────────────────────────────────

    /**
     * @dev Student pays tuition — single storage read + write
     */
    function payTuition() external payable {
        // One storage read for both checks (status covers both whitelisted + paid)
        require(studentStatus[msg.sender] == WHITELISTED, "Not eligible");
        require(msg.value == tuitionAmount, "Wrong amount");

        // Single storage write — flips from WHITELISTED(1) to PAID(2)
        studentStatus[msg.sender] = PAID;

        emit TuitionPaid(msg.sender, msg.value);
    }

    // ─── View Functions (free — no gas) ────────────────────────

    function isWhitelisted(address _wallet) external view returns (bool) {
        return studentStatus[_wallet] >= WHITELISTED;
    }

    function hasPaid(address _wallet) external view returns (bool) {
        return studentStatus[_wallet] == PAID;
    }

    function getStatus(address _wallet) external view returns (uint8) {
        return studentStatus[_wallet]; // 0=none, 1=whitelisted, 2=paid
    }

    function getStudentID(address _wallet) external view returns (bytes32) {
        return studentIDHash[_wallet];
    }

    function getContractBalance() external view returns (uint256) {
        return address(this).balance;
    }
}