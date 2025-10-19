// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/**
 * @title Contrato KipuBank (v.TP4)
 * @author Agustín Cerdá
 */

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract KipuBank is AccessControl, Pausable { 
    /** VARIABLES */
 
    // mapping multi-token: usuario -> token -> balance
    mapping(address user => mapping(address token => uint256 amount)) private s_balances;
    // address(0) representa ETH
    // amount -> cuanto tiene depositado el usuario en ese token

    uint256 public immutable MIN_RETIRO = 0.001 ether;
    uint256 public immutable MAX_RETIRO = 10 ether;

    uint256 public bankCapUSD; // Límite total del banco en USD
    uint256 public totalDeposits;
    uint256 public totalWithdrawals;
    uint256 public totalBankUSD; // total en USD del banco, se actualiza dinámicamente

    /// @dev identificador del rol de pauser
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE"); // hash único para representar el rol

    /// @notice mapping token => Chainlink price feed
    mapping(address token => AggregatorV3Interface) public priceFeeds;

    /*//////////////////////////////////////////////////////////////
                                Eventos
    //////////////////////////////////////////////////////////////*/

    event Deposit(address indexed user, address indexed token, uint256 amount);
    event Withdraw(address indexed user, address indexed token, uint256 amount);
    event BankCapUpdated(uint256 oldCapUSD, uint256 newCapUSD);

    /*//////////////////////////////////////////////////////////////
                                Errores
    //////////////////////////////////////////////////////////////*/

    error InsufficientBalance(uint256 requested, uint256 available);
    error TransferFailed(bytes errorData);
    error AmountTooSmall(uint256 requested, uint256 minAllowed);
    error AmountTooLarge(uint256 requested, uint256 maxAllowed);
    error DepositLimitReached(uint256 requestedTotalUSD, uint256 bankCapUSD);
    error ContractPaused();
    error NoPriceFeed(address token);
    error OracleCompromised();
    error StalePrice();

    /*//////////////////////////////////////////////////////////////
                                CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(uint256 _bankCapUSD) { 
        bankCapUSD = _bankCapUSD;
        // delegación de roles
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(PAUSER_ROLE, msg.sender);
    }

    /*//////////////////////////////////////////////////////////////
                                Funciones de precio USD
    //////////////////////////////////////////////////////////////*/

    /// @notice Asignar un price feed Chainlink a un token
    function setPriceFeed(address token, address feed) external onlyRole(DEFAULT_ADMIN_ROLE) {
        priceFeeds[token] = AggregatorV3Interface(feed);
    }

    /// @notice Obtiene el precio en USD del token (una unidad del token)
    function getTokenPriceUSD(address token) public view returns (uint256 price, uint8 decimals) {
        AggregatorV3Interface feed = priceFeeds[token];
        if(address(feed) == address(0)) revert NoPriceFeed(token);

        (, int256 answer,, uint256 updatedAt,) = feed.latestRoundData();
        if(answer <= 0) revert OracleCompromised();
        if(block.timestamp - updatedAt > 3600) revert StalePrice();

        price = uint256(answer);
        decimals = feed.decimals();
    }

    /// @notice Convierte cantidad de token a USD usando Chainlink
    function getValueInUSD(address token, uint256 amount) public view returns (uint256) {
        (uint256 price, uint8 decimals) = getTokenPriceUSD(token);
        return (amount * price) / (10 ** decimals);
    }

    /// @notice Obtiene el valor total en USD de todos los depósitos en el banco 
    function getTotalBankValueUSD() public view returns (uint256 totalValueUSD) {
        return totalBankUSD;
    }

    /*//////////////////////////////////////////////////////////////
                                Depósitos Nativos (ETH)
    //////////////////////////////////////////////////////////////*/

    receive() external payable {
        depositETH();
    }

    fallback() external payable {
        depositETH();
    }

    function depositETH() public payable whenNotPaused {
        uint256 valueUSD = getValueInUSD(address(0), msg.value);
        if(totalBankUSD + valueUSD > bankCapUSD) revert DepositLimitReached(totalBankUSD + valueUSD, bankCapUSD);

        _deposit(msg.sender, address(0), msg.value);
    }

    /*//////////////////////////////////////////////////////////////
                                Depósitos ERC20
    //////////////////////////////////////////////////////////////*/

    function depositToken(address token, uint256 amount) external whenNotPaused {
        if(amount == 0) revert TransferFailed("");
        uint256 valueUSD = getValueInUSD(token, amount);
        if(totalBankUSD + valueUSD > bankCapUSD) revert DepositLimitReached(totalBankUSD + valueUSD, bankCapUSD);

        bool success = IERC20(token).transferFrom(msg.sender, address(this), amount);
        if(!success) revert TransferFailed("");

        _deposit(msg.sender, token, amount);
    }

    /*//////////////////////////////////////////////////////////////
                                Retiros Nativos (ETH)
    //////////////////////////////////////////////////////////////*/

    function withdrawETH(uint256 amount) external whenNotPaused {
        if (amount < MIN_RETIRO) revert AmountTooSmall(amount, MIN_RETIRO);
        if (amount > MAX_RETIRO) revert AmountTooLarge(amount, MAX_RETIRO);

        uint256 balance = s_balances[msg.sender][address(0)];
        if (balance < amount) revert InsufficientBalance(amount, balance);

        _withdraw(msg.sender, address(0), amount);

        (bool success, bytes memory err) = payable(msg.sender).call{value: amount}("");
        if (!success) revert TransferFailed(err);
    }

    /*//////////////////////////////////////////////////////////////
                                Retiros ERC20
    //////////////////////////////////////////////////////////////*/

    function withdrawToken(address token, uint256 amount) external whenNotPaused {
        uint256 balance = s_balances[msg.sender][token];
        if (balance < amount) revert InsufficientBalance(amount, balance);

        _withdraw(msg.sender, token, amount);

        bool success = IERC20(token).transfer(msg.sender, amount);
        if(!success) revert TransferFailed("");
    }

    /*//////////////////////////////////////////////////////////////
                        Funciones privadas de contabilidad interna
    //////////////////////////////////////////////////////////////*/

    function _deposit(address user, address token, uint256 amount) private {
        s_balances[user][token] += amount;

        // actualizar totalBankUSD
        uint256 valueUSD = getValueInUSD(token, amount);
        totalBankUSD += valueUSD;

        totalDeposits += 1;
        emit Deposit(user, token, amount);
    }

    function _withdraw(address user, address token, uint256 amount) private {
        s_balances[user][token] -= amount;

        // actualizar totalBankUSD
        uint256 valueUSD = getValueInUSD(token, amount);
        totalBankUSD -= valueUSD;

        totalWithdrawals += 1;
        emit Withdraw(user, token, amount);
    }

    /*//////////////////////////////////////////////////////////////
                                Funciones de control
    //////////////////////////////////////////////////////////////*/

    function pauseBank() external onlyRole(PAUSER_ROLE) {
        _pause(); 
        emit Paused(msg.sender);
    }

    function unpauseBank() external onlyRole(PAUSER_ROLE) {
        _unpause(); 
        emit Unpaused(msg.sender);
    }

    function setBankCapUSD(uint256 newCapUSD) external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 oldCap = bankCapUSD;
        bankCapUSD = newCapUSD;
        emit BankCapUpdated(oldCap, newCapUSD);
    }   

    /*//////////////////////////////////////////////////////////////
                                View
    //////////////////////////////////////////////////////////////*/

    function getBalance(address user, address token) external view returns (uint256) {
        return s_balances[user][token];
    }
}
