# KIPU BANK V2

## ⛽ Gas Optimization Summary

1. The withdraw function
    
    a. Constants (MAX_WITHDRAWAL constant over immutable)
        
        Constant values are resolved at compile time and are embedded directly into the bytecode. 
        This eliminates any run-time access cost for reading state or code during runtime (it is the cheapest way to store fixed values).
    
    b. Order of checks => MAX_WITHDRAWAL before userBalance
        
        The constant limit (cheap access) is verified first before accessing the user's balance in storage (expensive access). 
        This guarantees that if the transaction is going to fail, it does so as quickly and cheaply as possible.
    
    c. Add unchecked (newBalance = userBalance - _amount;)
        
        Since underflow is already guaranteed by the prior check (if (_amount > userBalance)), 
        using unchecked removes the gas cost of Solidity's default safety checks for addition/subtraction.


## ⚙️ Security Optimizations Summary

1. Reentrancy guard 
    
    Import ReentrancyGuard from openzeppelin libs and extend the contract from openzeppelin's ReentrancyGuard allows us to use nonReentrant modifier.
    The nonReentrant modifier is usefull in the withdraw function to avoid reentrancy attacks.

2. Openzepelin's Owneable instead modifier

    Omport Openzepelin's Owneable to allow only owner to interact with key functions.


## 🛫 Step by step to deploy & test in sepolia network

1. First of all we need to have a wallet with Sepolia ETH (testnet ether).

2. Deploy the smart contract (KipuBankV2) in sepolia using remix or other IDE. For this we need to set the constructor params:
    
    a. _ethUsdPriceFeed = The chainlink ETH/USD oracle addres in Sepolia (0x694AA1769357215DE4FAC081bf1f309aDC325306).
    
    b. _bankCapUsd = The capacity bank limit in USD. E.g 10000 USD. (using 8 decimals internally, as Chainlink does)

3. Now we are able to deposit or withdraw ETH, handling the bank total value in usd.

4. Then we need to add a ERC20 token with the correspoding oracle to have support for other currencies. For example, we could add USDC in sepolia this way:
    
    a. USDC (Sepolia Mock) address: 0x1c7D4B196Cb0c7B01d743Fbc6116a902BC5cf5de
   
    b. USDC/USD price feed address: 0x773616E4d11A78F51129900264f1D27E8AbC9552
    Before wa can handle USDC, we need to interact with the USDC's contract to approve this operations calling the function approve(address spender, uint256 amount) 

5. Now we can deposit this allowed ERC20 token and then withdraw them.

6. All the bank public/external functions are allowed to use:
    
    a. deposit() [eth]
    
    b. depositToken() [allowed erc20 token]
    
    c. withdraw() [eth]
    
    d. withdrawToken() [allowed erc20 token]
    
    e. getTotalBankValueUsd() [onlyOwner] [usd]
    
    f. addSupportedToken()
    
    g. setEthPriceFeed()
    
    h. getTokenBalance()
    
    i. getEthBalance()
    
    j. getBankCap()
    
    k. getTotalEthDeposits()
    
    l. getTotalEthWithdrawals()
    
    m. getTotalTokenDeposits()
    
    n. getTotalTokenWithdrawals()


## 💡 Design decisions & trade-offs

1. Use openzeppelin approved interfaces instead of "home made". Delete onlyOwner modifier and use it from openzeppelin. The same for reentrancyGuard.
    
2. Use SafeERC20 to support old "not standard" token that doesnt revert when fail. SafeERC20 handle this for us.
