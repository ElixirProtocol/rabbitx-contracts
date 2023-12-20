// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "openzeppelin/utils/ReentrancyGuard.sol";

import {Initializable} from "openzeppelin-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "openzeppelin-upgradeable/access/OwnableUpgradeable.sol";
import {AccessControlUpgradeable} from "openzeppelin-upgradeable/access/AccessControlUpgradeable.sol";

import {IRabbitX} from "src/interfaces/IRabbitx.sol";

/// @title Pool implementation
/// @author The Elixir Team
/// @custom:security-contact security@elixir.finance
/// @notice Pool implementation logic for RabbitX minimal proxy pools.
contract RabbitXPool is Initializable, OwnableUpgradeable, ReentrancyGuard {
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
    }

    /*//////////////////////////////////////////////////////////////
                        DEPOSIT/WITHDRAWAL ENTRY
    //////////////////////////////////////////////////////////////*/

    /// @notice Deposits funds into the pool, which are redirected to RabbitX.
    /// @param amount The token amount to deposit.
    /// @param receiver The receiver of the virtual LP balance.
    function deposit(uint256 amount, address receiver) external {
        // Check that the amount is valid.
        if (amount == 0) revert InvalidAmount(amount);

        // Check that the receiver is not the zero address.
        if (receiver == address(0)) revert InvalidAddress(receiver);

        // Take fee for unqueue transaction.
        takeElixirFee(pool.router);

        // Add to queue.
        queue[queueCount++] = Spot(
            msg.sender,
            pool.router,
            SpotType.DepositPerp,
            abi.encode(DepositPerp({id: id, token: token, amount: amount, receiver: receiver}))
        );

        emit Queued(queue[queueCount - 1], queueCount, queueUpTo);
    }

    /// @notice Withdraw funds form the pool, which are deducted from RabbitX.
    /// @dev The vault must already have a sufficient token balance, calling this function does not withdraw funds from the rabbit exchange to the vault
    /// @dev Only the vault owner can call this function
    /// @param amount The amount of token shares to withdraw.
    function withdraw(uint256 amount) external onlyOwner {
        if (amount == 0) revert InvalidAmount(amount);

        // Take fee for unqueue transaction.
        takeElixirFee(pool.router);

        // Add to queue.
        queue[queueCount++] = Spot(
            msg.sender,
            pool.router,
            SpotType.WithdrawPerp,
            abi.encode(WithdrawPerp({id: id, tokenId: tokenToProduct[token], amount: amount}))
        );

        emit Queued(queue[queueCount - 1], queueCount, queueUpTo);
    }

    /// @notice Processes a spot transaction given a response.
    /// @param spot The spot to process.
    /// @param response The response for the spot in queue.
    function processSpot(Spot calldata spot, bytes memory response) public {
        if (msg.sender != address(this)) revert NotSelf();

        if (spot.spotType == SpotType.Deposit) {
            Deposit memory spotTxn = abi.decode(spot.transaction, (Deposit));

            DepositResponse memory responseTxn = abi.decode(response, (DepositResponse));

            // Check if the amount exceeds the token's pool hardcap.
            if (tokenData.activeAmount + shares > tokenData.hardcap) {
                revert HardcapReached(token, tokenData.hardcap, tokenData.activeAmount, shares);
            }

            // Fetch the router of the pool.
            VertexRouter router = VertexRouter(pool.router);

            // Transfer tokens from the caller to this contract.
            IERC20Metadata(token).safeTransferFrom(caller, address(router), amount);

            // Deposit funds to Vertex through router.
            router.submitSlowModeDeposit(tokenToProduct[token], uint128(amount), "9O7rUEUljP");

            // Add amount to the active market making balance of the user.
            tokenData.userActiveAmount[receiver] += shares;

            // Add amount to the active pool market making balance.
            tokenData.activeAmount += shares;

            emit Deposit(address(router), caller, receiver, id, token, amount, shares);
        } else if (spot.spotType == SpotType.Withdraw) {
            Withdraw memory spotTxn = abi.decode(spot.transaction, (Withdraw));

            WithdrawResponse memory responseTxn = abi.decode(response, (WithdrawResponse));

            // Get the token address.
            address token = productToToken[spotTxn.tokenId];

            // Get the token data.
            Token storage tokenData = pools[spotTxn.id].tokens[token];

            // Substract amount from the active market making balance of the caller.
            tokenData.userActiveAmount[sender] -= amount;

            // Substract amount from the active pool market making balance.
            tokenData.activeAmount -= amount;

            // Add fee to the Elixir balance.
            tokenData.fees[sender] += fee;

            // Update the user pending balance.
            tokenData.userPendingAmount[sender] += (amountToReceive - fee);

            // Create Vertex withdraw payload request.
            IEndpoint.WithdrawCollateral memory withdrawPayload =
                IEndpoint.WithdrawCollateral(router.contractSubaccount(), tokenId, uint128(amountToReceive), 0);

            // Send withdraw requests to Vertex.
            _sendTransaction(
                router,
                abi.encodePacked(uint8(IEndpoint.TransactionType.WithdrawCollateral), abi.encode(withdrawPayload))
            );

            emit Withdraw(address(router), sender, tokenId, amountToReceive);
        } else {
            revert InvalidSpotType(spot);
        }
    }

    /*//////////////////////////////////////////////////////////////
                                HELPERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Updates the RabbitX smart contract address.
    /// @param _rabbit The address of the RabbitX smart contract.
    function setRabbit(address _rabbit) external onlyOwner {
        rabbit = IRabbitX(_rabbit);
    }

    /*//////////////////////////////////////////////////////////////
                          PERMISSIONED FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Processes the next spot in the withdraw perp queue.
    /// @param spotId The ID of the spot queue to process.
    /// @param response The response to the spot transaction.
    function unqueue(uint128 spotId, bytes memory response) external {
        // Get the spot data from the queue.
        Spot memory spot = queue[queueUpTo];

        // Get the external account of the router.
        address externalAccount = getExternalAccount(spot.router);

        // Check that the sender is the external account of the router.
        if (msg.sender != externalAccount) revert NotExternalAccount(spot.router, externalAccount, msg.sender);

        if (response.length != 0) {
            // Check that next spot in queue matches the given spot ID.
            if (spotId != queueUpTo + 1) revert InvalidSpot(spotId, queueUpTo);

            // Process spot. Skips if fail or revert.
            try this.processSpot(spot, response) {} catch {}
        } else {
            // Intetionally skip.
        }

        // Increase the queue up to.
        queueUpTo++;
    }
}
