//SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

/**
 * @title KipuBank
 * @author Hernán Iannello
 * @notice Smart contract which allows users to deposit ETH
 * in a personal vault and withdraw them with a limit per transaction.
 */
contract KipuBank {
    // ====================================================================
    // VARIABLES (IMMUTABLE, STATE & STORAGE)
    // ====================================================================

    /**
     * @dev Address of the contract owner. This is set during deployment.
     */
    address public immutable owner;

    /**
     * @dev Maximum limit of ETH that can be withdrawn in a single transaction.
     */
    uint256 public constant MAX_WITHDRAWAL = 0.5 ether;

    /**
     * @dev Total capacity of ETH that bank can hold (in Wei).
     * @dev Fixed in deployment to ensure capacity.
     */
    uint256 private immutable BANK_CAP;

    /**
     * @dev Mapping that saves each user's personal ETH balance (in Wei).
     * @dev The key is the user's address.
     */
    mapping(address => uint256) private balances;

    /**
     * @dev Number of successful deposits made.
     */
    uint256 private totalDeposits;

    /**
     * @dev Number of successful withdrawals made.
     */
    uint256 private totalWithdrawals;

    // ====================================================================
    // EVENTS
    // ====================================================================

    /**
    * @dev Emitted when a user successfully deposits ETH.
    * @param user Depositing address.
    * @param amount Amount deposited (in Wei).
    * @param newBalance New user balance.
    */
    event DepositSuccessful(address indexed user, uint256 amount, uint256 newBalance);

    /**
    * @dev Emitted when a user successfully withdraws ETH.
    * @param user Withdrawal address.
    * @param amount Withdrawn amount (in Wei).
    * @param newBalance New user balance.
    */
    event WithdrawalSuccessful(address indexed user, uint256 amount, uint256 newBalance);

    // ====================================================================
    // CUSTOM ERRORS
    // ====================================================================

    /**
     * @dev Issued when a deposit fails because the amount sent is zero.
     */
    error ZeroDeposit();

    /**
     * @dev Issued when the deposit exceeds the bank's total limit (BANK_CAP).
     */
    error BankCapExceeded();

    /**
    * @dev Emitted when the user attempts to withdraw more than they have in their vault.
    * @param requested Requested.
    * @param available Total available in the vault.
    */
    error InsufficientFunds(uint256 available, uint256 requested);

    /**
    * @dev Issued when a withdrawal exceeds the maximum transaction limit (MAX_WITHDRAWAL).
    * @param limit Maximum allowed per withdrawal.
    * @param requested Amount the user is attempting to withdraw.
    */
    error WithdrawalLimitExceeded(uint256 limit, uint256 requested);

    /**
    * @dev Emitted if the transfer of native ETH to the user fails.
    */
    error TransferFailed();

    /**
    * @dev Emitted when a function call is not made by the owner of the address.
    * @param caller The caller of the function.
    * @param owner The owner of the address.
    */
    error UnauthorizedCaller(address caller, address owner);

    // ====================================================================
    // MODIFIERS
    // ====================================================================

    /**
     * @dev Modifier to validate that only the owner can call the function.
     */
    modifier onlyOwner() {
      if (msg.sender != owner) revert UnauthorizedCaller(msg.sender, owner);
      _;
   }

    // ====================================================================
    // CONSTRUCTOR
    // ====================================================================

    /**
    * @dev Constructor that initializes the contract.
    * @param _bankCap The total deposit limit the contract can accept (in ETH).
    * @notice Sets the contract owner and the global deposit limit.
    */
    constructor(uint256 _bankCap) {
        owner = msg.sender;
        BANK_CAP = _bankCap * 1 ether; // Converts the input (in ETH) to Wei
    }

    // ====================================================================
    // FALLBACK / RECEIVE 
    // ====================================================================

    /**
    * @dev The 'receive' function is executed when someone sends ETH to the contract
    * without specifying a function to call.
    * In this case, it simply calls the 'deposit' function.
    * @notice Allows you to simply deposit ETH without specifying the 'deposit' function.
    */
    receive() external payable {
        deposit();
    }

    // ====================================================================
    // FUNCTIONS
    // ====================================================================

    /**
    * @notice Allows the user to withdraw ETH from their personal vault.
    * @param _amount Amount of ETH (in Wei) the user wishes to withdraw.
    */
    function withdraw(uint256 _amount) external {
        if (_amount > MAX_WITHDRAWAL) {
            revert WithdrawalLimitExceeded(MAX_WITHDRAWAL, _amount);
        }
    
        address user = msg.sender;
        uint256 userBalance = balances[user];
        if (_amount > userBalance) {
            revert InsufficientFunds(userBalance, _amount);
        }

        uint256 newBalance;
        unchecked {
            newBalance = userBalance - _amount;
            balances[user] = newBalance;
        }
        totalWithdrawals++;
        
        (bool success, ) = payable(user).call{value: _amount}("");
        if (!success) {
            revert TransferFailed();
        }
        emit WithdrawalSuccessful(user, _amount, newBalance);
    }

    /**
    * @notice Allows any user to deposit ETH into their personal vault.
    */
    function deposit() public payable {
        uint256 amount = msg.value;
        address user = msg.sender;

        if (amount == 0) {
            revert ZeroDeposit();
        }

        if (address(this).balance > BANK_CAP) {
            revert BankCapExceeded();
        }

        balances[user] += amount;
        totalDeposits++;
        emit DepositSuccessful(user, amount, balances[user]);
    }

    /**
    * @notice Returns the ETH balance of the user calling the function (in Wei).
    * @return The user's balance.
    */
    function getMyBalance() public view returns (uint256) {
        return balances[msg.sender];
    }

    /**
    * @notice Returns the total number of deposits that have been made.
    * @return The total deposit count.
    */
    function getTotalDeposits() public view returns (uint256) {
        return totalDeposits;
    }

    /**
    * @notice Returns the total number of withdrawals that have been made.
    * @return The total withdrawal count.
    */
    function getTotalWithdrawals() public view returns (uint256) {
        return totalWithdrawals;
    }

    /**
    * @notice Returns the maximum total ETH capacity the bank can hold.
    * @return The contract's bank capacity (in Wei).
    */
    function getBankCap() public view returns (uint256) {
        return BANK_CAP;
    }
}
