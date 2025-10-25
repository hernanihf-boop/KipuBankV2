//SPDX-License-Identifier: MIT
pragma solidity >=0.8.20 <0.9.0;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";

/**
 * @title ERC20Mock
 * @notice A simple ERC20 to simulate a real token in a testing environment.
 * @dev Allow the 'mint' function to give testing user token to test.
 */
contract ERC20Mock is ERC20 {
    using SafeMath for uint256;

    uint8 private constant TOKEN_DECIMAL = 18;

    string public tokenName;
    string public tokenSymbol;

    /**
     * @notice Constructor.
     * @dev Starts the token with name, symbol and mint an intial quantity to the deployment account.
     */
    constructor(string memory _tokenName, string memory _tokenSymbol) ERC20(_tokenName, _tokenSymbol) {
        tokenName = _tokenName;
        tokenSymbol = _tokenSymbol;
        _mint(msg.sender, 1000000 * (10 ** TOKEN_DECIMAL));
    }

    /**
     * @notice Allows to mint token to any address.
     * @dev With this function we can give tokens to different addresses for testing purposes.
     * @param to Address who receives the tokens.
     * @param amount Amount of tokens to mint.
     */
    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }

    function decimals() public pure override returns (uint8) {
        return TOKEN_DECIMAL;
    }
}