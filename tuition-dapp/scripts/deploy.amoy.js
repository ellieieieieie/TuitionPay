/**
 * deploy.amoy.js — Polygon Amoy testnet deployment
 *
 * Deploys MockUSDC and MockPriceFeed on-chain (Amoy has no JPY/USD Chainlink
 * feed and no publicly faucetable USDC), then deploys TuitionPayment wired
 * to both.  Everything is real on-chain state — just using test tokens.
 *
 * Prerequisites:
 *   1. Copy .env.example → .env and fill in:
 *        AMOY_RPC_URL, DEPLOYER_PRIVATE_KEY, POLYGONSCAN_API_KEY
 *   2. Fund your deployer wallet with Amoy POL:
 *        https://faucet.polygon.technology  (select "Amoy")
 *
 * Run:
 *   npx hardhat run scripts/deploy.amoy.js --network amoy
 */

const { ethers, run } = require("hardhat");

// ─── Config ────────────────────────────────────────────────────────────────

// $500 USDC per credit unit (USDC has 6 decimals)
const FEE_PER_UNIT = ethers.parseUnits("500", 6);

// Mock JPY/USD rate: ~0.0067 expressed with 8 decimals = 670_000
const MOCK_FX_PRICE = 670_000n;
const MOCK_FX_DECIMALS = 8;

// How long to wait before attempting PolygonScan verification (ms)
const VERIFY_DELAY_MS = 30_000;

// ─── Helpers ───────────────────────────────────────────────────────────────

function log(msg) { console.log(`\n[deploy] ${msg}`); }

async function deployAndLog(factory, args = [], label = "") {
  const contract = await factory.deploy(...args);
  await contract.waitForDeployment();
  const addr = await contract.getAddress();
  console.log(`  ✔ ${label || factory.target} → ${addr}`);
  return contract;
}

/** Pause so Amoy indexers catch up before verification */
function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function verify(address, constructorArgs) {
  try {
    await run("verify:verify", {
      address,
      constructorArguments: constructorArgs,
    });
    console.log(`  ✔ Verified on PolygonScan`);
  } catch (err) {
    // "Already verified" is not a real error
    if (err.message?.includes("Already Verified") || err.message?.includes("already verified")) {
      console.log(`  ✔ Already verified`);
    } else {
      console.warn(`  ⚠ Verification failed: ${err.message}`);
    }
  }
}

// ─── Main ──────────────────────────────────────────────────────────────────

async function main() {
  const [deployer] = await ethers.getSigners();
  const network = await ethers.provider.getNetwork();

  log(`Network  : ${network.name} (chainId ${network.chainId})`);
  log(`Deployer : ${deployer.address}`);
  log(`Balance  : ${ethers.formatEther(await ethers.provider.getBalance(deployer.address))} POL`);

  // ── 1. MockUSDC ────────────────────────────────────────────────────────
  log("Deploying MockUSDC…");
  const MockUSDC = await ethers.getContractFactory("MockUSDC");
  const usdc = await deployAndLog(MockUSDC, [], "MockUSDC");

  // ── 2. MockPriceFeed ───────────────────────────────────────────────────
  log("Deploying MockPriceFeed (JPY/USD, 8 dec)…");
  const MockPriceFeed = await ethers.getContractFactory("MockPriceFeed");
  const feed = await deployAndLog(MockPriceFeed, [MOCK_FX_PRICE, MOCK_FX_DECIMALS], "MockPriceFeed");

  // ── 3. TuitionPayment ──────────────────────────────────────────────────
  log("Deploying TuitionPayment…");
  const usdcAddr  = await usdc.getAddress();
  const feedAddr  = await feed.getAddress();
  const uniWallet = deployer.address; // replace with the real university wallet before going live

  const TuitionPayment = await ethers.getContractFactory("TuitionPayment");
  const tuition = await deployAndLog(
    TuitionPayment,
    [usdcAddr, deployer.address, uniWallet, FEE_PER_UNIT, feedAddr],
    "TuitionPayment"
  );
  const tuitionAddr = await tuition.getAddress();

  // ── 4. Initial setup ───────────────────────────────────────────────────
  log("Locking FX rate from mock Chainlink feed…");
  await (await tuition.lockFxRate()).wait();
  const lockedRate = await tuition.lockedFxRate();
  console.log(`  ✔ FX rate locked: ${lockedRate} (8 decimals → ${Number(lockedRate) / 1e8} USD/JPY)`);

  log("Setting payment date (30 days from now)…");
  const thirtyDays = Math.floor(Date.now() / 1000) + 30 * 24 * 60 * 60;
  await (await tuition.setPaymentDate(thirtyDays)).wait();
  console.log(`  ✔ Payment date set to ${new Date(thirtyDays * 1000).toUTCString()}`);

  // ── 5. Print deployment summary ────────────────────────────────────────
  log("─── Deployment Summary ───────────────────────────────────────────");
  console.log(`  MockUSDC        : ${usdcAddr}`);
  console.log(`  MockPriceFeed   : ${feedAddr}`);
  console.log(`  TuitionPayment  : ${tuitionAddr}`);
  console.log(`  Admin/Deployer  : ${deployer.address}`);
  console.log(`  University Wallet: ${uniWallet}`);
  console.log(`  Fee per unit    : $${ethers.formatUnits(FEE_PER_UNIT, 6)} USDC`);
  console.log(`  Payment date    : ${new Date(thirtyDays * 1000).toUTCString()}`);

  log("─── Next Steps ───────────────────────────────────────────────────");
  console.log("  1. Copy the addresses above into your front-end / .env");
  console.log("  2. Mint test USDC to student wallets:");
  console.log(`       usdc.mint(<studentAddress>, <amount>)`);
  console.log("  3. Whitelist students:");
  console.log(`       tuition.whitelistStudent(<wallet>, keccak256(<studentId>))`);
  console.log("  4. Set credit units:");
  console.log(`       tuition.setCreditUnits(<wallet>, <units>)`);

  // ── 6. PolygonScan verification (optional, requires API key) ───────────
  if (process.env.POLYGONSCAN_API_KEY) {
    log(`Waiting ${VERIFY_DELAY_MS / 1000}s for Amoy indexer, then verifying…`);
    await sleep(VERIFY_DELAY_MS);

    log("Verifying MockUSDC…");
    await verify(usdcAddr, []);

    log("Verifying MockPriceFeed…");
    await verify(feedAddr, [MOCK_FX_PRICE, MOCK_FX_DECIMALS]);

    log("Verifying TuitionPayment…");
    await verify(tuitionAddr, [usdcAddr, deployer.address, uniWallet, FEE_PER_UNIT, feedAddr]);
  } else {
    log("POLYGONSCAN_API_KEY not set — skipping verification.");
    console.log("  Add it to .env and re-run with --verify to verify later.");
  }

  log("Done.");
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
