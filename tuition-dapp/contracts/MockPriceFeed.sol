// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title MockPriceFeed
 * @notice Minimal mock of Chainlink's AggregatorV3Interface for local testing.
 *         Returns a configurable price and uses block.timestamp for updatedAt
 *         so the staleness check in TuitionPayment always passes.
 */
contract MockPriceFeed {
    int256 private _price;
    uint8  private _decimals;

    constructor(int256 initialPrice, uint8 feedDecimals) {
        _price    = initialPrice;
        _decimals = feedDecimals;
    }

    /// @notice Matches Chainlink's AggregatorV3Interface signature
    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        return (1, _price, block.timestamp, block.timestamp, 1);
    }

    function decimals() external view returns (uint8) {
        return _decimals;
    }

    /// @notice Helper to change the price mid-test if needed
    function setPrice(int256 newPrice) external {
        _price = newPrice;
    }
}
