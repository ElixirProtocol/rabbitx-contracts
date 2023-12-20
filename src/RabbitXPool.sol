// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";

import {ERC20Upgradeable} from "openzeppelin-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {Initializable} from "openzeppelin-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "openzeppelin-upgradeable/access/OwnableUpgradeable.sol";
import {AccessControlUpgradeable} from "openzeppelin-upgradeable/access/AccessControlUpgradeable.sol";

import {IRabbitX} from "src/interfaces/IRabbitx.sol";

/// @title Pool implementation
/// @author The Elixir Team
/// @custom:security-contact security@elixir.finance
/// @notice Pool implementation logic for RabbitX minimal proxy pools.
contract RabbitXPool is ERC20Upgradeable, OwnableUpgradeable, AccessControlUpgradeable {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                                VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice RabbitX exchange smart contract.
    IRabbitX public rabbit;

    /// @notice Token to deposit in this this pool.
    IERC20 public token;

    /// @notice Trader role for market making via this pool.
    bytes32 public constant TRADER_ROLE = keccak256("TRADER_ROLE");

    /// @notice Depositor role for deposits.
    bytes32 public constant DEPOSITOR_ROLE = keccak256("DEPOSITOR_ROLE");

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event Deposit(address indexed depositor, uint256 amount);
    event Withdraw(address indexed to, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error NotDepositor();
    error InvalidAmount(uint256 amount);
    error InvalidAddress(address addr);

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
    function initialize(address _owner, address _rabbit, address _token) public initializer {
        __Ownable_init(_owner);
        __AccessControl_init();

        _setRoleAdmin(DEPOSITOR_ROLE, DEFAULT_ADMIN_ROLE);
        _setRoleAdmin(TRADER_ROLE, DEFAULT_ADMIN_ROLE);

        _grantRole(DEFAULT_ADMIN_ROLE, _owner);
        _grantRole(DEPOSITOR_ROLE, _owner);

        rabbit = IRabbitX(_rabbit);
        token = IERC20(_token);

        // Update token name and symbol.
        __ERC20_init("RabbitX Pool", "RXP");
    }

    /*//////////////////////////////////////////////////////////////
                        DEPOSIT/WITHDRAWAL ENTRY
    //////////////////////////////////////////////////////////////*/

    /// @notice Deposits funds into the pool, which are redirected to RabbitX.
    /// @param amount The amount of tokens to deposit.
    function deposit(uint256 amount) external {
        if (amount == 0) revert InvalidAmount(amount);
        if (!hasRole(DEPOSITOR_ROLE, msg.sender)) revert NotDepositor();

        // Transfer tokens from the caller to this contract.
        token.safeTransferFrom(msg.sender, address(this), amount);

        // Approve the RabbitX exchange to spend the tokens.
        token.approve(address(rabbit), amount);

        // Deposit the tokens into the RabbitX exchange.
        rabbit.deposit(amount);

        // Mint shares to the caller.
        // TODO: via HB with queue?
        _mint(msg.sender, amount);

        emit Deposit(msg.sender, amount);
    }

    /// @notice Withdraw funds form the pool, which are deducted from RabbitX.
    /// @dev The vault must already have a sufficient token balance, calling this function does not withdraw funds from the rabbit exchange to the vault
    /// @dev Only the vault owner can call this function
    /// @param amount The amount of shares to burn.
    /// @param to The address to which to send the tokens.
    function withdraw(uint256 amount, address to) external onlyOwner {
        if (amount == 0) revert InvalidAmount(amount);
        if (to == address(0)) revert InvalidAddress(to);

        // Burn the shares from the caller.
        _burn(msg.sender, amount);

        // Transfer the tokens to the receiver.
        token.safeTransfer(to, amount);

        emit Withdraw(to, amount);
    }

    /*//////////////////////////////////////////////////////////////
                                HELPERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Updates the RabbitX smart contract address.
    /// @param _rabbit The address of the RabbitX smart contract.
    function setRabbit(address _rabbit) external onlyOwner {
        rabbit = IRabbitX(_rabbit);
    }
}
