// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {Initializable} from "openzeppelin-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "openzeppelin-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "openzeppelin-upgradeable/access/OwnableUpgradeable.sol";
import {AccessControlUpgradeable} from "openzeppelin-upgradeable/access/AccessControlUpgradeable.sol";

import {IRabbitX} from "src/interfaces/IRabbitx.sol";

/// @title Pool implementation
/// @author The Elixir Team
/// @custom:security-contact security@elixir.finance
/// @notice Pool implementation logic for RabbitX minimal proxy pools.
contract RabbitXPool is Initializable, UUPSUpgradeable, OwnableUpgradeable, AccessControlUpgradeable {
    /*//////////////////////////////////////////////////////////////
                                VARIABLES
    //////////////////////////////////////////////////////////////*/

    IRabbitX public rabbit;
    IERC20 public paymentToken;

    uint256 public constant ADMIN_ROLE = 0;
    uint256 public constant TRADER_ROLE = 1;
    uint256 public constant DEPOSITOR_ROLE = 2;

    mapping(address => mapping(uint256 => bool)) public signers;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event Deposit(address indexed depositor, uint256 amount);
    event AddRole(address indexed user, uint256 indexed role);
    event RemoveRole(address indexed user, uint256 indexed role);
    event WithdrawTo(address indexed to, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Prevent the implementation contract from being initialized.
    /// @dev The proxy contract state will still be able to call this function because the constructor does not affect the proxy state.
    constructor() {
        _disableInitializers();
    }

    /*//////////////////////////////////////////////////////////////
                               INITIALIZER
    //////////////////////////////////////////////////////////////*/

    /// @notice No constructor in upgradable contracts, so initialized with this function.
    function initialize(address _owner, address _rabbit, address _paymentToken) public initializer {
        __UUPSUpgradeable_init();
        __Ownable_init(_owner);

        signers[_owner][ADMIN_ROLE] = true;
        signers[_owner][DEPOSITOR_ROLE] = true;
        rabbit = IRabbitX(_rabbit);
        paymentToken = IERC20(_paymentToken);
    }

    /*//////////////////////////////////////////////////////////////
                        DEPOSIT/WITHDRAWAL ENTRY
    //////////////////////////////////////////////////////////////*/

    /// @notice Deposits funds into the pool, which is redirected to RabbitX.
    /// @param amount The amount of tokens to deposit.
    function deposit(uint256 amount) external {
        require(signers[msg.sender][DEPOSITOR_ROLE], "NOT_A_DEPOSITOR");
        emit Deposit(msg.sender, amount);
        paymentToken.approve(address(rabbit), amount);
        rabbit.deposit(amount);
    }

    /// @notice Deposits funds into the pool, which is redirected to RabbitX.
    /// @dev The vault must already have a sufficient token balance, calling this function does not withdraw funds from the rabbit exchange to the vault
    /// @dev Only the vault owner can call this function
    /// @param amount The amount of tokens to withdraw.
    /// @param to The address to which to send the tokens.
    function withdraw(uint256 amount, address to) external onlyOwner {
        require(amount > 0, "WRONG_AMOUNT");
        require(to != address(0), "ZERO_ADDRESS");
        emit WithdrawTo(to, amount);
        bool success = _makeTransfer(to, amount);
        require(success, "TRANSFER_FAILED");
    }

    /*//////////////////////////////////////////////////////////////
                                HELPERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Check if a user has the admin role.
    /// @param user The user to check.
    function isAdmin(address user) public view returns (bool) {
        return signers[user][ADMIN_ROLE];
    }

    /**
     * @notice give the user the ADMIN_ROLE - which gives
     * the ability to add and remove roles for other users
     *
     * @dev the caller must themselves have the ADMIN_ROLE
     *
     * @param user the address to give the ADMIN_ROLE to
     */
    ///
    function addAdmin(address user) external {
        addRole(user, ADMIN_ROLE);
    }

    /**
     * @notice take away the ADMIN_ROLE - which removes
     * the ability to add and remove roles for other users
     *
     * @dev the caller must themselves have the ADMIN_ROLE
     *
     * @param user the address from which to remove the ADMIN_ROLE
     */
    function removeAdmin(address user) external {
        removeRole(user, ADMIN_ROLE);
    }

    /**
     * @notice does the user have the TRADER_ROLE - which gives
     * the ability to trade on the rabbit exchange with the vault's funds
     *
     * @param user the address to check
     * @return true if the user has the TRADER_ROLE
     */
    function isTrader(address user) public view returns (bool) {
        return signers[user][TRADER_ROLE];
    }

    /**
     * @notice give the user the TRADER_ROLE - which gives
     * the ability to trade on the rabbit exchange with the vault's funds
     *
     * @dev the caller must have the ADMIN_ROLE
     *
     * @param user the address to give the TRADER_ROLE to
     */
    function addTrader(address user) external {
        addRole(user, TRADER_ROLE);
    }

    /**
     * @notice take away the TRADER_ROLE - which removes
     * the ability to trade on the rabbit exchange with the vault's funds
     *
     * @dev the caller must have the ADMIN_ROLE
     *
     * @param user the address from which to remove the TRADER_ROLE
     */
    function removeTrader(address user) external {
        removeRole(user, TRADER_ROLE);
    }

    /**
     * @notice does the user have the DEPOSITOR_ROLE - which gives
     * the ability to deposit the vault's funds into the rabbit exchange
     *
     * @param user the address to check
     * @return true if the user has the DEPOSITOR_ROLE
     */
    function isDepositor(address user) public view returns (bool) {
        return signers[user][DEPOSITOR_ROLE];
    }

    /**
     * @notice give the user the DEPOSITOR_ROLE - which gives
     * the ability to deposit the vault's funds into the rabbit exchange
     *
     * @dev the caller must have the ADMIN_ROLE
     *
     * @param user the address to give the DEPOSITOR_ROLE to
     */
    function addDepositor(address user) external {
        addRole(user, DEPOSITOR_ROLE);
    }

    /**
     * @notice take away the DEPOSITOR_ROLE - which removes
     * the ability to deposit the vault's funds into the rabbit exchange
     *
     * @dev the caller must have the ADMIN_ROLE
     *
     * @param user the address from which to remove the DEPOSITOR_ROLE
     */
    function removeDepositor(address user) external {
        removeRole(user, DEPOSITOR_ROLE);
    }

    /**
     * @notice does the user have the specified role
     *
     * @dev the roles recognised by the vault are
     * ADMIN_ROLE (0), TRADER_ROLE (1) and DEPOSITOR_ROLE (2), other roles can
     * be given and removed, but they have no special meaning for the vault
     *
     * @param signer the address to check
     * @param role the role to check
     * @return true if the user has the specified role
     */
    function isValidSigner(address signer, uint256 role) public view returns (bool) {
        return signers[signer][role];
    }

    /**
     * @notice give the user the specified role
     *
     * @dev the caller must have the ADMIN_ROLE
     * @dev the roles recognised by the vault are
     * ADMIN_ROLE (0), TRADER_ROLE (1) and DEPOSITOR_ROLE (2), other roles can
     * be given and removed, but they have no special meaning for the vault
     *
     * @param signer the address to which to give the role
     * @param role the role to give
     */
    function addRole(address signer, uint256 role) public {
        require(signers[msg.sender][ADMIN_ROLE], "NOT_AN_ADMIN");
        signers[signer][role] = true;
        emit AddRole(signer, role);
    }

    /**
     * @notice take away the specified role from the user
     *
     * @dev the caller must have the ADMIN_ROLE
     * @dev the roles recognised by the vault are
     * ADMIN_ROLE (0), TRADER_ROLE (1) and DEPOSITOR_ROLE (2), other roles can
     * be given and removed, but they have no special meaning for the vault
     *
     * @param signer the address from which to remove the role
     * @param role the role to remove
     */
    function removeRole(address signer, uint256 role) public {
        require(signers[msg.sender][ADMIN_ROLE], "NOT_AN_ADMIN");
        signers[signer][role] = false;
        emit RemoveRole(signer, role);
    }

    /**
     * @notice sets the address of the IERC20 payment token used by the rabbit exchange
     *
     * @dev WARNING must match the payment token address on the rabbit exchange
     * contract, normally set during deployment
     * @dev only the vault owner can call this function
     *
     * @param _paymentToken the address of the payment token
     */
    function setPaymentToken(address _paymentToken) external onlyOwner {
        paymentToken = IERC20(_paymentToken);
    }

    /**
     * @notice sets the address of the rabbit exchange contract
     *
     * @dev WARNING incorrect setting could lead to loss of funds when
     * calling makeDeposit, normally set during deployment
     * @dev only the vault owner can call this function
     *
     * @param _rabbit the address of the rabbit exchange contract
     */
    function setRabbit(address _rabbit) external onlyOwner {
        rabbit = IRabbitX(_rabbit);
    }

    function _makeTransfer(address to, uint256 amount) private returns (bool success) {
        return _tokenCall(abi.encodeWithSelector(paymentToken.transfer.selector, to, amount));
    }

    function _tokenCall(bytes memory data) private returns (bool) {
        (bool success, bytes memory returndata) = address(paymentToken).call(data);
        if (success && returndata.length > 0) {
            success = abi.decode(returndata, (bool));
        }
        return success;
    }

    /*//////////////////////////////////////////////////////////////
                               UPGRADE
    //////////////////////////////////////////////////////////////*/

    /// @dev Upgrades the implementation of the proxy to new address.
    function _authorizeUpgrade(address) internal override onlyOwner {}
}
