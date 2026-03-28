const { expect } = require("chai");
const { ethers } = require("hardhat");
const { time } = require("@nomicfoundation/hardhat-network-helpers");
const { anyValue } = require("@nomicfoundation/hardhat-chai-matchers/withArgs");

describe("TuitionPayment", function () {
  let tuition, usdc, priceFeed;
  let admin, student1, student2, universityWallet, outsider;

  const USDC        = (n) => ethers.parseUnits(n.toString(), 6);
  const FEE_PER_UNIT = USDC(500);       // $500 per credit unit
  const MOCK_FX_RATE = 670000n;         // 0.00670000 USD/JPY, 8 decimals

  // ── Deploy fresh contracts before each test ──────────────────────────
  beforeEach(async function () {
    [admin, student1, student2, universityWallet, outsider] = await ethers.getSigners();

    const MockUSDC = await ethers.getContractFactory("MockUSDC");
    usdc = await MockUSDC.deploy();
    await usdc.waitForDeployment();

    const MockPriceFeed = await ethers.getContractFactory("MockPriceFeed");
    priceFeed = await MockPriceFeed.deploy(MOCK_FX_RATE, 8);
    await priceFeed.waitForDeployment();

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

    // student1: whitelisted, 4 CU → fees = 2000 USDC (deposit cap)
    const studentHash = ethers.keccak256(ethers.solidityPacked(["string"], ["STU-2026-001"]));
    await tuition.connect(admin).whitelistStudent(student1.address, studentHash);
    await tuition.connect(admin).setCreditUnits(student1.address, 4);
    await usdc.mint(student1.address, USDC(10000));
  });

  // ================================================================
  //  deposit()
  // ================================================================
  describe("deposit()", function () {
    it("should accept a valid USDC deposit", async function () {
      await usdc.connect(student1).approve(await tuition.getAddress(), USDC(1000));
      await tuition.connect(student1).deposit(USDC(1000));
      expect(await tuition.escrowBalance(student1.address)).to.equal(USDC(1000));
    });

    it("should emit a Deposit event", async function () {
      await usdc.connect(student1).approve(await tuition.getAddress(), USDC(1000));
      await expect(tuition.connect(student1).deposit(USDC(1000)))
        .to.emit(tuition, "Deposit")
        .withArgs(student1.address, USDC(1000));
    });

    it("should allow multiple deposits that accumulate within cap (after cooldown)", async function () {
      await usdc.connect(student1).approve(await tuition.getAddress(), USDC(2000));
      await tuition.connect(student1).deposit(USDC(1000));
      await time.increase(61);
      await tuition.connect(student1).deposit(USDC(1000)); // total = 2000 = cap
      expect(await tuition.escrowBalance(student1.address)).to.equal(USDC(2000));
    });

    it("should revert with ZeroAmount if amount is zero", async function () {
      await expect(
        tuition.connect(student1).deposit(0)
      ).to.be.revertedWithCustomError(tuition, "ZeroAmount");
    });

    it("should revert if caller is not whitelisted", async function () {
      await usdc.mint(outsider.address, USDC(1000));
      await usdc.connect(outsider).approve(await tuition.getAddress(), USDC(1000));
      await expect(tuition.connect(outsider).deposit(USDC(1000))).to.be.reverted;
    });

    it("should revert if student has not approved USDC", async function () {
      await expect(tuition.connect(student1).deposit(USDC(1000))).to.be.reverted;
    });

    it("should revert when contract is paused", async function () {
      await tuition.connect(admin).pause();
      await usdc.connect(student1).approve(await tuition.getAddress(), USDC(1000));
      await expect(tuition.connect(student1).deposit(USDC(1000))).to.be.reverted;
    });
  });

  // ================================================================
  //  Deposit cap
  // ================================================================
  describe("Deposit cap", function () {
    it("should revert with DepositExceedsFees if deposit would exceed fees", async function () {
      // student1 owes 2000 USDC — depositing 2001 must revert
      await usdc.connect(student1).approve(await tuition.getAddress(), USDC(3000));
      await expect(
        tuition.connect(student1).deposit(USDC(2001))
      ).to.be.revertedWithCustomError(tuition, "DepositExceedsFees");
    });

    it("should revert if accumulated balance would exceed fees", async function () {
      await usdc.connect(student1).approve(await tuition.getAddress(), USDC(5000));
      await tuition.connect(student1).deposit(USDC(1500));
      await time.increase(61);
      // 1500 + 600 = 2100 > 2000 cap
      await expect(
        tuition.connect(student1).deposit(USDC(600))
      ).to.be.revertedWithCustomError(tuition, "DepositExceedsFees");
    });

    it("should allow depositing exactly the fee amount", async function () {
      await usdc.connect(student1).approve(await tuition.getAddress(), USDC(2000));
      await tuition.connect(student1).deposit(USDC(2000));
      expect(await tuition.escrowBalance(student1.address)).to.equal(USDC(2000));
    });

    it("should revert if student has no credit units assigned (cap = 0)", async function () {
      const hash2 = ethers.keccak256(ethers.solidityPacked(["string"], ["STU-002"]));
      await tuition.connect(admin).whitelistStudent(student2.address, hash2);
      // No setCreditUnits → calculateFees returns 0 → any amount > 0 exceeds cap
      await usdc.mint(student2.address, USDC(1000));
      await usdc.connect(student2).approve(await tuition.getAddress(), USDC(1000));
      await expect(
        tuition.connect(student2).deposit(USDC(1000))
      ).to.be.revertedWithCustomError(tuition, "DepositExceedsFees");
    });
  });

  // ================================================================
  //  Deposit rate limiting
  // ================================================================
  describe("Deposit rate limiting", function () {
    it("should revert with DepositCooldownActive if depositing too soon", async function () {
      await usdc.connect(student1).approve(await tuition.getAddress(), USDC(2000));
      await tuition.connect(student1).deposit(USDC(1000));
      await expect(
        tuition.connect(student1).deposit(USDC(500))
      ).to.be.revertedWithCustomError(tuition, "DepositCooldownActive");
    });

    it("should allow deposit after cooldown expires", async function () {
      await usdc.connect(student1).approve(await tuition.getAddress(), USDC(2000));
      await tuition.connect(student1).deposit(USDC(1000));
      await time.increase(61);
      await tuition.connect(student1).deposit(USDC(500));
      expect(await tuition.escrowBalance(student1.address)).to.equal(USDC(1500));
    });

    it("should update lastDepositTime on each deposit", async function () {
      await usdc.connect(student1).approve(await tuition.getAddress(), USDC(1000));
      await tuition.connect(student1).deposit(USDC(1000));
      expect(await tuition.lastDepositTime(student1.address)).to.be.gt(0);
    });

    it("DEPOSIT_COOLDOWN constant should be 60 seconds", async function () {
      expect(await tuition.DEPOSIT_COOLDOWN()).to.equal(60);
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

    it("should allow full withdrawal when paused", async function () {
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

    it("should revert with NoFundsAvailable if student has no balance", async function () {
      await tuition.connect(admin).pause();
      await expect(
        tuition.connect(student2).emergencyWithdraw()
      ).to.be.revertedWithCustomError(tuition, "NoFundsAvailable");
    });

    it("should zero balance before transfer (CEI — double withdrawal fails)", async function () {
      await tuition.connect(admin).pause();
      await tuition.connect(student1).emergencyWithdraw();
      await expect(
        tuition.connect(student1).emergencyWithdraw()
      ).to.be.revertedWithCustomError(tuition, "NoFundsAvailable");
    });
  });

  // ================================================================
  //  Privacy: hash mappings
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

    it("should reject duplicate student hash", async function () {
      const hash = ethers.keccak256(ethers.solidityPacked(["string"], ["STU-2026-001"]));
      await expect(
        tuition.connect(admin).whitelistStudent(student2.address, hash)
      ).to.be.revertedWithCustomError(tuition, "HashAlreadyRegistered");
    });

    it("should reject duplicate wallet address", async function () {
      const newHash = ethers.keccak256(ethers.solidityPacked(["string"], ["STU-NEW"]));
      await expect(
        tuition.connect(admin).whitelistStudent(student1.address, newHash)
      ).to.be.revertedWithCustomError(tuition, "WalletAlreadyRegistered");
    });
  });

  // ================================================================
  //  batchWhitelist()
  // ================================================================
  describe("batchWhitelist()", function () {
    it("should whitelist multiple students in one tx", async function () {
      const signers = await ethers.getSigners();
      const h2 = ethers.keccak256(ethers.solidityPacked(["string"], ["STU-B1"]));
      const h3 = ethers.keccak256(ethers.solidityPacked(["string"], ["STU-B2"]));
      await tuition.connect(admin).batchWhitelist([signers[5].address, signers[6].address], [h2, h3]);
      expect(await tuition.studentHashToWallet(h2)).to.equal(signers[5].address);
      expect(await tuition.studentHashToWallet(h3)).to.equal(signers[6].address);
    });

    it("should emit StudentWhitelisted for each student", async function () {
      const s2 = (await ethers.getSigners())[5];
      const h2 = ethers.keccak256(ethers.solidityPacked(["string"], ["STU-B3"]));
      await expect(tuition.connect(admin).batchWhitelist([s2.address], [h2]))
        .to.emit(tuition, "StudentWhitelisted")
        .withArgs(s2.address, h2);
    });

    it("should revert with ArrayLengthMismatch on mismatched arrays", async function () {
      const h = ethers.keccak256(ethers.solidityPacked(["string"], ["STU-X"]));
      await expect(
        tuition.connect(admin).batchWhitelist([student2.address], [h, h])
      ).to.be.revertedWithCustomError(tuition, "ArrayLengthMismatch");
    });

    it("should revert with EmptyArray on empty input", async function () {
      await expect(
        tuition.connect(admin).batchWhitelist([], [])
      ).to.be.revertedWithCustomError(tuition, "EmptyArray");
    });

    it("should revert with HashAlreadyRegistered on duplicate hash", async function () {
      const existing = ethers.keccak256(ethers.solidityPacked(["string"], ["STU-2026-001"]));
      await expect(
        tuition.connect(admin).batchWhitelist([student2.address], [existing])
      ).to.be.revertedWithCustomError(tuition, "HashAlreadyRegistered");
    });

    it("should revert with WalletAlreadyRegistered on duplicate wallet", async function () {
      const newHash = ethers.keccak256(ethers.solidityPacked(["string"], ["STU-NEW"]));
      await expect(
        tuition.connect(admin).batchWhitelist([student1.address], [newHash])
      ).to.be.revertedWithCustomError(tuition, "WalletAlreadyRegistered");
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
    it("should remove a student and clear all mappings", async function () {
      await tuition.connect(admin).removeStudent(student1.address);
      const hash = ethers.keccak256(ethers.solidityPacked(["string"], ["STU-2026-001"]));
      expect(await tuition.studentHashToWallet(hash)).to.equal(ethers.ZeroAddress);
      expect(await tuition.walletToStudentHash(student1.address)).to.equal(ethers.ZeroHash);
      expect(await tuition.creditUnits(student1.address)).to.equal(0);
      expect(await tuition.lastDepositTime(student1.address)).to.equal(0);
    });

    it("should emit StudentRemoved event", async function () {
      const hash = ethers.keccak256(ethers.solidityPacked(["string"], ["STU-2026-001"]));
      await expect(tuition.connect(admin).removeStudent(student1.address))
        .to.emit(tuition, "StudentRemoved")
        .withArgs(student1.address, hash);
    });

    it("should revert with StudentNotWhitelisted for unknown address", async function () {
      await expect(
        tuition.connect(admin).removeStudent(outsider.address)
      ).to.be.revertedWithCustomError(tuition, "StudentNotWhitelisted");
    });

    it("should leave escrow balance intact (admin calls refundStudent first)", async function () {
      await usdc.connect(student1).approve(await tuition.getAddress(), USDC(2000));
      await tuition.connect(student1).deposit(USDC(2000));
      await tuition.connect(admin).removeStudent(student1.address);
      expect(await tuition.escrowBalance(student1.address)).to.equal(USDC(2000));
    });

    it("should clear lastDepositTime so re-whitelisted wallet has no stale cooldown", async function () {
      await usdc.connect(student1).approve(await tuition.getAddress(), USDC(2000));
      await tuition.connect(student1).deposit(USDC(2000));
      await tuition.connect(admin).refundStudent(student1.address);
      await tuition.connect(admin).removeStudent(student1.address);
      expect(await tuition.lastDepositTime(student1.address)).to.equal(0);
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

    it("should revert with NoFundsAvailable if student has no balance", async function () {
      await expect(
        tuition.connect(admin).refundStudent(student1.address)
      ).to.be.revertedWithCustomError(tuition, "NoFundsAvailable");
    });

    it("should revert if caller is not admin", async function () {
      await usdc.connect(student1).approve(await tuition.getAddress(), USDC(500));
      await tuition.connect(student1).deposit(USDC(500));
      await expect(
        tuition.connect(student1).refundStudent(student1.address)
      ).to.be.reverted;
    });
  });

  // ================================================================
  //  batchSetCreditUnits()
  // ================================================================
  describe("batchSetCreditUnits()", function () {
    it("should set credit units for multiple students", async function () {
      const hash2 = ethers.keccak256(ethers.solidityPacked(["string"], ["STU-002"]));
      await tuition.connect(admin).whitelistStudent(student2.address, hash2);
      await tuition.connect(admin).batchSetCreditUnits([student1.address, student2.address], [5, 3]);
      expect(await tuition.creditUnits(student1.address)).to.equal(5);
      expect(await tuition.creditUnits(student2.address)).to.equal(3);
    });

    it("should emit CreditUnitsSet for each student", async function () {
      await expect(tuition.connect(admin).batchSetCreditUnits([student1.address], [10]))
        .to.emit(tuition, "CreditUnitsSet")
        .withArgs(student1.address, 10);
    });

    it("should revert with ArrayLengthMismatch on mismatched arrays", async function () {
      await expect(
        tuition.connect(admin).batchSetCreditUnits([student1.address], [5, 10])
      ).to.be.revertedWithCustomError(tuition, "ArrayLengthMismatch");
    });

    it("should revert with EmptyArray on empty input", async function () {
      await expect(
        tuition.connect(admin).batchSetCreditUnits([], [])
      ).to.be.revertedWithCustomError(tuition, "EmptyArray");
    });

    it("should revert with StudentNotWhitelisted for unknown address", async function () {
      await expect(
        tuition.connect(admin).batchSetCreditUnits([outsider.address], [5])
      ).to.be.revertedWithCustomError(tuition, "StudentNotWhitelisted");
    });

    it("should revert with CreditUnitsOutOfRange for 0 or >30 units", async function () {
      await expect(
        tuition.connect(admin).batchSetCreditUnits([student1.address], [0])
      ).to.be.revertedWithCustomError(tuition, "CreditUnitsOutOfRange");
      await expect(
        tuition.connect(admin).batchSetCreditUnits([student1.address], [31])
      ).to.be.revertedWithCustomError(tuition, "CreditUnitsOutOfRange");
    });
  });

  // ================================================================
  //  setPaymentDate()
  // ================================================================
  describe("setPaymentDate()", function () {
    it("should set a future payment date", async function () {
      const now = await time.latest();
      await tuition.connect(admin).setPaymentDate(now + 3600);
      expect(await tuition.paymentDate()).to.equal(now + 3600);
    });

    it("should revert with PaymentDateMustBeFuture for past/current timestamp", async function () {
      const now = await time.latest();
      await expect(
        tuition.connect(admin).setPaymentDate(now)
      ).to.be.revertedWithCustomError(tuition, "PaymentDateMustBeFuture");
    });

    it("should revert with PaymentsAlreadyExecuted after executePayment is called", async function () {
      // Complete a payment cycle
      await usdc.connect(student1).approve(await tuition.getAddress(), USDC(2000));
      await tuition.connect(student1).deposit(USDC(2000));
      await tuition.connect(admin).lockFxRate();
      const now = await time.latest();
      await tuition.connect(admin).setPaymentDate(now + 60);
      await time.increase(61);
      await tuition.connect(admin).executePayment([student1.address]);

      // Trying to set a new date without resetting should revert
      await expect(
        tuition.connect(admin).setPaymentDate(now + 9999)
      ).to.be.revertedWithCustomError(tuition, "PaymentsAlreadyExecuted");
    });
  });

  // ================================================================
  //  setFeePerUnit()
  // ================================================================
  describe("setFeePerUnit()", function () {
    it("should update the fee per unit", async function () {
      await tuition.connect(admin).setFeePerUnit(USDC(600));
      expect(await tuition.feePerUnit()).to.equal(USDC(600));
    });

    it("should emit FeePerUnitUpdated event", async function () {
      await expect(tuition.connect(admin).setFeePerUnit(USDC(600)))
        .to.emit(tuition, "FeePerUnitUpdated")
        .withArgs(FEE_PER_UNIT, USDC(600));
    });

    it("should revert with FeesMustBePositive for zero fee", async function () {
      await expect(
        tuition.connect(admin).setFeePerUnit(0)
      ).to.be.revertedWithCustomError(tuition, "FeesMustBePositive");
    });

    it("should revert with PaymentsAlreadyExecuted after executePayment is called", async function () {
      await usdc.connect(student1).approve(await tuition.getAddress(), USDC(2000));
      await tuition.connect(student1).deposit(USDC(2000));
      await tuition.connect(admin).lockFxRate();
      const now = await time.latest();
      await tuition.connect(admin).setPaymentDate(now + 60);
      await time.increase(61);
      await tuition.connect(admin).executePayment([student1.address]);

      await expect(
        tuition.connect(admin).setFeePerUnit(USDC(600))
      ).to.be.revertedWithCustomError(tuition, "PaymentsAlreadyExecuted");
    });
  });

  // ================================================================
  //  lockFxRate() + resetLockedFxRate()
  // ================================================================
  describe("lockFxRate()", function () {
    it("should lock the current Chainlink rate as uint256", async function () {
      await tuition.connect(admin).lockFxRate();
      expect(await tuition.lockedFxRate()).to.equal(MOCK_FX_RATE);
    });

    it("should emit FxRateLocked event", async function () {
      await expect(tuition.connect(admin).lockFxRate())
        .to.emit(tuition, "FxRateLocked")
        .withArgs(MOCK_FX_RATE, anyValue);
    });

    it("should allow re-locking to update the rate", async function () {
      await tuition.connect(admin).lockFxRate();
      await tuition.connect(admin).lockFxRate();
      expect(await tuition.lockedFxRate()).to.equal(MOCK_FX_RATE);
    });

    it("should revert if caller is not admin", async function () {
      await expect(tuition.connect(outsider).lockFxRate()).to.be.reverted;
    });
  });

  describe("resetLockedFxRate()", function () {
    it("should clear the locked rate to zero", async function () {
      await tuition.connect(admin).lockFxRate();
      await tuition.connect(admin).resetLockedFxRate();
      expect(await tuition.lockedFxRate()).to.equal(0);
    });

    it("should emit FxRateReset event with the previous rate", async function () {
      await tuition.connect(admin).lockFxRate();
      await expect(tuition.connect(admin).resetLockedFxRate())
        .to.emit(tuition, "FxRateReset")
        .withArgs(MOCK_FX_RATE);
    });

    it("should cause calculateFeesInJPY to revert after reset", async function () {
      await tuition.connect(admin).lockFxRate();
      await tuition.connect(admin).resetLockedFxRate();
      await expect(
        tuition.calculateFeesInJPY(student1.address)
      ).to.be.revertedWithCustomError(tuition, "FxRateNotLocked");
    });

    it("should cause executePayment to revert after reset", async function () {
      await usdc.connect(student1).approve(await tuition.getAddress(), USDC(2000));
      await tuition.connect(student1).deposit(USDC(2000));
      await tuition.connect(admin).lockFxRate();
      const now = await time.latest();
      await tuition.connect(admin).setPaymentDate(now + 60);
      await time.increase(61);
      await tuition.connect(admin).resetLockedFxRate();

      await expect(
        tuition.connect(admin).executePayment([student1.address])
      ).to.be.revertedWithCustomError(tuition, "FxRateNotLocked");
    });

    it("should revert if caller is not admin", async function () {
      await expect(tuition.connect(outsider).resetLockedFxRate()).to.be.reverted;
    });
  });

  // ================================================================
  //  calculateFees() + calculateFeesInJPY()
  // ================================================================
  describe("calculateFees()", function () {
    it("should return creditUnits * feePerUnit", async function () {
      expect(await tuition.calculateFees(student1.address)).to.equal(USDC(2000));
    });

    it("should return 0 for unknown address", async function () {
      expect(await tuition.calculateFees(outsider.address)).to.equal(0);
    });
  });

  describe("calculateFeesInJPY()", function () {
    it("should convert USDC fees to JPY using locked rate", async function () {
      await tuition.connect(admin).lockFxRate();
      // 4 CU × 500 USDC = 2000 USDC = 2_000_000_000 raw
      // (2_000_000_000 * 1e8) / (670_000 * 1e6) = 298,507 JPY
      expect(await tuition.calculateFeesInJPY(student1.address)).to.equal(298507n);
    });

    it("should return 0 for student with 0 credit units", async function () {
      await tuition.connect(admin).lockFxRate();
      expect(await tuition.calculateFeesInJPY(outsider.address)).to.equal(0);
    });

    it("should revert with FxRateNotLocked if rate not set", async function () {
      await expect(
        tuition.calculateFeesInJPY(student1.address)
      ).to.be.revertedWithCustomError(tuition, "FxRateNotLocked");
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

    it("should reset paid students", async function () {
      expect(await tuition.paymentCompleted(student1.address)).to.equal(true);
      await tuition.connect(admin).batchResetPayments([student1.address]);
      expect(await tuition.paymentCompleted(student1.address)).to.equal(false);
    });

    it("should reset paymentsExecutedThisSemester flag", async function () {
      expect(await tuition.paymentsExecutedThisSemester()).to.equal(true);
      await tuition.connect(admin).batchResetPayments([student1.address]);
      expect(await tuition.paymentsExecutedThisSemester()).to.equal(false);
    });

    it("should emit PaymentStatusReset for paid students", async function () {
      await expect(tuition.connect(admin).batchResetPayments([student1.address]))
        .to.emit(tuition, "PaymentStatusReset")
        .withArgs(student1.address);
    });

    it("should silently skip unpaid students (no event, no SSTORE)", async function () {
      const hash2 = ethers.keccak256(ethers.solidityPacked(["string"], ["STU-002"]));
      await tuition.connect(admin).whitelistStudent(student2.address, hash2);
      // student2 never paid — should not emit
      const tx = await tuition.connect(admin).batchResetPayments([student1.address, student2.address]);
      const receipt = await tx.wait();
      const resetEvents = receipt.logs.filter(
        l => l.fragment && l.fragment.name === "PaymentStatusReset"
      );
      expect(resetEvents.length).to.equal(1); // only student1
    });

    it("should revert with StudentNotWhitelisted for non-whitelisted address", async function () {
      await expect(
        tuition.connect(admin).batchResetPayments([outsider.address])
      ).to.be.revertedWithCustomError(tuition, "StudentNotWhitelisted");
    });

    it("should revert with EmptyArray on empty input", async function () {
      await expect(
        tuition.connect(admin).batchResetPayments([])
      ).to.be.revertedWithCustomError(tuition, "EmptyArray");
    });
  });

  // ================================================================
  //  getStatus()
  // ================================================================
  describe("getStatus()", function () {
    it("should return (true, false, false, 0, 60) for whitelisted student with no deposit", async function () {
      const [isWhitelisted, isDeposited, isPaid, balance, nextDepositAllowed] =
        await tuition.getStatus(student1.address);
      expect(isWhitelisted).to.equal(true);
      expect(isDeposited).to.equal(false);
      expect(isPaid).to.equal(false);
      expect(balance).to.equal(0);
      expect(nextDepositAllowed).to.equal(60); // lastDepositTime(0) + 60
    });

    it("should return isDeposited=true when fully funded", async function () {
      await usdc.connect(student1).approve(await tuition.getAddress(), USDC(2000));
      await tuition.connect(student1).deposit(USDC(2000));
      const [, isDeposited, , balance] = await tuition.getStatus(student1.address);
      expect(isDeposited).to.equal(true);
      expect(balance).to.equal(USDC(2000));
    });

    it("should return (false, false, false, 0, 60) for unknown address", async function () {
      const [isWhitelisted, isDeposited, isPaid, balance, nextDepositAllowed] =
        await tuition.getStatus(outsider.address);
      expect(isWhitelisted).to.equal(false);
      expect(isDeposited).to.equal(false);
      expect(isPaid).to.equal(false);
      expect(balance).to.equal(0);
      expect(nextDepositAllowed).to.equal(60);
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

    it("should return nextDepositAllowed = lastDepositTime + 60", async function () {
      await usdc.connect(student1).approve(await tuition.getAddress(), USDC(1000));
      await tuition.connect(student1).deposit(USDC(1000));
      const lastTime = await tuition.lastDepositTime(student1.address);
      const [, , , , nextDepositAllowed] = await tuition.getStatus(student1.address);
      expect(nextDepositAllowed).to.equal(lastTime + 60n);
    });
  });

  // ================================================================
  //  Integration: full payment lifecycle
  // ================================================================
  describe("Integration: end-to-end payment flow", function () {
    it("whitelist → set CU → lock rate → deposit → execute payment", async function () {
      const hash2 = ethers.keccak256(ethers.solidityPacked(["string"], ["STU-2026-002"]));
      await tuition.connect(admin).whitelistStudent(student2.address, hash2);
      await tuition.connect(admin).setCreditUnits(student2.address, 3); // 1500 USDC

      await usdc.mint(student2.address, USDC(5000));
      await usdc.connect(student2).approve(await tuition.getAddress(), USDC(1500));
      await tuition.connect(student2).deposit(USDC(1500));

      await tuition.connect(admin).lockFxRate();
      const now = await time.latest();
      await tuition.connect(admin).setPaymentDate(now + 60);
      await time.increase(61);

      const uniBefore = await usdc.balanceOf(universityWallet.address);
      await tuition.connect(admin).executePayment([student2.address]);
      const uniAfter = await usdc.balanceOf(universityWallet.address);

      expect(uniAfter - uniBefore).to.equal(USDC(1500));
      expect(await tuition.escrowBalance(student2.address)).to.equal(0);
      expect(await tuition.paymentCompleted(student2.address)).to.equal(true);
      expect(await tuition.paymentsExecutedThisSemester()).to.equal(true);
    });

    it("should skip students with 0 credit units in executePayment", async function () {
      const hash2 = ethers.keccak256(ethers.solidityPacked(["string"], ["STU-002"]));
      await tuition.connect(admin).whitelistStudent(student2.address, hash2);
      // No CU assigned → required = 0 → skip

      await tuition.connect(admin).lockFxRate();
      const now = await time.latest();
      await tuition.connect(admin).setPaymentDate(now + 60);
      await time.increase(61);

      await tuition.connect(admin).executePayment([student2.address]);
      expect(await tuition.paymentCompleted(student2.address)).to.equal(false);
    });

    it("should skip already-paid students silently", async function () {
      await usdc.connect(student1).approve(await tuition.getAddress(), USDC(2000));
      await tuition.connect(student1).deposit(USDC(2000));
      await tuition.connect(admin).lockFxRate();
      const now = await time.latest();
      await tuition.connect(admin).setPaymentDate(now + 60);
      await time.increase(61);
      await tuition.connect(admin).executePayment([student1.address]);

      const uniBefore = await usdc.balanceOf(universityWallet.address);
      await tuition.connect(admin).executePayment([student1.address]);
      expect(await usdc.balanceOf(universityWallet.address)).to.equal(uniBefore);
    });

    it("should emit InsufficientBalance for underfunded students", async function () {
      await usdc.connect(student1).approve(await tuition.getAddress(), USDC(500));
      await tuition.connect(student1).deposit(USDC(500));

      await tuition.connect(admin).lockFxRate();
      const now = await time.latest();
      await tuition.connect(admin).setPaymentDate(now + 60);
      await time.increase(61);

      await expect(tuition.connect(admin).executePayment([student1.address]))
        .to.emit(tuition, "InsufficientBalance")
        .withArgs(student1.address, USDC(2000), USDC(500));
    });

    it("full semester reset → new semester cycle", async function () {
      // Semester 1: pay
      await usdc.connect(student1).approve(await tuition.getAddress(), USDC(2000));
      await tuition.connect(student1).deposit(USDC(2000));
      await tuition.connect(admin).lockFxRate();
      const now = await time.latest();
      await tuition.connect(admin).setPaymentDate(now + 60);
      await time.increase(61);
      await tuition.connect(admin).executePayment([student1.address]);
      expect(await tuition.paymentsExecutedThisSemester()).to.equal(true);

      // Reset for semester 2
      await tuition.connect(admin).batchResetPayments([student1.address]);
      await tuition.connect(admin).resetLockedFxRate();
      expect(await tuition.paymentsExecutedThisSemester()).to.equal(false);
      expect(await tuition.lockedFxRate()).to.equal(0);

      // Semester 2: lock new rate, set new date, deposit, pay
      await tuition.connect(admin).lockFxRate();
      const now2 = await time.latest();
      await tuition.connect(admin).setPaymentDate(now2 + 60);
      await usdc.connect(student1).approve(await tuition.getAddress(), USDC(2000));
      await time.increase(61); // past cooldown AND payment date
      await tuition.connect(student1).deposit(USDC(2000));
      await tuition.connect(admin).executePayment([student1.address]);
      expect(await tuition.paymentCompleted(student1.address)).to.equal(true);
    });

    it("refund → remove → re-whitelist flow", async function () {
      await usdc.connect(student1).approve(await tuition.getAddress(), USDC(1000));
      await tuition.connect(student1).deposit(USDC(1000));

      await tuition.connect(admin).refundStudent(student1.address);
      await tuition.connect(admin).removeStudent(student1.address);

      const newHash = ethers.keccak256(ethers.solidityPacked(["string"], ["STU-2026-001-v2"]));
      await tuition.connect(admin).whitelistStudent(student1.address, newHash);
      expect(await tuition.studentHashToWallet(newHash)).to.equal(student1.address);
    });
  });
});
