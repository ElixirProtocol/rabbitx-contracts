// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import {IERC20Metadata} from "openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";

import {IRabbitX} from "src/interfaces/IRabbitX.sol";

/// @title Elixir pool router for RabbitX
/// @author The Elixir Team
/// @custom:security-contact security@elixir.finance
/// @notice Pool router contract to deposit funds on behalf of users to RabbitX. Allows external account to market make for this contract.
contract RabbitRouter {
    using SafeERC20 for IERC20Metadata;

    /*//////////////////////////////////////////////////////////////
                                VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice The RabbitX contract.
    IRabbitX public immutable rabbit;

    /// @notice The address of the external account to market make on RabbitX.
    address public immutable externalAccount;

    /// @notice The Manager contract associated with this Router.
    address public immutable manager;

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Reverts when the sender is not the Manager contract.
    error NotManager();

    /*//////////////////////////////////////////////////////////////
                                MODIFIERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Reverts when the sender is not the Manager contract.
    modifier onlyManager() {
        if (msg.sender != manager) revert NotManager();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Set the Manager, RabbitX, and external account.
    /// @param _externalAccount The address of the external account.
    constructor(address _rabbit, address _externalAccount) {
        // Set the Manager as the owner.
        manager = msg.sender;

        // Set RabbitX's endpoint address.
        rabbit = IRabbitX(_rabbit);

        // Set the external account.
        externalAccount = _externalAccount;
    }

    /*//////////////////////////////////////////////////////////////
                                RABBITX
    //////////////////////////////////////////////////////////////*/

    /// @notice Deposits funds to RabbitX on behalf of the user.
    /// @dev Only callable by the Manager contract.
    function deposit(uint256 amount) external onlyManager {
        rabbit.deposit(amount);
    }

    /// @notice Allows RabbitX to check if an address is authorized.
    /// @param signer The address to check
    function isValidSigner(address signer, uint256) external view returns (bool) {
        return signer == externalAccount;
    }

    /*//////////////////////////////////////////////////////////////
                             TOKEN TRANSFER
    //////////////////////////////////////////////////////////////*/

    /// @notice Approves RabbitX to transfer a token.
    /// @dev Only callable by the Manager contract.
    /// @param token The token to approve.
    function makeApproval(address token) external onlyManager {
        // Approve the token transfer.
        IERC20Metadata(token).safeApprove(address(rabbit), type(uint256).max);
    }

    /// @notice Allow claims from RabbitManager contract.
    /// @dev Only callable by the Manager contract.
    /// @param token The token to transfer.
    /// @param amount The amount to transfer.
    function claimToken(address token, uint256 amount) external onlyManager {
        // Transfer the token to the manager.
        IERC20Metadata(token).safeTransfer(manager, amount);
    }
}
