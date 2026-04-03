# TuitionPayDApp

A decentralised tuition payment application built on **Polygon PoS** for the **BAC2002 Blockchain and Cryptocurrency** module at the Singapore Institute of Technology (SIT).

TuitionPayDApp enables international students to pay tuition fees using **USDC stablecoin** through a smart contract–based **escrow system**, replacing manual bank transfers with automated, transparent, and near-instant on-chain settlement.

---

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Technology Stack](#technology-stack)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Environment Configuration](#environment-configuration)
- [Deployment](#deployment)
  - [Local Development (Hardhat)](#local-development-hardhat)
  - [Polygon Amoy Testnet](#polygon-amoy-testnet)
- [Running Tests](#running-tests)
- [Frontend Usage](#frontend-usage)
- [Smart Contracts](#smart-contracts)
- [Deployed Contracts (Amoy Testnet)](#deployed-contracts-amoy-testnet)
- [Project Structure](#project-structure)
- [Team](#team)

---

## Overview

International students paying tuition fees from abroad face high foreign exchange conversion fees (~3–4% via SWIFT), slow cross-border settlement (3–5 business days), and limited payment transparency. TuitionPayDApp addresses these inefficiencies:

- **Low fees**: A $891 USDC transfer on Polygon costs ~$0.001 in gas fees (99%+ reduction vs traditional wire)
- **Near-instant settlement**: ~2-second block finality on Polygon PoS
- **Full transparency**: All transactions permanently recorded and verifiable on PolygonScan
- **FX rate consistency**: Chainlink oracle integration locks the JPY/USD rate per trimester so all students see the same local currency equivalent

---

## Architecture

The system follows a four-layer design:

1. **Frontend Layer** — Student Client and Admin Client (Vanilla JS + CSS), connected via MetaMask and ethers.js
2. **Off-Chain Layer** — Chainlink oracle for FX rates (MockPriceFeed on testnet), student USDC acquisition via external exchanges
3. **Security Layer** — RBAC (OpenZeppelin AccessControl), ReentrancyGuard, Pausable, oracle staleness validation, bounded batch sizes, deposit rate limiting
4. **On-Chain Layer** — TuitionPayment.sol smart contract on Polygon PoS with six core modules: Identity & Whitelist, CU & Fees, FX Rate, Escrow, Payment, Receipt

Refer to the report's Appendix B for the full architecture diagram.

---

## Technology Stack

| Component | Technology |
|-----------|-----------|
| Smart Contract Language | Solidity 0.8.20 |
| Development Framework | Hardhat |
| Security Libraries | OpenZeppelin v5 (AccessControl, ReentrancyGuard, Pausable) |
| Oracle | Chainlink AggregatorV3Interface (@chainlink/contracts v1.5.0) |
| Frontend | Vanilla JavaScript, CSS |
| Blockchain Library | ethers.js v6 (CDN) |
| Wallet | MetaMask |
| Blockchain | Polygon PoS (Amoy testnet for demo) |
| Stablecoin | USDC (native Circle-issued on Polygon) |

---

## Prerequisites

Before you begin, ensure you have the following installed:

- **Node.js** >= v18.0.0 — [Download](https://nodejs.org/)
- **npm** (comes with Node.js)
- **MetaMask** browser extension — [Install](https://metamask.io/)
- **Git** — [Download](https://git-scm.com/)

For testnet deployment, you will also need:
- A MetaMask wallet with **Amoy testnet POL** for gas fees — [Polygon Faucet](https://faucet.polygon.technology)
- A **PolygonScan API key** (for contract verification) — [Get one here](https://polygonscan.com/myapikey)

---

## Installation

1. **Clone the repository**

```bash
git clone https://github.com/ellieieieieie/TuitionPay.git
cd TuitonPay
```

2. **Install dependencies**

```bash
npm install
```

This installs Hardhat, OpenZeppelin contracts, Chainlink contracts, and all dev dependencies.

3. **Compile the smart contracts**

```bash
npx hardhat compile
```

---

## Environment Configuration

1. **Copy the example environment file**

```bash
cp .env.example .env
```

2. **Fill in your `.env` file**

```env
# Polygon Amoy testnet RPC
AMOY_RPC_URL=https://rpc-amoy.polygon.technology

# Deployer wallet private key (MetaMask → Account Details → Export)
DEPLOYER_PRIVATE_KEY=<your-private-key>

# PolygonScan API key (for contract verification)
POLYGONSCAN_API_KEY=<your-api-key>
```

> **Security**: Never commit your `.env` file. It is already included in `.gitignore`.

---

## Deployment

### Local Development (Hardhat)

1. **Start a local Hardhat node** (in a separate terminal):

```bash
npx hardhat node
```

This starts a local Ethereum-compatible blockchain at `http://127.0.0.1:8545` with pre-funded test accounts.

2. **Deploy contracts with test data**:

```bash
npx hardhat run scripts/deploy.js --network localhost
```

This script:
- Deploys MockUSDC, MockPriceFeed, and TuitionPayment contracts
- Whitelists two test students with hashed IDs
- Assigns credit units (4 CU and 3 CU respectively)
- Mints 10,000 test USDC to each student wallet
- Locks the FX rate from the mock Chainlink feed
- Prints the deployed contract addresses for frontend configuration

3. **Update frontend configuration**: Copy the printed addresses into the `CONFIG` object at the top of both `admin.html` and `student.html`:

```javascript
const CONFIG = {
  TUITION_ADDRESS: "<printed TuitionPayment address>",
  USDC_ADDRESS:    "<printed MockUSDC address>",
  RPC_URL:         "http://127.0.0.1:8545",
};
```

4. **Import test accounts into MetaMask**: Use the private keys printed by `npx hardhat node` to import the admin and student accounts into MetaMask. Connect MetaMask to `Localhost 8545`.

5. **Open the frontend**: Open `admin.html` or `student.html` directly in your browser.

---

### Polygon Amoy Testnet

1. **Ensure your `.env` is configured** with `AMOY_RPC_URL`, `DEPLOYER_PRIVATE_KEY`, and `POLYGONSCAN_API_KEY`.

2. **Fund your deployer wallet** with Amoy testnet POL from the [Polygon Faucet](https://faucet.polygon.technology).

3. **Deploy to Amoy**:

```bash
npx hardhat run scripts/deploy.amoy.js --network amoy
```

This script:
- Deploys MockUSDC, MockPriceFeed, and TuitionPayment to Amoy
- Locks the FX rate and sets a payment date (30 days from deployment)
- Verifies all three contracts on PolygonScan (if API key is provided)
- Prints a deployment summary with all addresses and next steps

4. **If the testnet is congested** and transactions fail, increase the gas price in `hardhat.config.js`:

```javascript
amoy: {
  // ...
  gasPrice: 35_000_000_000,  // 35 gwei
},
```

---

## Running Tests

Run the full test suite (25+ tests):

```bash
npx hardhat test
```

Tests cover:
- Deposit functionality (valid deposits, zero amount, unapproved, paused state)
- Deposit cap enforcement (prevents over-deposits beyond calculated fees)
- Deposit rate limiting (1-minute cooldown between deposits)
- Emergency withdrawal (paused-only, CEI pattern, double-withdrawal prevention)
- Privacy hash mappings (duplicate hash/wallet rejection)
- Batch operations (whitelisting, credit unit assignment, payment reset)
- FX rate locking and resetting (Chainlink oracle integration)
- Fee calculation (USDC and JPY conversion)
- End-to-end payment lifecycle (whitelist → deposit → execute → reset → new semester)
- Edge cases (zero credit units, already-paid students, insufficient balance events)

---

## Frontend Usage

### Admin Client (`admin.html`)

The admin dashboard provides three tabs:

**Students Tab**
- View all enrolled students with their CU, fees owed (USDC and JPY), escrow balance, and payment status
- Whitelist individual students (wallet address + student ID) or batch whitelist via CSV-style input
- Assign credit units individually or in batch
- Refund or remove students

**Semester Setup Tab**
- Step 1: Lock the FX rate from the Chainlink oracle (or MockPriceFeed on testnet)
- Step 2: Set the payment deadline
- Step 3: Select eligible students and execute batch payment to the university wallet
- Step 4: Reset semester (clears payment statuses for the next trimester)

**Configuration Tab**
- Update fee per credit unit
- Update university wallet address
- Update Chainlink price feed address
- Emergency pause/unpause controls

### Student Client (`student.html`)

- View assigned credit units, total fees owed in USDC and JPY, and payment deadline
- See escrow deposit progress bar (amount deposited vs amount required)
- Deposit USDC into escrow (two-step: approve + deposit via MetaMask)
- View live and locked FX rates
- Emergency withdraw (available only when the contract is paused)

---

## Smart Contracts

### TuitionPayment.sol

The core escrow-based payment contract with six modules:

| Module | Key Functions | Purpose |
|--------|--------------|---------|
| Identity & Whitelist | `whitelistStudent()`, `batchWhitelist()`, `removeStudent()` | Student registration with keccak256-hashed IDs |
| CU & Fees | `setCreditUnits()`, `batchSetCreditUnits()`, `calculateFees()`, `calculateFeesInJPY()` | Fee assignment and calculation |
| FX Rate | `getLatestRate()`, `lockFxRate()`, `resetLockedFxRate()` | Chainlink oracle integration with staleness check |
| Escrow | `deposit()`, `getStatus()` | USDC deposits with cap enforcement and rate limiting |
| Payment | `executePayment()`, `refundStudent()`, `batchResetPayments()` | Batch settlement to university wallet (max 50 per call) |
| Receipt | Events: `PaymentExecuted`, `Deposit`, `Refund`, etc. | On-chain audit trail on PolygonScan |

### MockPriceFeed.sol

Minimal mock of Chainlink's `AggregatorV3Interface` for local and testnet use. Returns a configurable JPY/USD rate (default: 670000 = 0.0067 USD/JPY at 8 decimals). Uses `block.timestamp` for `updatedAt` so the staleness check always passes.

Since Chainlink does not deploy a JPY/USD price feed on the Polygon Amoy testnet, this mock preserves the full oracle integration flow (`lockFxRate()` → `getLatestRate()` → `latestRoundData()`) end-to-end. The `lockFxRate()` function requires no modification for mainnet deployment where a live Chainlink JPY/USD feed exists.

### MockUSDC.sol

Minimal ERC-20 token mimicking USDC (6 decimals) for testing. Anyone can call `mint()` — this is a test-only contract. In production, students would acquire real USDC through external exchanges.

---

## Deployed Contracts (Amoy Testnet)

| Contract | Address |
|----------|---------|
| TuitionPayment | `0x00F0D684625c023ade1BD3EA4553c1F3A8D44c02` |
| MockPriceFeed | `0x835D121eac88Fa4a59c2bECbDE90a7daa23cf82D` |
| MockUSDC | `0x61B231D28FA48efe5d4De20F32C60ef17Af197Eb` |

All contracts are verified on [Polygon Amoy PolygonScan](https://amoy.polygonscan.com). Source code is publicly readable and inspectable.

---

## Project Structure

```
tuition-dapp/
├── contracts/
│   ├── TuitionPayment.sol      # Core escrow payment contract
│   ├── MockPriceFeed.sol       # Chainlink oracle mock for testnet
│   └── MockUSDC.sol            # Test USDC token (6 decimals)
├── scripts/
│   ├── deploy.js               # Local Hardhat deployment + test data setup
│   └── deploy.amoy.js          # Polygon Amoy testnet deployment + verification
├── test/
│   └── TuitionPayment.test.js  # 25+ unit and integration tests
├── admin.html                  # Admin dashboard (single-file frontend)
├── student.html                # Student portal (single-file frontend)
├── hardhat.config.js           # Hardhat configuration (Solidity 0.8.20, Amoy network)
├── package.json                # Dependencies and npm scripts
├── .env.example                # Environment variable template
├── .gitignore                  # Excludes node_modules, artifacts, .env
└── README.md                   # This file
```

---

## Team

**Group 10** — BAC2002 Blockchain and Cryptocurrency, Singapore Institute of Technology

| Name | Student ID |
|------|-----------|
| Ellie Josepha Lim Shi Ern | 2401756 |
| Hayden Chua Shao En | 2402425 |
| Kannan Karthikeyan | 2402904 |
| Loh Kai Chuin | 2401764 |
| Nurul Zahirah Binte Muhamadnoh | 2401671 |
