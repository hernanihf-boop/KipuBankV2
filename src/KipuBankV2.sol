//SPDX-License-Identifier: MIT
pragma solidity >=0.8.20 <0.9.0;

import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";


/**
 * @title KipuBank
 * @author Hernán Iannello
 * @notice Smart contract which allows users to deposit ERC20 tokens
 * in a personal vault and withdraw or hold them.
 */
contract KipuBank is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;
    // ====================================================================
    // CONSTANTS & VARIABLES (IMMUTABLE, STATE & STORAGE)
    // ====================================================================

    /**
     * @dev Maximum limit of USD that can be withdrawn in a single transaction.
     */
    uint256 public constant MAX_WITHDRAWAL_USD = 1000 * 1e8;

    /**
     * @dev Maximum amount of time to consider an outdated price feed.
     */
    uint256 private constant MAX_PRICE_FEED_AGE = 1800; // 30 min.

    /**
     * @dev We use the address(0) to represent ETH.
     */
    address private constant ETH_TOKEN_ADDRESS = address(0);

    /**
     * @dev Total capacity of USD that bank can hold.
     * @dev Fixed in deployment to ensure capacity.
     */
    uint256 private immutable BANK_CAP_USD;

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
     * @dev Mapping to tracking the tokens total deposited amount in the bank (stored in native token units).
     */
    mapping(address => uint256) private totalReserves;

    /**
     * @dev Mapping to verify if a token is supported.
     * @dev The key is the token's address.
     */
    mapping(address => bool) private isSupportedToken;

    /**
     * @dev Mapping to register token price feed (oracles).
     */
    mapping(address => AggregatorV3Interface) private tokenPriceFeeds;

    /**
     * @dev Mapping to register the decimals for a supported token.
     */
    mapping(address => uint8) private tokenDecimalsMap;

    /**
     * @dev Mapping to register number of successful deposits made for each token.
     */
    mapping(address => uint256) private totalDeposits;

    /**
     * @dev Mapping to register number of successful withdrawals made for each token.
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
    */
    event DepositSuccessful(address indexed token, address indexed user, uint256 amount);

    /**
    * @dev Emitted when a user successfully withdraws a token.
    * @param token Withdrawal token address.
    * @param user Withdrawal address.
    * @param amount Withdrawn amount (in Wei).
    */
    event WithdrawalSuccessful(address indexed token, address indexed user, uint256 amount);

    /**
    * @dev Emitted when a new token supported is added.
    * @param token Token address.
    */
    event SupportedTokenAdded(address indexed token);

    /**
    * @dev Emitted when a supported price feed is added.
    * @param addr Price feed address.
    */
    event PriceFeedSet(address indexed addr);

    // ====================================================================
    // CUSTOM ERRORS
    // ====================================================================

    /**
     * @dev Issued when a deposit fails because the amount sent is zero.
     */
    error ZeroDeposit();

     /**
     * @dev Issued when a withdraw fails because the amount sent is zero.
     */
    error ZeroWithdraw();

    /**
     * @dev Issued when the deposit exceeds the bank's total limit (BANK_CAP).
     */
    error BankCapExceeded();

    /**
     * @dev Issued when set the bank cap at deployment time if the value is not supported.
     */
    error InvalidBankCapValue();

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
    * @dev Emitted if the token transfer fails.
    * @param token Token the address of the token.
    */
    error TransferFailed(address token);

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
    * @dev Emitted when a price feed address is not supported.
    * @param priceFeed The addres of the price feed.
    */
    error NotSupportedPriceFeed(address priceFeed);

    /**
    * @dev Emitted when a price obtained from price feed is invalid or outdated.
    */
    error InvalidOrOutdatedPrice();

    // ====================================================================
    // MODIFIERS
    // ====================================================================

    modifier onlySupportedToken(address _token) {
        if (_token != ETH_TOKEN_ADDRESS && !isSupportedToken[_token]) {
            revert UnsupportedToken(_token);
        }
        _;
    }

    // ====================================================================
    // CONSTRUCTOR
    // ====================================================================

    /**
    * @dev Constructor that initializes the contract.
    * @param _ethUsdPriceFeed the price feed address.
    * @param _bankCapUsd The total usd limit the contract can handle/accept.
    * @notice Sets the contract owner and the global deposit limit.
    */
    constructor(AggregatorV3Interface _ethUsdPriceFeed, uint256 _bankCapUsd) Ownable(msg.sender) {
        if(address(_ethUsdPriceFeed) == address(0)) revert NotSupportedPriceFeed(address(_ethUsdPriceFeed));
        if (_bankCapUsd == 0) revert InvalidBankCapValue();

        isSupportedToken[ETH_TOKEN_ADDRESS] = true;
        tokenPriceFeeds[ETH_TOKEN_ADDRESS] = AggregatorV3Interface(_ethUsdPriceFeed);
        tokenDecimalsMap[ETH_TOKEN_ADDRESS] = 18;
        BANK_CAP_USD = _bankCapUsd * 1e8; // Use 8 decimal, consistent with Chainlink (e.g., 1000 * 1e8)
        
        emit PriceFeedSet(address(_ethUsdPriceFeed));
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
    * @notice Allows any user to deposit ETH into their personal vault.
    */
    function deposit() public payable {
        uint256 amount = msg.value;
        address user = msg.sender;

        if (amount == 0) revert ZeroDeposit();

        uint256 usdAmount = _convertEthToUsd(amount);
        if (_calculateTotalBankValueUsd() + usdAmount > BANK_CAP_USD) {
            revert BankCapExceeded();
        }

        balances[user][ETH_TOKEN_ADDRESS] += amount;
        totalReserves[ETH_TOKEN_ADDRESS] += amount;
        totalDeposits[ETH_TOKEN_ADDRESS]++;

        emit DepositSuccessful(ETH_TOKEN_ADDRESS, user, amount);
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

        (uint256 usdAmount, ) = _convertTokenToUsd(_token, _amount);
        if (_calculateTotalBankValueUsd() + usdAmount > BANK_CAP_USD) {
            revert BankCapExceeded();
        }

        address user = msg.sender;
        IERC20(_token).safeTransferFrom(user, address(this), _amount);

        balances[user][_token] += _amount;
        totalReserves[_token] += _amount;
        totalDeposits[_token]++;

        emit DepositSuccessful(_token, user, _amount);
    }

    /**
    * @notice Allows the user to withdraw ETH from their personal vault.
    * @param _amount Amount of ETH (in Wei) the user wishes to withdraw.
    */
    function withdraw(uint256 _amount) external nonReentrant {
        if (_amount == 0) revert ZeroWithdraw();

        uint256 usdAmount = _convertEthToUsd(_amount);
        if (usdAmount > MAX_WITHDRAWAL_USD) revert WithdrawalLimitExceeded(MAX_WITHDRAWAL_USD, usdAmount);
    
        address user = msg.sender;
        uint256 userBalance = balances[user][ETH_TOKEN_ADDRESS];
        if (_amount > userBalance) revert InsufficientFunds(userBalance, _amount); 

        unchecked {
            balances[user][ETH_TOKEN_ADDRESS] = userBalance - _amount;
        }
        totalReserves[ETH_TOKEN_ADDRESS] -= _amount;
        totalWithdrawals[ETH_TOKEN_ADDRESS]++;
        
        (bool success, ) = payable(user).call{value: _amount}("");
        if (!success) revert TransferFailed(ETH_TOKEN_ADDRESS);

        emit WithdrawalSuccessful(ETH_TOKEN_ADDRESS, user, _amount);
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
        if (_amount == 0) revert ZeroWithdraw();

        (uint256 usdAmount, ) = _convertTokenToUsd(_token, _amount);
        if (usdAmount > MAX_WITHDRAWAL_USD) revert WithdrawalLimitExceeded(MAX_WITHDRAWAL_USD, usdAmount);

        address user = msg.sender;
        uint256 userBalance = balances[user][_token];
        if (_amount > userBalance) revert InsufficientFunds(userBalance, _amount);

        unchecked {
            balances[user][_token] = userBalance - _amount;
        }
        totalReserves[_token] -= _amount;
        totalWithdrawals[_token]++;

        IERC20(_token).safeTransfer(user, _amount);

        emit WithdrawalSuccessful(_token, user, _amount);
    }

    /**
     * @notice Retrieves the total value of the reserves in USD.
     * @dev Only owner function. 
     * @return The total value of the bank vault/reserves in USD (using 8 decimals).
     */
    function getTotalBankValueUsd() external view onlyOwner returns (uint256) {
        return _calculateTotalBankValueUsd(); 
    }

    /**
    * @notice Adds a ERC20 token to the supported list.
    * @param _token The ERC20 token address.
    * @param _priceFeed The ERC20 price feed
    */
    function addSupportedToken(address _token, address _priceFeed) external onlyOwner {
        if(address(_priceFeed) == address(0)) revert NotSupportedPriceFeed(address(_priceFeed));
        if (_token == ETH_TOKEN_ADDRESS || isSupportedToken[_token]) revert TokenAlreadySupported(_token);
        
        isSupportedToken[_token] = true;
        tokenPriceFeeds[_token] = AggregatorV3Interface(_priceFeed);
        supportedTokens.push(_token);
        tokenDecimalsMap[_token] = IERC20Metadata(_token).decimals(); 

        emit SupportedTokenAdded(_token);
    }

    /**
    * @notice Sets the price feed adress. Only allowed to owner.
    * @param _priceFeed The price feed adress.
    */
    function setEthPriceFeed(address _priceFeed) external onlyOwner {
        if(_priceFeed == address(0)) revert NotSupportedPriceFeed(address(_priceFeed));
        tokenPriceFeeds[ETH_TOKEN_ADDRESS] = AggregatorV3Interface(_priceFeed); // sepolia: 0x694AA1769357215DE4FAC081bf1f309aDC325306
        
        emit PriceFeedSet(_priceFeed);
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
    * @notice Returns the ETH user balance (in Wei).
    * @return The user's balance.
    */
    function getEthBalance() public view returns (uint256) {
        return balances[msg.sender][ETH_TOKEN_ADDRESS];
    }

    /**
    * @notice Returns the maximum total ETH capacity the bank can hold.
    * @return The contract's bank capacity (in Wei).
    */
    function getBankCap() public view returns (uint256) {
        return BANK_CAP_USD;
    }

    /**
    * @notice Returns the total number of eth deposits that have been made.
    * @return The total deposit count.
    */
    function getTotalEthDeposits() public view returns (uint256) {
        return totalDeposits[ETH_TOKEN_ADDRESS];
    }

    /**
    * @notice Returns the total number of eth withdrawals that have been made.
    * @return The total withdrawal count.
    */
    function getTotalEthWithdrawals() public view returns (uint256) {
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
     * @dev Calculates the current total value of all reserves in the bank (in USD, 8 decimals).
     */
    function _calculateTotalBankValueUsd() private view returns (uint256 currentTotalUsd) {
        if (totalReserves[ETH_TOKEN_ADDRESS] > 0) {
            currentTotalUsd += _convertEthToUsd(totalReserves[ETH_TOKEN_ADDRESS]);
        }

        for (uint256 i = 0; i < supportedTokens.length; i++) {
            address token = supportedTokens[i];
            uint256 reserve = totalReserves[token];
            if (reserve > 0) {
                (uint256 usdValue, ) = _convertTokenToUsd(token, reserve);
                currentTotalUsd += usdValue;
            }
        }
    }

    /**
     * @dev Obtain the ETH/USD price from price feed.
     * @return price in USD with 8 decimals (2000e8 = $2000).
     */
    function _getEthUsdPrice() private view returns (uint256) {
        (, int256 ethUsdPrice, , uint256 updatedAt, ) = tokenPriceFeeds[ETH_TOKEN_ADDRESS].latestRoundData();
        if (ethUsdPrice <= 0 || block.timestamp - updatedAt > MAX_PRICE_FEED_AGE) {
            revert InvalidOrOutdatedPrice(); 
        }
        return uint256(ethUsdPrice);
    }

    /**
     * @dev Convert an amount from ETH (18 decimals) to USD (8 decimals) using the price feed.
     * @param ethAmount Eth amount (in wei).
     * @return Equivalent value in USD (using 8 decimals).
     */
    function _convertEthToUsd(uint256 ethAmount) private view returns (uint256) {
        uint256 ethUsdPrice = _getEthUsdPrice();
        return (ethAmount * ethUsdPrice) / (10 ** 10);
    }

    /**
     * @dev Get the token price and decimals from the feed.
     * @param _token Token address.
     * @return price the token price.
     * @return feedDecimals the token decimals.
     */
    function _getTokenPriceFeedData(address _token) private view returns (uint256 price, uint8 feedDecimals) {
        AggregatorV3Interface tokenPriceFeed = tokenPriceFeeds[_token];
        ( , int256 tokenUsdPrice, , uint256 updatedAt, ) = tokenPriceFeed.latestRoundData();
        if (tokenUsdPrice <= 0 || block.timestamp - updatedAt > MAX_PRICE_FEED_AGE) {
            revert InvalidOrOutdatedPrice();
        }

        feedDecimals = uint8(tokenPriceFeed.decimals());
        price = uint256(tokenUsdPrice);
    }

    /**
     * @dev Convert an amount from Token to USD using the price feed.
     * @param _token Token address.
     * @param _amount Token amount.
     * @return usdAmount The value in USD (using 8 decimals)
     * @return tokenDecimals The token's decimals.
     */
    function _convertTokenToUsd(address _token, uint256 _amount) private view returns (uint256 usdAmount, uint8 tokenDecimals) {
        if (_token == ETH_TOKEN_ADDRESS) return (_convertEthToUsd(_amount), 18);

        (uint256 tokenUsdPrice, ) = _getTokenPriceFeedData(_token);
        tokenDecimals = tokenDecimalsMap[_token]; 
        usdAmount = (_amount * tokenUsdPrice) / (10 ** tokenDecimals);
        
        return (usdAmount, tokenDecimals);
    }
}
