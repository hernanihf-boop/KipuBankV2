// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title AggregatorV3Interface
 * @notice Defines the minimum Chainlink V3 interface to use in the mock.
 * @dev Required for the V3AggregatorMock implementation.
 */
interface AggregatorV3Interface {
    function decimals() external view returns (uint8);
    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );
}