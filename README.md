# KipuBankV2

⛽ KipuBank Gas Optimization Summary

This document details the gas optimizations implemented in the KipuBank.sol smart contract, ensuring it is a secure and highly efficient contract on the Ethereum Virtual Machine (EVM).

1. Declarations and Constants 
    ##### Optimization 
    constant over immutable

    ##### Location
    MAX_WITHDRAWAL

    ##### Rationale
    Constant values are resolved at compile time and are embedded directly into the bytecode. 
    This eliminates any run-time access cost for reading state or code during runtime (it is the cheapest way to store fixed values).

    ##### Optimization
    Custom Errors

    ##### Location
    Entire Contract

    ##### Rationale
    Using custom errors (error MyError()) instead of traditional require("string") saves a significant amount of gas in failing transactions, as the EVM does not need to store or process the string message.


2. The withdraw Function (Maximum C-E-I Efficiency)
The withdraw function was optimized to follow the C-E-I pattern (Checks, Effects, Interactions) in the most economical way possible.

    ##### Optimization
    Storage Caching

    ##### Location
    uint256 userBalance = balances[user];

    ##### Rationale
    By reading the storage variable (balances[user]) only once into a local stack variable (userBalance), we avoid multiple and costly SLOAD (storage load) operations that would occur if the mapping were accessed multiple times.

    ##### Optimization
    Order of Checks

    ##### Location
    MAX_WITHDRAWAL before userBalance

    ##### Rationale
    The constant limit (cheap access) is verified first before accessing the user's balance in storage (expensive access). 
    This guarantees that if the transaction is going to fail, it does so as quickly and cheaply as possible.

    ##### Optimization
    unchecked Arithmetic

    ##### Location
    newBalance = userBalance - _amount;

    ##### Rationale
    Since underflow is already guaranteed by the prior check (if (_amount > userBalance)), using unchecked removes the gas cost of Solidity's default safety checks for addition/subtraction.

    ##### Optimization
    newBalance Handling

    ##### Location
    uint256 newBalance;

    ##### Rationale
    newBalance is calculated into a local stack variable before the storage update. This ensures that the emit WithdrawalSuccessful uses the correct post-withdrawal balance without needing an additional storage read.

3. The deposit Function (Validation Efficiency)

    ##### Optimization
    
    Direct Capacity Check

    ##### Location
    
    if (address(this).balance > BANK_CAP)

    ##### Rationale 
    
    The EVM adds the transaction's ETH to the contract's balance before executing the first line of the payable function. 
    Therefore, the check is performed directly on the new address(this).balance, eliminating the need to manually add + msg.value and saving gas.