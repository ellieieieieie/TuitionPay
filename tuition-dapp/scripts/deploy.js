const { ethers } = require("hardhat");

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying with account:", deployer.address);

  // ── 1. Deploy MockUSDC (local only — on testnet use real USDC address) ──
  const MockUSDC = await ethers.getContractFactory("MockUSDC");
  const usdc = await MockUSDC.deploy();
  await usdc.waitForDeployment();
  console.log("MockUSDC deployed to:", await usdc.getAddress());

  // ── 2. Deploy MockPriceFeed (local only — on testnet use real Chainlink feed) ──
  const MockPriceFeed = await ethers.getContractFactory("MockPriceFeed");
  const feed = await MockPriceFeed.deploy(670000, 8); // JPY/USD ~0.0067
  await feed.waitForDeployment();
  console.log("MockPriceFeed deployed to:", await feed.getAddress());

  // ── 3. Deploy TuitionPayment ──
  const FEE_PER_UNIT = ethers.parseUnits("500", 6); // $500 per credit unit (USDC 6 dec)
  const universityWallet = deployer.address;         // use deployer as university for local testing

  const TuitionPayment = await ethers.getContractFactory("TuitionPayment");
  const tuition = await TuitionPayment.deploy(
    await usdc.getAddress(),
    deployer.address,        // admin
    universityWallet,
    FEE_PER_UNIT,
    await feed.getAddress()
  );
  await tuition.waitForDeployment();
  console.log("TuitionPayment deployed to:", await tuition.getAddress());

  // ── 4. Quick smoke test: whitelist a student and deposit ──
  const signers = await ethers.getSigners();
  const student = signers[1];

  const studentHash = ethers.keccak256(
    ethers.solidityPacked(["string"], ["STU-2026-001"])
  );

  await tuition.whitelistStudent(student.address, studentHash);
  console.log("Student whitelisted:", student.address);

  await tuition.setCreditUnits(student.address, 4);
  console.log("Credit units set: 4 (owes $2,000 USDC)");

  // Mint USDC to student and deposit
  await usdc.mint(student.address, ethers.parseUnits("5000", 6));
  await usdc.connect(student).approve(await tuition.getAddress(), ethers.parseUnits("2000", 6));
  await tuition.connect(student).deposit(ethers.parseUnits("2000", 6));

  const balance = await tuition.escrowBalance(student.address);
  console.log("Student escrow balance:", ethers.formatUnits(balance, 6), "USDC");

  const sufficient = await tuition.checkSufficient(student.address);
  console.log("Payment sufficient?", sufficient);

  console.log("\nDone. All contracts deployed and smoke-tested successfully.");
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
