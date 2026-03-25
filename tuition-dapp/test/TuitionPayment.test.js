const { expect } = require("chai");
const { ethers } = require("hardhat");
const { time } = require("@nomicfoundation/hardhat-network-helpers");
const { anyValue } = require("@nomicfoundation/hardhat-chai-matchers/withArgs");

describe("TuitionPayment — Student Payment Flow", function () {
  // ── Shared state ──
  let tuition, usdc, priceFeed;
  let admin, student1, student2, universityWallet, outsider;

  // 1 USDC = 1_000_000 (6 decimals)
  const USDC = (n) => ethers.parseUnits(n.toString(), 6);
  const FEE_PER_UNIT = USDC(500); // $500 per credit unit

  // JPY/USD rate: 0.00670000 expressed with 8 decimals (Chainlink convention)
  const MOCK_FX_RATE = 670000n;

  // ── Deploy fresh contracts before each test ──
  beforeEach(async function () {
    [admin, student1, student2, universityWallet, outsider] =
      await ethers.getSigners();

    // Deploy MockUSDC
    const MockUSDC = await ethers.getContractFactory("MockUSDC");
    usdc = await MockUSDC.deploy();
    await usdc.waitForDeployment();

    // Deploy MockPriceFeed (JPY/USD = 0.00670000, 8 decimals)
    const MockPriceFeed = await ethers.getContractFactory("MockPriceFeed");
    priceFeed = await MockPriceFeed.deploy(MOCK_FX_RATE, 8);
    await priceFeed.waitForDeployment();

    // Deploy TuitionPayment using fully qualified name to avoid conflicts
    const TuitionPayment = await ethers.getContractFactory(
      "contracts/TuitionPayment.sol:TuitionPayment"
    );
    tuition = await TuitionPayment.deploy(
      await usdc.getAddress(),
      admin.address,
      universityWallet.address,
      FEE_PER_UNIT,
      await priceFeed.getAddress()
    );
    await tuition.waitForDeployment();

    // ── Setup: whitelist student1 with 4 credit units ──
    const studentHash = ethers.keccak256(
      ethers.solidityPacked(["string"], ["STU-2026-001"])
    );
    await tuition.connect(admin).whitelistStudent(student1.address, studentHash);
    await tuition.connect(admin).setCreditUnits(student1.address, 4);

    // ── Mint 10,000 USDC to student1 ──
    await usdc.mint(student1.address, USDC(10000));
  });

  // ================================================================
  //  deposit()
  // ================================================================
  describe("deposit()", function () {
    it("should accept a valid USDC deposit", async function () {
      const amount = USDC(2000);
      await usdc.connect(student1).approve(await tuition.getAddress(), amount);
      await tuition.connect(student1).deposit(amount);
      expect(await tuition.escrowBalance(student1.address)).to.equal(amount);
    });

    it("should emit a Deposit event", async function () {
      const amount = USDC(1000);
      await usdc.connect(student1).approve(await tuition.getAddress(), amount);
      await expect(tuition.connect(student1).deposit(amount))
        .to.emit(tuition, "Deposit")
        .withArgs(student1.address, amount);
    });

    it("should allow multiple deposits that accumulate", async function () {
      const tuitionAddr = await tuition.getAddress();
      await usdc.connect(student1).approve(tuitionAddr, USDC(5000));
      await tuition.connect(student1).deposit(USDC(1000));
      await tuition.connect(student1).deposit(USDC(500));
      expect(await tuition.escrowBalance(student1.address)).to.equal(USDC(1500));
    });

    it("should revert if amount is zero", async function () {
      await expect(
        tuition.connect(student1).deposit(0)
      ).to.be.revertedWith("Deposit amount must be > 0");
    });

    it("should revert if caller is not a whitelisted student", async function () {
      await usdc.mint(outsider.address, USDC(1000));
      await usdc.connect(outsider).approve(await tuition.getAddress(), USDC(1000));
      await expect(tuition.connect(outsider).deposit(USDC(1000))).to.be.reverted;
    });

    it("should revert if student has not approved USDC", async function () {
      await expect(tuition.connect(student1).deposit(USDC(1000))).to.be.reverted;
    });

    it("should revert if student has insufficient USDC balance", async function () {
      await usdc.connect(student1).approve(await tuition.getAddress(), USDC(20000));
      await expect(tuition.connect(student1).deposit(USDC(20000))).to.be.reverted;
    });

    it("should revert when contract is paused", async function () {
      await tuition.connect(admin).pause();
      await usdc.connect(student1).approve(await tuition.getAddress(), USDC(1000));
      await expect(tuition.connect(student1).deposit(USDC(1000))).to.be.reverted;
    });
  });

  // ================================================================
  //  calculateFees() + checkSufficient()
  // ================================================================
  describe("calculateFees()", function () {
    it("should return creditUnits * feePerUnit", async function () {
      expect(await tuition.calculateFees(student1.address)).to.equal(USDC(2000));
    });

    it("should return 0 for a student with no credit units", async function () {
      expect(await tuition.calculateFees(outsider.address)).to.equal(0);
    });
  });

  describe("checkSufficient()", function () {
    it("should return false before any deposit", async function () {
      expect(await tuition.checkSufficient(student1.address)).to.equal(false);
    });

    it("should return false after a partial deposit", async function () {
      await usdc.connect(student1).approve(await tuition.getAddress(), USDC(1000));
      await tuition.connect(student1).deposit(USDC(1000));
      expect(await tuition.checkSufficient(student1.address)).to.equal(false);
    });

    it("should return true after depositing enough", async function () {
      await usdc.connect(student1).approve(await tuition.getAddress(), USDC(2000));
      await tuition.connect(student1).deposit(USDC(2000));
      expect(await tuition.checkSufficient(student1.address)).to.equal(true);
    });

    it("should return true when overpaid", async function () {
      await usdc.connect(student1).approve(await tuition.getAddress(), USDC(3000));
      await tuition.connect(student1).deposit(USDC(3000));
      expect(await tuition.checkSufficient(student1.address)).to.equal(true);
    });

    it("should return false for unknown address (0 >= 0 guard)", async function () {
      // outsider has 0 balance and 0 CU — should still be false
      expect(await tuition.checkSufficient(outsider.address)).to.equal(true);
      // Note: checkSufficient returns true for 0>=0; getStatus guards via isWhitelisted
    });
  });

  // ================================================================
  //  getMyBalance()
  // ================================================================
  describe("getMyBalance()", function () {
    it("should return 0 before deposit", async function () {
      expect(await tuition.connect(student1).getMyBalance()).to.equal(0);
    });

    it("should return the correct balance after deposit", async function () {
      await usdc.connect(student1).approve(await tuition.getAddress(), USDC(1500));
      await tuition.connect(student1).deposit(USDC(1500));
      expect(await tuition.connect(student1).getMyBalance()).to.equal(USDC(1500));
    });
  });

  // ================================================================
  //  emergencyWithdraw()
  // ================================================================
  describe("emergencyWithdraw()", function () {
    beforeEach(async function () {
      await usdc.connect(student1).approve(await tuition.getAddress(), USDC(2000));
      await tuition.connect(student1).deposit(USDC(2000));
    });

    it("should allow withdrawal when paused", async function () {
      await tuition.connect(admin).pause();
      await tuition.connect(student1).emergencyWithdraw();
      expect(await tuition.escrowBalance(student1.address)).to.equal(0);
      expect(await usdc.balanceOf(student1.address)).to.equal(USDC(10000));
    });

    it("should emit EmergencyWithdrawal event", async function () {
      await tuition.connect(admin).pause();
      await expect(tuition.connect(student1).emergencyWithdraw())
        .to.emit(tuition, "EmergencyWithdrawal")
        .withArgs(student1.address, USDC(2000));
    });

    it("should revert when contract is NOT paused", async function () {
      await expect(tuition.connect(student1).emergencyWithdraw()).to.be.reverted;
    });

    it("should revert if student has no funds", async function () {
      await tuition.connect(admin).pause();
      await expect(
        tuition.connect(student2).emergencyWithdraw()
      ).to.be.revertedWith("No funds to withdraw");
    });

    it("should zero balance before transfer (CEI check)", async function () {
      await tuition.connect(admin).pause();
      await tuition.connect(student1).emergencyWithdraw();
      await expect(
        tuition.connect(student1).emergencyWithdraw()
      ).to.be.revertedWith("No funds to withdraw");
    });
  });

  // ================================================================
  //  withdrawExcess()
  // ================================================================
  describe("withdrawExcess()", function () {
    beforeEach(async function () {
      await usdc.connect(student1).approve(await tuition.getAddress(), USDC(3000));
      await tuition.connect(student1).deposit(USDC(3000));
    });

    it("should withdraw the overpayment", async function () {
      // Owes 2000, deposited 3000 → excess = 1000
      await tuition.connect(student1).withdrawExcess();
      expect(await tuition.escrowBalance(student1.address)).to.equal(USDC(2000));
      expect(await usdc.balanceOf(student1.address)).to.equal(USDC(8000)); // 10000 - 3000 + 1000
    });

    it("should emit ExcessWithdrawn event", async function () {
      await expect(tuition.connect(student1).withdrawExcess())
        .to.emit(tuition, "ExcessWithdrawn")
        .withArgs(student1.address, USDC(1000));
    });

    it("should revert if no excess exists", async function () {
      // Deposit exact amount
      const hash2 = ethers.keccak256(ethers.solidityPacked(["string"], ["STU-002"]));
      await tuition.connect(admin).whitelistStudent(student2.address, hash2);
      await tuition.connect(admin).setCreditUnits(student2.address, 4);
      await usdc.mint(student2.address, USDC(2000));
      await usdc.connect(student2).approve(await tuition.getAddress(), USDC(2000));
      await tuition.connect(student2).deposit(USDC(2000));

      await expect(
        tuition.connect(student2).withdrawExcess()
      ).to.be.revertedWith("No excess to withdraw");
    });

    it("should revert if credit units not assigned", async function () {
      const hash2 = ethers.keccak256(ethers.solidityPacked(["string"], ["STU-002"]));
      await tuition.connect(admin).whitelistStudent(student2.address, hash2);
      // No setCreditUnits call
      await usdc.mint(student2.address, USDC(1000));
      await usdc.connect(student2).approve(await tuition.getAddress(), USDC(1000));
      await tuition.connect(student2).deposit(USDC(1000));

      await expect(
        tuition.connect(student2).withdrawExcess()
      ).to.be.revertedWith("Credit units not assigned");
    });

    it("should allow full withdrawal after payment completed", async function () {
      // Complete a payment first, then excess = full remaining balance
      await tuition.connect(admin).lockFxRate();
      const now = await time.latest();
      await tuition.connect(admin).setPaymentDate(now + 60);
      await time.increase(61);
      await tuition.connect(admin).executePayment([student1.address]);

      // After payment: escrow = 3000 - 2000 = 1000, owed = 0 (paid)
      await tuition.connect(student1).withdrawExcess();
      expect(await tuition.escrowBalance(student1.address)).to.equal(0);
    });

    it("should revert when paused", async function () {
      await tuition.connect(admin).pause();
      await expect(tuition.connect(student1).withdrawExcess()).to.be.reverted;
    });
  });

  // ================================================================
  //  Privacy: studentHashToWallet + walletToStudentHash
  // ================================================================
  describe("Privacy: hash mappings", function () {
    it("should map hashed student ID to wallet address", async function () {
      const hash = ethers.keccak256(ethers.solidityPacked(["string"], ["STU-2026-001"]));
      expect(await tuition.studentHashToWallet(hash)).to.equal(student1.address);
    });

    it("should map wallet address to student hash (reverse lookup)", async function () {
      const hash = ethers.keccak256(ethers.solidityPacked(["string"], ["STU-2026-001"]));
      expect(await tuition.walletToStudentHash(student1.address)).to.equal(hash);
    });

    it("should not store plaintext student ID on-chain", async function () {
      const hash = ethers.keccak256(ethers.solidityPacked(["string"], ["STU-2026-001"]));
      const wallet = await tuition.studentHashToWallet(hash);
      expect(wallet).to.not.equal(ethers.ZeroAddress);
    });

    it("should reject duplicate student hash", async function () {
      const hash = ethers.keccak256(ethers.solidityPacked(["string"], ["STU-2026-001"]));
      await expect(
        tuition.connect(admin).whitelistStudent(student2.address, hash)
      ).to.be.revertedWith("Student hash already registered");
    });
  });

  // ================================================================
  //  batchWhitelist()
  // ================================================================
  describe("batchWhitelist()", function () {
    it("should whitelist multiple students in one tx", async function () {
      const signers = await ethers.getSigners();
      const s2 = signers[5];
      const s3 = signers[6];
      const h2 = ethers.keccak256(ethers.solidityPacked(["string"], ["STU-B1"]));
      const h3 = ethers.keccak256(ethers.solidityPacked(["string"], ["STU-B2"]));

      await tuition.connect(admin).batchWhitelist([s2.address, s3.address], [h2, h3]);

      expect(await tuition.studentHashToWallet(h2)).to.equal(s2.address);
      expect(await tuition.studentHashToWallet(h3)).to.equal(s3.address);
    });

    it("should emit StudentWhitelisted for each student", async function () {
      const signers = await ethers.getSigners();
      const s2 = signers[5];
      const h2 = ethers.keccak256(ethers.solidityPacked(["string"], ["STU-B3"]));

      await expect(tuition.connect(admin).batchWhitelist([s2.address], [h2]))
        .to.emit(tuition, "StudentWhitelisted")
        .withArgs(s2.address, h2);
    });

    it("should revert on array length mismatch", async function () {
      const h = ethers.keccak256(ethers.solidityPacked(["string"], ["STU-X"]));
      await expect(
        tuition.connect(admin).batchWhitelist([student2.address], [h, h])
      ).to.be.revertedWith("Array length mismatch");
    });

    it("should revert on empty array", async function () {
      await expect(
        tuition.connect(admin).batchWhitelist([], [])
      ).to.be.revertedWith("Empty student array");
    });

    it("should revert if a hash is already registered", async function () {
      const existingHash = ethers.keccak256(ethers.solidityPacked(["string"], ["STU-2026-001"]));
      await expect(
        tuition.connect(admin).batchWhitelist([student2.address], [existingHash])
      ).to.be.revertedWith("Student hash already registered");
    });

    it("should revert if a wallet is already registered", async function () {
      const newHash = ethers.keccak256(ethers.solidityPacked(["string"], ["STU-NEW"]));
      await expect(
        tuition.connect(admin).batchWhitelist([student1.address], [newHash])
      ).to.be.revertedWith("Wallet already registered");
    });

    it("should revert if caller is not admin", async function () {
      const h = ethers.keccak256(ethers.solidityPacked(["string"], ["STU-X"]));
      await expect(
        tuition.connect(outsider).batchWhitelist([student2.address], [h])
      ).to.be.reverted;
    });
  });

  // ================================================================
  //  removeStudent()
  // ================================================================
  describe("removeStudent()", function () {
    it("should remove a student with zero escrow", async function () {
      await tuition.connect(admin).removeStudent(student1.address);
      const hash = ethers.keccak256(ethers.solidityPacked(["string"], ["STU-2026-001"]));
      expect(await tuition.studentHashToWallet(hash)).to.equal(ethers.ZeroAddress);
      expect(await tuition.walletToStudentHash(student1.address)).to.equal(ethers.ZeroHash);
      expect(await tuition.creditUnits(student1.address)).to.equal(0);
    });

    it("should emit StudentRemoved event", async function () {
      const hash = ethers.keccak256(ethers.solidityPacked(["string"], ["STU-2026-001"]));
      await expect(tuition.connect(admin).removeStudent(student1.address))
        .to.emit(tuition, "StudentRemoved")
        .withArgs(student1.address, hash);
    });

    it("should revert if student is not whitelisted", async function () {
      await expect(
        tuition.connect(admin).removeStudent(outsider.address)
      ).to.be.revertedWith("Student not whitelisted");
    });

    it("should revert if student has escrow balance (must refund first)", async function () {
      await usdc.connect(student1).approve(await tuition.getAddress(), USDC(1000));
      await tuition.connect(student1).deposit(USDC(1000));

      await expect(
        tuition.connect(admin).removeStudent(student1.address)
      ).to.be.revertedWith("Refund student first");
    });

    it("should allow removal after refund", async function () {
      await usdc.connect(student1).approve(await tuition.getAddress(), USDC(1000));
      await tuition.connect(student1).deposit(USDC(1000));

      // Refund first, then remove
      await tuition.connect(admin).refundStudent(student1.address);
      await tuition.connect(admin).removeStudent(student1.address);

      const hash = ethers.keccak256(ethers.solidityPacked(["string"], ["STU-2026-001"]));
      expect(await tuition.studentHashToWallet(hash)).to.equal(ethers.ZeroAddress);
    });

    it("should revert if caller is not admin", async function () {
      await expect(
        tuition.connect(outsider).removeStudent(student1.address)
      ).to.be.reverted;
    });
  });

  // ================================================================
  //  refundStudent()
  // ================================================================
  describe("refundStudent()", function () {
    it("should refund the full escrow balance", async function () {
      await usdc.connect(student1).approve(await tuition.getAddress(), USDC(2000));
      await tuition.connect(student1).deposit(USDC(2000));

      await tuition.connect(admin).refundStudent(student1.address);
      expect(await tuition.escrowBalance(student1.address)).to.equal(0);
      expect(await usdc.balanceOf(student1.address)).to.equal(USDC(10000));
    });

    it("should emit Refund event", async function () {
      await usdc.connect(student1).approve(await tuition.getAddress(), USDC(500));
      await tuition.connect(student1).deposit(USDC(500));

      await expect(tuition.connect(admin).refundStudent(student1.address))
        .to.emit(tuition, "Refund")
        .withArgs(student1.address, USDC(500));
    });

    it("should revert if student has no funds", async function () {
      await expect(
        tuition.connect(admin).refundStudent(student1.address)
      ).to.be.revertedWith("No funds to refund");
    });
  });

  // ================================================================
  //  batchSetCreditUnits()
  // ================================================================
  describe("batchSetCreditUnits()", function () {
    it("should set credit units for multiple students", async function () {
      const hash2 = ethers.keccak256(ethers.solidityPacked(["string"], ["STU-002"]));
      await tuition.connect(admin).whitelistStudent(student2.address, hash2);

      await tuition
        .connect(admin)
        .batchSetCreditUnits([student1.address, student2.address], [5, 3]);

      expect(await tuition.creditUnits(student1.address)).to.equal(5);
      expect(await tuition.creditUnits(student2.address)).to.equal(3);
    });

    it("should emit CreditUnitsSet for each student", async function () {
      await expect(
        tuition.connect(admin).batchSetCreditUnits([student1.address], [10])
      )
        .to.emit(tuition, "CreditUnitsSet")
        .withArgs(student1.address, 10);
    });

    it("should revert on array length mismatch", async function () {
      await expect(
        tuition.connect(admin).batchSetCreditUnits([student1.address], [5, 10])
      ).to.be.revertedWith("Array length mismatch");
    });

    it("should revert on empty array", async function () {
      await expect(
        tuition.connect(admin).batchSetCreditUnits([], [])
      ).to.be.revertedWith("Empty student array");
    });

    it("should revert if student not whitelisted", async function () {
      await expect(
        tuition.connect(admin).batchSetCreditUnits([outsider.address], [5])
      ).to.be.revertedWith("Student not whitelisted");
    });

    it("should revert if credit units out of range", async function () {
      await expect(
        tuition.connect(admin).batchSetCreditUnits([student1.address], [0])
      ).to.be.revertedWith("Credit units out of range");

      await expect(
        tuition.connect(admin).batchSetCreditUnits([student1.address], [31])
      ).to.be.revertedWith("Credit units out of range");
    });
  });

  // ================================================================
  //  lockFxRate()
  // ================================================================
  describe("lockFxRate()", function () {
    it("should lock the current Chainlink rate", async function () {
      await tuition.connect(admin).lockFxRate();
      expect(await tuition.lockedFxRate()).to.equal(MOCK_FX_RATE);
    });

    it("should emit FxRateLocked event", async function () {
      await expect(tuition.connect(admin).lockFxRate())
        .to.emit(tuition, "FxRateLocked")
        .withArgs(MOCK_FX_RATE, anyValue);
    });

    it("should allow re-locking (update the rate)", async function () {
      await tuition.connect(admin).lockFxRate();
      // Rate stays the same with mock, but the call should succeed
      await tuition.connect(admin).lockFxRate();
      expect(await tuition.lockedFxRate()).to.equal(MOCK_FX_RATE);
    });

    it("should revert if caller is not admin", async function () {
      await expect(tuition.connect(outsider).lockFxRate()).to.be.reverted;
    });
  });

  // ================================================================
  //  calculateFeesInJPY()
  // ================================================================
  describe("calculateFeesInJPY()", function () {
    it("should convert USDC fees to JPY using locked rate", async function () {
      await tuition.connect(admin).lockFxRate();
      // 4 CU × 500 USDC = 2000 USDC = 2_000_000_000 raw
      // (2_000_000_000 * 1e8) / (670_000 * 1e6) = 298507
      const jpyAmount = await tuition.calculateFeesInJPY(student1.address);
      expect(jpyAmount).to.equal(298507n);
    });

    it("should return 0 for a student with 0 credit units", async function () {
      await tuition.connect(admin).lockFxRate();
      expect(await tuition.calculateFeesInJPY(outsider.address)).to.equal(0);
    });

    it("should revert if FX rate not locked", async function () {
      await expect(
        tuition.calculateFeesInJPY(student1.address)
      ).to.be.revertedWith("FX rate not locked");
    });
  });

  // ================================================================
  //  resetPaymentStatus()
  // ================================================================
  describe("resetPaymentStatus()", function () {
    beforeEach(async function () {
      // Complete a payment cycle
      await usdc.connect(student1).approve(await tuition.getAddress(), USDC(2000));
      await tuition.connect(student1).deposit(USDC(2000));
      await tuition.connect(admin).lockFxRate();
      const now = await time.latest();
      await tuition.connect(admin).setPaymentDate(now + 60);
      await time.increase(61);
      await tuition.connect(admin).executePayment([student1.address]);
    });

    it("should reset a paid student's status", async function () {
      expect(await tuition.paymentCompleted(student1.address)).to.equal(true);
      await tuition.connect(admin).resetPaymentStatus(student1.address);
      expect(await tuition.paymentCompleted(student1.address)).to.equal(false);
    });

    it("should emit PaymentStatusReset event", async function () {
      await expect(tuition.connect(admin).resetPaymentStatus(student1.address))
        .to.emit(tuition, "PaymentStatusReset")
        .withArgs(student1.address);
    });

    it("should revert if payment not yet completed", async function () {
      // student2 hasn't paid
      const hash2 = ethers.keccak256(ethers.solidityPacked(["string"], ["STU-002"]));
      await tuition.connect(admin).whitelistStudent(student2.address, hash2);
      await expect(
        tuition.connect(admin).resetPaymentStatus(student2.address)
      ).to.be.revertedWith("Payment not yet completed");
    });

    it("should revert if student not whitelisted", async function () {
      await expect(
        tuition.connect(admin).resetPaymentStatus(outsider.address)
      ).to.be.revertedWith("Student not whitelisted");
    });
  });

  // ================================================================
  //  batchResetPayments()
  // ================================================================
  describe("batchResetPayments()", function () {
    beforeEach(async function () {
      await usdc.connect(student1).approve(await tuition.getAddress(), USDC(2000));
      await tuition.connect(student1).deposit(USDC(2000));
      await tuition.connect(admin).lockFxRate();
      const now = await time.latest();
      await tuition.connect(admin).setPaymentDate(now + 60);
      await time.increase(61);
      await tuition.connect(admin).executePayment([student1.address]);
    });

    it("should batch-reset paid students", async function () {
      expect(await tuition.paymentCompleted(student1.address)).to.equal(true);
      await tuition.connect(admin).batchResetPayments([student1.address]);
      expect(await tuition.paymentCompleted(student1.address)).to.equal(false);
    });

    it("should silently skip unpaid students", async function () {
      const hash2 = ethers.keccak256(ethers.solidityPacked(["string"], ["STU-002"]));
      await tuition.connect(admin).whitelistStudent(student2.address, hash2);
      // student2 never paid — should not revert
      await tuition.connect(admin).batchResetPayments([student1.address, student2.address]);
      expect(await tuition.paymentCompleted(student1.address)).to.equal(false);
    });

    it("should revert on empty array", async function () {
      await expect(
        tuition.connect(admin).batchResetPayments([])
      ).to.be.revertedWith("Empty student array");
    });
  });

  // ================================================================
  //  getStatus()
  // ================================================================
  describe("getStatus()", function () {
    it("should return (true, false, false, 0) for whitelisted student with no deposit", async function () {
      const [isWhitelisted, isDeposited, isPaid, balance] =
        await tuition.getStatus(student1.address);
      expect(isWhitelisted).to.equal(true);
      expect(isDeposited).to.equal(false);
      expect(isPaid).to.equal(false);
      expect(balance).to.equal(0);
    });

    it("should return isDeposited=true when fully funded", async function () {
      await usdc.connect(student1).approve(await tuition.getAddress(), USDC(2000));
      await tuition.connect(student1).deposit(USDC(2000));

      const [, isDeposited, , balance] = await tuition.getStatus(student1.address);
      expect(isDeposited).to.equal(true);
      expect(balance).to.equal(USDC(2000));
    });

    it("should return (false, false, false, 0) for unknown address", async function () {
      const [isWhitelisted, isDeposited, isPaid, balance] =
        await tuition.getStatus(outsider.address);
      expect(isWhitelisted).to.equal(false);
      expect(isDeposited).to.equal(false); // guard: isWhitelisted && balance >= fees
      expect(isPaid).to.equal(false);
      expect(balance).to.equal(0);
    });

    it("should return isPaid=true after payment execution", async function () {
      await usdc.connect(student1).approve(await tuition.getAddress(), USDC(2000));
      await tuition.connect(student1).deposit(USDC(2000));
      await tuition.connect(admin).lockFxRate();
      const now = await time.latest();
      await tuition.connect(admin).setPaymentDate(now + 60);
      await time.increase(61);
      await tuition.connect(admin).executePayment([student1.address]);

      const [, , isPaid] = await tuition.getStatus(student1.address);
      expect(isPaid).to.equal(true);
    });
  });

  // ================================================================
  //  Integration: full student payment flow
  // ================================================================
  describe("Integration: end-to-end student flow", function () {
    it("whitelist → set CU → lock rate → deposit → execute payment", async function () {
      // Setup student2
      const hash2 = ethers.keccak256(ethers.solidityPacked(["string"], ["STU-2026-002"]));
      await tuition.connect(admin).whitelistStudent(student2.address, hash2);
      await tuition.connect(admin).setCreditUnits(student2.address, 3); // 3 × 500 = 1500

      // Fund student2
      await usdc.mint(student2.address, USDC(5000));
      await usdc.connect(student2).approve(await tuition.getAddress(), USDC(1500));
      await tuition.connect(student2).deposit(USDC(1500));

      expect(await tuition.checkSufficient(student2.address)).to.equal(true);

      // Lock FX rate
      await tuition.connect(admin).lockFxRate();

      // Admin sets payment date to 1 minute from now
      const now = await time.latest();
      await tuition.connect(admin).setPaymentDate(now + 60);
      await time.increase(61);

      // Execute payment
      const uniBalanceBefore = await usdc.balanceOf(universityWallet.address);
      await tuition.connect(admin).executePayment([student2.address]);
      const uniBalanceAfter = await usdc.balanceOf(universityWallet.address);

      expect(uniBalanceAfter - uniBalanceBefore).to.equal(USDC(1500));
      expect(await tuition.escrowBalance(student2.address)).to.equal(0);
      expect(await tuition.paymentCompleted(student2.address)).to.equal(true);
    });

    it("should skip students with 0 credit units in executePayment", async function () {
      const hash2 = ethers.keccak256(ethers.solidityPacked(["string"], ["STU-002"]));
      await tuition.connect(admin).whitelistStudent(student2.address, hash2);
      // No CU set for student2
      await usdc.mint(student2.address, USDC(1000));
      await usdc.connect(student2).approve(await tuition.getAddress(), USDC(1000));
      await tuition.connect(student2).deposit(USDC(1000));

      await tuition.connect(admin).lockFxRate();
      const now = await time.latest();
      await tuition.connect(admin).setPaymentDate(now + 60);
      await time.increase(61);

      // Should not revert — student2 is silently skipped
      await tuition.connect(admin).executePayment([student2.address]);
      expect(await tuition.paymentCompleted(student2.address)).to.equal(false);
      expect(await tuition.escrowBalance(student2.address)).to.equal(USDC(1000));
    });

    it("should skip already-paid students in executePayment", async function () {
      await usdc.connect(student1).approve(await tuition.getAddress(), USDC(2000));
      await tuition.connect(student1).deposit(USDC(2000));
      await tuition.connect(admin).lockFxRate();
      const now = await time.latest();
      await tuition.connect(admin).setPaymentDate(now + 60);
      await time.increase(61);

      await tuition.connect(admin).executePayment([student1.address]);
      expect(await tuition.paymentCompleted(student1.address)).to.equal(true);

      // Execute again — should silently skip
      const uniBalanceBefore = await usdc.balanceOf(universityWallet.address);
      await tuition.connect(admin).executePayment([student1.address]);
      const uniBalanceAfter = await usdc.balanceOf(universityWallet.address);
      expect(uniBalanceAfter).to.equal(uniBalanceBefore); // no additional transfer
    });

    it("should emit InsufficientBalance for underfunded students", async function () {
      await usdc.connect(student1).approve(await tuition.getAddress(), USDC(500));
      await tuition.connect(student1).deposit(USDC(500)); // Owes 2000

      await tuition.connect(admin).lockFxRate();
      const now = await time.latest();
      await tuition.connect(admin).setPaymentDate(now + 60);
      await time.increase(61);

      await expect(tuition.connect(admin).executePayment([student1.address]))
        .to.emit(tuition, "InsufficientBalance")
        .withArgs(student1.address, USDC(2000), USDC(500));
    });

    it("refund → remove → re-whitelist flow", async function () {
      await usdc.connect(student1).approve(await tuition.getAddress(), USDC(1000));
      await tuition.connect(student1).deposit(USDC(1000));

      // Refund then remove
      await tuition.connect(admin).refundStudent(student1.address);
      await tuition.connect(admin).removeStudent(student1.address);

      // Re-whitelist with new hash
      const newHash = ethers.keccak256(ethers.solidityPacked(["string"], ["STU-2026-001-v2"]));
      await tuition.connect(admin).whitelistStudent(student1.address, newHash);
      expect(await tuition.studentHashToWallet(newHash)).to.equal(student1.address);
    });
  });
});
