// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import {ECDSA} from "openzeppelin/utils/cryptography/ECDSA.sol";
import {EIP712} from "openzeppelin/utils/cryptography/EIP712.sol";
import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "openzeppelin/access/Ownable.sol";

/// @title Elixir distributor
/// @author The Elixir Team
/// @custom:security-contact security@elixir.finance
/// @notice Allows users to claim a token amount, approved by Elixir.
contract Distributor is Ownable, EIP712 {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                                VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice Track token claimed amounts.
    mapping(address user => mapping(address token => uint256 totalAmount)) public claimed;

    /// @notice The Elixir signer address.
    address public immutable signer;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a user claims a token amount.
    /// @param caller The caller of the transaction.
    /// @param receiver The receiver of the rewards.
    /// @param token The token claimed.
    /// @param amount The amount of rewards claimed.
    event Claimed(address caller, address indexed receiver, address indexed token, uint256 indexed amount);

    /// @notice Emitted when the owner withdraws a token.
    /// @param token The token withdrawn.
    /// @param amount The amount of token withdrawn.
    event Withdraw(address indexed token, uint256 indexed amount);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Error emitted when the ECDSA signer is not correct.
    error InvalidSignature();

    /// @notice Error emitted when the user has already claimed.
    error AlreadyClaimed();

    /// @notice Error emitted when the amount is zero.
    error InvalidAmount();

    /// @notice Error emitted when the token is zero.
    error InvalidToken();

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Set the storage variables.
    /// @param _name The name of the contract.
    /// @param _version The version of the contract.
    /// @param _signer The Elixir signer address.
    constructor(string memory _name, string memory _version, address _signer) EIP712(_name, _version) {
        // Set the signer address.
        signer = _signer;
    }

    /*//////////////////////////////////////////////////////////////
                           EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Claims tokens approved by Elixir.
    /// @param receiver The receiver of the claim.
    /// @param token The token to claim.
    /// @param totalAmount The total amount of tokens.
    /// @param signature The signature from the Elixir signer.
    function claim(address receiver, address token, uint256 totalAmount, bytes memory signature) external {
        // Check that the token is not zero.
        if (token == address(0)) revert InvalidToken();

        // Check that the totalAmount is not zero.
        if (totalAmount == 0) revert InvalidAmount();

        // Generate digest.
        bytes32 digest = _hashTypedDataV4(
            keccak256(
                abi.encode(
                    keccak256("Claim(address user,address token,uint256 totalAmount)"), receiver, token, totalAmount
                )
            )
        );

        // Check if the signature is valid. No need to mark digest as used as the amount claimed is stored.
        // Aditionally, the ECDSA library will prevent signature malleability due to the symmetrical nature of the elliptic curve.
        if (ECDSA.recover(digest, signature) != signer) revert InvalidSignature();

        // Get the token amount claimed.
        uint256 claimedAmount = claimed[receiver][token];

        // Get the remaining amount to claim.
        uint256 amount = totalAmount - claimedAmount;

        // Update the amount claimed.
        claimed[receiver][token] = totalAmount;

        // Transfer the amount to user.
        IERC20(token).safeTransfer(receiver, amount);

        emit Claimed(msg.sender, receiver, token, amount);
    }

    /// @notice Withdraw a given amount of tokens.
    function emergencyWithdraw(address token, uint256 amount) external onlyOwner {
        IERC20(token).safeTransfer(owner(), amount);

        emit Withdraw(token, amount);
    }
}
