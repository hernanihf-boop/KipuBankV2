//SPDX-License-Identifier: MIT
pragma solidity >=0.8.20 <0.9.0;

import {AggregatorV3Interface} from "./AggregatorV3Interface.sol";

/**
 * @title AggregatorV3Mock
 * @notice Mock contract to simulate the chainlink's AggregatorV3Interface.
 * @dev Allow user to manually stablish price and update timestamp.
 */
contract AggregatorV3Mock is AggregatorV3Interface  {
    uint8 public decimals;
    int256 internal answer;
    uint256 internal updatedAt;
    uint256 internal version = 1;

    /**
     * @notice Constructor.
     * @param _decimals The numerbe of decimal (recomendation: 8) to inform.
     * @param _initialAnswer The final price (e.g., 3000 USD in 8 decimals is 300000000000).
     */
    constructor(uint8 _decimals, int256 _initialAnswer) {
        decimals = _decimals;
        answer = _initialAnswer;
        updatedAt = block.timestamp;
    }

    /**
     * @notice Simulates the function that retrieves tha latest data from the oracle.
     * @dev KipuBank calls this function to obtain the price.
     */
    function latestRoundData()
        public
        view
        returns (
            uint80 roundId,
            int256 answer_,
            uint256 startedAt,
            uint256 updatedAt_,
            uint80 answeredInRound
        )
    {
        roundId = 1; 
        answer_ = answer; 
        startedAt = updatedAt; 
        updatedAt_ = updatedAt; 
        answeredInRound = 1;
    }

    /**
     * @notice Function for the contract owner, allows to change the price in testing time.
     * @param _newAnswer The new simulated price.
     */
    function updateAnswer(int256 _newAnswer) public {
        answer = _newAnswer;
        updatedAt = block.timestamp;
        version++;
    }

    /**
     * @notice Aux function to simulate an outdated price.
     * @dev Usefull to prove consistency and validation in KipuBank.
     */
    function setUpdatedAt(uint256 _newTimestamp) public {
        updatedAt = _newTimestamp;
    }
}
