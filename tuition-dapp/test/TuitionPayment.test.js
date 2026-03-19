const { expect } = require("chai");
const { ethers } = require("hardhat");
const { time } = require("@nomicfoundation/hardhat-network-helpers");

describe("TuitionPayment — Student Payment Flow", function () {
  // ── Shared state ──
  let tuition, usdc;
  let admin, student1, student2, universityWallet, outsider;

  // 1 USDC = 1_000_000 (6 decimals)
  const USDC = (n) => ethers.parseUnits(n.toString(), 6);
  const FEE_PER_UNIT = USDC(500); // $500 per credit unit

  // ── Deploy fresh contracts before each test ──
  beforeEach(async function () {
    [admin, student1, student2, universityWallet, outsider] =
      await ethers.getSigners();

    // Deploy MockUSDC
    const MockUSDC = await ethers.getContractFactory("MockUSDC");
    usdc = await MockUSDC.deploy();
    await usdc.waitForDeployment();

    // Deploy TuitionPayment
    const TuitionPayment = await ethers.getContractFactory("TuitionPayment");
    tuition = await TuitionPayment.deploy(
      await usdc.getAddress(),
      admin.address,
      universityWallet.address,
      FEE_PER_UNIT
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

      // Student must approve first
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

      await expect(
        tuition.connect(outsider).deposit(USDC(1000))
      ).to.be.reverted; // AccessControl revert
    });

    it("should revert if student has not approved USDC", async function () {
      await expect(
        tuition.connect(student1).deposit(USDC(1000))
      ).to.be.reverted; // ERC20: insufficient allowance
    });

    it("should revert if student has insufficient USDC balance", async function () {
      // student1 has 10,000 USDC — try to deposit 20,000
      await usdc
        .connect(student1)
        .approve(await tuition.getAddress(), USDC(20000));

      await expect(
        tuition.connect(student1).deposit(USDC(20000))
      ).to.be.reverted; // ERC20: transfer amount exceeds balance
    });

    it("should revert when contract is paused", async function () {
      await tuition.connect(admin).pause();
      await usdc.connect(student1).approve(await tuition.getAddress(), USDC(1000));

      await expect(
        tuition.connect(student1).deposit(USDC(1000))
      ).to.be.reverted; // Pausable: paused
    });
  });

  // ================================================================
  //  calculateFees() + checkSufficient()
  // ================================================================
  describe("calculateFees()", function () {
    it("should return creditUnits * feePerUnit", async function () {
      // student1 has 4 CU at $500 each = $2,000
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

      // Owes 2000, deposited 1000
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
      // Deposit 2000 USDC first
      await usdc.connect(student1).approve(await tuition.getAddress(), USDC(2000));
      await tuition.connect(student1).deposit(USDC(2000));
    });

    it("should allow withdrawal when paused", async function () {
      await tuition.connect(admin).pause();
      await tuition.connect(student1).emergencyWithdraw();

      expect(await tuition.escrowBalance(student1.address)).to.equal(0);
      expect(await usdc.balanceOf(student1.address)).to.equal(USDC(10000)); // back to original
    });

    it("should emit EmergencyWithdrawal event", async function () {
      await tuition.connect(admin).pause();

      await expect(tuition.connect(student1).emergencyWithdraw())
        .to.emit(tuition, "EmergencyWithdrawal")
        .withArgs(student1.address, USDC(2000));
    });

    it("should revert when contract is NOT paused", async function () {
      await expect(
        tuition.connect(student1).emergencyWithdraw()
      ).to.be.reverted; // Pausable: not paused
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

      // Double withdrawal should fail
      await expect(
        tuition.connect(student1).emergencyWithdraw()
      ).to.be.revertedWith("No funds to withdraw");
    });
  });

  // ================================================================
  //  Privacy layer — studentHashToWallet
  // ================================================================
  describe("Privacy: studentHashToWallet", function () {
    it("should map hashed student ID to wallet address", async function () {
      const hash = ethers.keccak256(
        ethers.solidityPacked(["string"], ["STU-2026-001"])
      );
      expect(await tuition.studentHashToWallet(hash)).to.equal(student1.address);
    });

    it("should not store plaintext student ID on-chain", async function () {
      // There is no getter for a plaintext ID — only the hash exists
      // This test documents the design intent
      const hash = ethers.keccak256(
        ethers.solidityPacked(["string"], ["STU-2026-001"])
      );
      const wallet = await tuition.studentHashToWallet(hash);
      expect(wallet).to.not.equal(ethers.ZeroAddress);
    });

    it("should reject duplicate student hash", async function () {
      const hash = ethers.keccak256(
        ethers.solidityPacked(["string"], ["STU-2026-001"])
      );
      await expect(
        tuition.connect(admin).whitelistStudent(student2.address, hash)
      ).to.be.revertedWith("Student hash already registered");
    });
  });

  // ================================================================
  //  Integration: full student payment flow
  // ================================================================
  describe("Integration: end-to-end student flow", function () {
    it("whitelist → set CU → deposit → check sufficient → execute payment", async function () {
      // Setup student2
      const hash2 = ethers.keccak256(
        ethers.solidityPacked(["string"], ["STU-2026-002"])
      );
      await tuition.connect(admin).whitelistStudent(student2.address, hash2);
      await tuition.connect(admin).setCreditUnits(student2.address, 3); // 3 × 500 = 1500

      // Fund student2
      await usdc.mint(student2.address, USDC(5000));
      await usdc.connect(student2).approve(await tuition.getAddress(), USDC(1500));
      await tuition.connect(student2).deposit(USDC(1500));

      expect(await tuition.checkSufficient(student2.address)).to.equal(true);

      // Admin sets payment date to 1 second from now
      const now = await time.latest();
      await tuition.connect(admin).setPaymentDate(now + 60);

      // Fast-forward past payment date
      await time.increase(61);

      // Execute payment
      const uniBalanceBefore = await usdc.balanceOf(universityWallet.address);
      await tuition.connect(admin).executePayment([student2.address]);
      const uniBalanceAfter = await usdc.balanceOf(universityWallet.address);

      expect(uniBalanceAfter - uniBalanceBefore).to.equal(USDC(1500));
      expect(await tuition.escrowBalance(student2.address)).to.equal(0);
    });
  });
});
