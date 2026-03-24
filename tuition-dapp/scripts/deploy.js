// scripts/deploy.js
// Deploys all contracts to the local Hardhat node and sets up test data.
// Run: npx hardhat run scripts/deploy.js --network localhost

const hre = require("hardhat");

async function main() {
  const [admin, student1, student2, universityWallet] =
    await hre.ethers.getSigners();

  const USDC = (n) => hre.ethers.parseUnits(n.toString(), 6);
  const FEE_PER_UNIT = USDC(500); // $500 per credit unit

  console.log("=== Deploying contracts ===\n");
  console.log("Admin:            ", admin.address);
  console.log("Student 1:        ", student1.address);
  console.log("Student 2:        ", student2.address);
  console.log("University Wallet:", universityWallet.address);
  console.log("");

  // 1. Deploy MockUSDC
  const MockUSDC = await hre.ethers.getContractFactory("MockUSDC");
  const usdc = await MockUSDC.deploy();
  await usdc.waitForDeployment();
  console.log("MockUSDC deployed to:      ", await usdc.getAddress());

  // 2. Deploy MockPriceFeed (SGD/USD = 0.75, 8 decimals)
  const MockPriceFeed = await hre.ethers.getContractFactory("MockPriceFeed");
  const priceFeed = await MockPriceFeed.deploy(75000000n, 8);
  await priceFeed.waitForDeployment();
  console.log("MockPriceFeed deployed to: ", await priceFeed.getAddress());

  // 3. Deploy TuitionPayment
  const TuitionPayment = await hre.ethers.getContractFactory("TuitionPayment");
  const tuition = await TuitionPayment.deploy(
    await usdc.getAddress(),
    admin.address,
    universityWallet.address,
    FEE_PER_UNIT,
    await priceFeed.getAddress()
  );
  await tuition.waitForDeployment();
  console.log("TuitionPayment deployed to:", await tuition.getAddress());

  // 4. Setup test data — whitelist 2 students
  console.log("\n=== Setting up test data ===\n");

  const hash1 = hre.ethers.keccak256(
    hre.ethers.solidityPacked(["string"], ["STU-2026-001"])
  );
  await tuition.whitelistStudent(student1.address, hash1);
  await tuition.setCreditUnits(student1.address, 4);
  console.log("Whitelisted Student 1:", student1.address, "(4 CU)");

  const hash2 = hre.ethers.keccak256(
    hre.ethers.solidityPacked(["string"], ["STU-2026-002"])
  );
  await tuition.whitelistStudent(student2.address, hash2);
  await tuition.setCreditUnits(student2.address, 3);
  console.log("Whitelisted Student 2:", student2.address, "(3 CU)");

  // 5. Mint USDC to students so they can deposit
  await usdc.mint(student1.address, USDC(10000));
  await usdc.mint(student2.address, USDC(10000));
  console.log("Minted 10,000 USDC to each student");

  // 6. Students approve and deposit
  await usdc.connect(student1).approve(await tuition.getAddress(), USDC(2000));
  await tuition.connect(student1).deposit(USDC(2000));
  console.log("Student 1 deposited 2,000 USDC");

  await usdc.connect(student2).approve(await tuition.getAddress(), USDC(1500));
  await tuition.connect(student2).deposit(USDC(1500));
  console.log("Student 2 deposited 1,500 USDC");

  // 7. Print summary
  console.log("\n========================================");
  console.log("  COPY THESE INTO YOUR FRONTEND");
  console.log("========================================");
  console.log(`TUITION_ADDRESS = "${await tuition.getAddress()}"`);
  console.log(`USDC_ADDRESS    = "${await usdc.getAddress()}"`);
  console.log("========================================\n");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});