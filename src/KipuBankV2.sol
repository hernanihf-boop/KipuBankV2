//SPDX-License-Identifier: MIT
pragma solidity >=0.8.20 <0.9.0;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title KipuBank
 * @author Hernán Iannello
 * @notice Smart contract which allows users to deposit ETH
 * in a personal vault and withdraw them with a limit per transaction.
 */
contract KipuBank is ReentrancyGuard {
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

    // We use address(0) to represent ETH
    address private constant ETH_TOKEN_ADDRESS = address(0);

    /**
     * @dev Total capacity of ETH that bank can hold (in Wei).
     * @dev Fixed in deployment to ensure capacity.
     */
    uint256 private immutable BANK_CAP;

    /**
     * @dev List of ERC20 tokens supported.
     */
    address[] public supportedTokens;

    /**
     * @dev Mapping that saves other mapping of token addres and balance.
     * @dev Mapping: userAddress => tokenAddress => balance
     */
    mapping(address => mapping(address => uint256)) private balances;

    /**
     * @dev Mapping to verify if a token is supported.
     * @dev The key is the token's address.
     */
    mapping(address => bool) private isSupportedToken;

    /**
     * @dev Mapping to register number of successful deposits made.
     */
    mapping(address => uint256) private totalDeposits;

    /**
     * @dev Mapping to register number of successful withdrawals made.
     */
    mapping(address => uint256) private totalWithdrawals;

    // ====================================================================
    // EVENTS
    // ====================================================================

    /**
    * @dev Emitted when a user successfully deposits a token.
    * @param token Depositing token address.
    * @param user Depositing address.
    * @param amount Amount deposited (in Wei).
    * @param newBalance New user balance.
    */
    event DepositSuccessful(address indexed token, address indexed user, uint256 amount, uint256 newBalance);

    /**
    * @dev Emitted when a user successfully withdraws a token.
    * @param token Withdrawal token address.
    * @param user Withdrawal address.
    * @param amount Withdrawn amount (in Wei).
    * @param newBalance New user balance.
    */
    event WithdrawalSuccessful(address indexed token, address indexed user, uint256 amount, uint256 newBalance);

    /**
    * @dev Emitted when a new token is supported.
    * @param token Token address.
    */
    event SupportedTokenAdded(address indexed token);

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

    /**
    * @dev Emitted when a token is not supported.
    * @param token The addres of the token.
    */
    error UnsupportedToken(address token);

    /**
    * @dev Emitted when a token is already supported.
    * @param token The addres of the token.
    */
    error TokenAlreadySupported(address token);
    
    /**
    * @dev Emitted when a token transfer is failed.
    * @param token The addres of the token.
    */
    error TokenTransferFailed(address token);

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

    modifier onlySupportedToken(address _token) {
        if (!isSupportedToken[_token]) {
            revert UnsupportedToken(_token);
        }
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
    * @notice Adds a ERC20 token to the supported list.
    * @param _token The ERC20 token address.
    */
    function addSupportedToken(address _token) external onlyOwner {
        if (_token == ETH_TOKEN_ADDRESS || isSupportedToken[_token]) revert TokenAlreadySupported(_token);
        isSupportedToken[_token] = true;
        supportedTokens.push(_token);
        emit SupportedTokenAdded(_token);
    }

    /**
    * @notice Returns the ERC20 token user balance.
    * @param _token The ERC20 token address.
    * @return The user balance in that token.
    */
    function getTokenBalance(address _token) external view onlySupportedToken(_token) returns (uint256) {
        return balances[msg.sender][_token];
    }

    /**
    * @notice Allows the user to withdraw ETH from their personal vault.
    * @param _amount Amount of ETH (in Wei) the user wishes to withdraw.
    */
    function withdraw(uint256 _amount) external nonReentrant {
        if (_amount == 0) revert ZeroDeposit();
        if (_amount > MAX_WITHDRAWAL) {
            revert WithdrawalLimitExceeded(MAX_WITHDRAWAL, _amount);
        }
    
        address user = msg.sender;
        uint256 userBalance = balances[user][ETH_TOKEN_ADDRESS];
        if (_amount > userBalance) {
            revert InsufficientFunds(userBalance, _amount);
        }

        uint256 newBalance;
        unchecked {
            newBalance = userBalance - _amount;
            balances[user][ETH_TOKEN_ADDRESS] = newBalance;
        }
        totalWithdrawals[ETH_TOKEN_ADDRESS]++;
        
        (bool success, ) = payable(user).call{value: _amount}("");
        if (!success) {
            revert TransferFailed();
        }
        emit WithdrawalSuccessful(ETH_TOKEN_ADDRESS, user, _amount, newBalance);
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

        balances[user][ETH_TOKEN_ADDRESS] += amount;
        totalDeposits[ETH_TOKEN_ADDRESS]++;
        emit DepositSuccessful(ETH_TOKEN_ADDRESS, user, amount, balances[user][ETH_TOKEN_ADDRESS]);
    }

    /**
    * @notice Withdraws tokens ERC20 from users vault.
    * @param _token ERC20 token address.
    * @param _amount Amount to withdraw (in token units).
    */
    function withdrawToken(
        address _token,
        uint256 _amount
    ) external onlySupportedToken(_token) nonReentrant {
        if (_token == ETH_TOKEN_ADDRESS) return;
        if (_amount == 0) revert ZeroDeposit();
        if (_amount > MAX_WITHDRAWAL) {
            revert WithdrawalLimitExceeded(MAX_WITHDRAWAL, _amount);
        }

        address user = msg.sender;
        uint256 userBalance = balances[user][_token];
        if (_amount > userBalance) {
            revert InsufficientFunds(userBalance, _amount);
        }

        uint256 newBalance;
        unchecked {
            newBalance = userBalance - _amount;
            balances[user][_token] = userBalance - _amount;
        }

        IERC20 token = IERC20(_token);
        bool success = token.transfer(user, _amount); // TODO: Consider use SafeERC20 openzeppelin contract
        if (!success) revert TokenTransferFailed(_token);

        emit WithdrawalSuccessful(_token, user, _amount, newBalance);
    }

    /**
    * @notice Deposits ERC20 tokens in the users vault.
    * @param _token ERC20 token address.
    * @param _amount Amount to deposit (in token units).
    */
    function depositToken(
        address _token,
        uint256 _amount
    ) external onlySupportedToken(_token) {
        if (_amount == 0) revert ZeroDeposit();
        IERC20 token = IERC20(_token);

        address user = msg.sender;
        bool success = token.transferFrom(user, address(this), _amount);
        if (!success) {
            revert TokenTransferFailed(_token);
        }

        uint256 newBalance = balances[user][_token] + _amount;
        balances[user][_token] = newBalance;
        emit DepositSuccessful(_token, user, _amount, newBalance);
    }

    /**
    * @notice Returns the ETH user balance (in Wei).
    * @return The user's balance.
    */
    function getEthBalance() public view returns (uint256) {
        return balances[msg.sender][ETH_TOKEN_ADDRESS];
    }

    /**
    * @notice Returns the total number of deposits that have been made.
    * @return The total deposit count.
    */
    function getTotalDeposits() public view returns (uint256) {
        return totalDeposits[ETH_TOKEN_ADDRESS];
    }

    /**
    * @notice Returns the total number of withdrawals that have been made.
    * @return The total withdrawal count.
    */
    function getTotalWithdrawals() public view returns (uint256) {
        return totalWithdrawals[ETH_TOKEN_ADDRESS];
    }

    /**
    * @notice Returns the total number of token deposits that have been made.
    * @param _token ERC20 token address.
    * @return The total deposit count.
    */
    function getTotalTokenDeposits(address _token) public view returns (uint256) {
        return totalDeposits[_token];
    }

    /**
    * @notice Returns the total number of token withdrawals that have been made.
    * @param _token ERC20 token address.
    * @return The total withdrawal count.
    */
    function getTotalTokenWithdrawals(address _token) public view returns (uint256) {
        return totalWithdrawals[_token];
    }

    /**
    * @notice Returns the maximum total ETH capacity the bank can hold.
    * @return The contract's bank capacity (in Wei).
    */
    function getBankCap() public view returns (uint256) {
        return BANK_CAP;
    }
}
