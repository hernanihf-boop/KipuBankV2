# KipuBankV2

## ⛽ Gas Optimization Summary

This document details the gas optimizations implemented in the KipuBank.sol smart contract, ensuring it is a secure and highly efficient contract on the Ethereum Virtual Machine (EVM).

1. The withdraw function
    
    a. Constants (MAX_WITHDRAWAL constant over immutable)
        
        Constant values are resolved at compile time and are embedded directly into the bytecode. 
        This eliminates any run-time access cost for reading state or code during runtime (it is the cheapest way to store fixed values).
    
    b. Storage Caching (Read balances[user] only once)
        
        By reading the storage variable (balances[user]) only once into a local stack variable (userBalance), 
        we avoid multiple storage load operations that would occur if the mapping were accessed multiple times.
    
    c. Order of checks => MAX_WITHDRAWAL before userBalance
        
        The constant limit (cheap access) is verified first before accessing the user's balance in storage (expensive access). 
        This guarantees that if the transaction is going to fail, it does so as quickly and cheaply as possible.
    
    d. Add unchecked (newBalance = userBalance - _amount;)
        
        Since underflow is already guaranteed by the prior check (if (_amount > userBalance)), 
        using unchecked removes the gas cost of Solidity's default safety checks for addition/subtraction.
    
    e. newBalance Handling => uint256 newBalance;
        
        newBalance is calculated into a local stack variable before the storage update. 
        This ensures that the emit WithdrawalSuccessful uses the correct post-withdrawal balance without needing an additional storage read.

2. The deposit Function 
    
    a. Validation Efficiency
        * Direct Capacity Check (if (address(this).balance > BANK_CAP))    
            
            The EVM adds the transaction's ETH to the contract's balance before executing the first line of the payable function. 
            Therefore, the check is performed directly on the new address(this).balance, eliminating the need to manually add + msg.value and saving gas.


## ⚙️ Security Optimizations Summary

1. Reentrancy guard 
    
    Import ReentrancyGuard from openzeppelin libs and extend the contract from openzeppelin's ReentrancyGuard allows us to use nonReentrant modifier.
    The nonReentrant modifier is usefull in the withdraw function to avoid reentrancy attacks.

