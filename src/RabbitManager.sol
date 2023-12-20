// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import {IERC20Metadata} from "openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {Math} from "openzeppelin/utils/math/Math.sol";
import {ReentrancyGuard} from "openzeppelin/security/ReentrancyGuard.sol";

import {Initializable} from "openzeppelin-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "openzeppelin-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "openzeppelin-upgradeable/access/OwnableUpgradeable.sol";

import {IRabbitManager} from "src/interfaces/IRabbitManager.sol";
import {IRabbitX} from "src/interfaces/IRabbitX.sol";

import {RabbitRouter} from "src/RabbitRouter.sol";

/// @title Elixir pool manager for RabbitX
/// @author The Elixir Team
/// @custom:security-contact security@elixir.finance
/// @notice Pool manager contract to provide liquidity for spot and perp market making on RabbitX.
contract RabbitManager is IRabbitManager, Initializable, UUPSUpgradeable, OwnableUpgradeable, ReentrancyGuard {
    using Math for uint256;
    using SafeERC20 for IERC20Metadata;

    /*//////////////////////////////////////////////////////////////
                                VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice The pools managed given an ID.
    mapping(uint256 id => Pool pool) public pools;

    /// @notice The RabbitX product IDs of token addresses.
    mapping(address token => uint32 id) public tokenToProduct;

    /// @notice The token addresses of RabbitX product IDs.
    mapping(uint32 id => address token) public productToToken;

    /// @notice The queue for Elixir to process.
    mapping(uint128 => Spot) public queue;

    /// @notice The queue count.
    uint128 public queueCount;

    /// @notice The queue up to.
    uint128 public queueUpTo;

    /// @notice The RabbitX slow mode fee.
    uint256 public slowModeFee = 1000000;

    /// @notice RabbitX' contract.
    IRabbitX public rabbit;

    /// @notice Fee payment token for slow mode transactions through RabbitX.
    IERC20Metadata public token;

    /// @notice The pause status of deposits. True if deposits are paused.
    bool public depositPaused;

    /// @notice The pause status of withdrawals. True if withdrawals are paused.
    bool public withdrawPaused;

    /// @notice The pause status of claims. True if claims are paused.
    bool public claimPaused;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a deposit is made.
    /// @param router The router of the pool deposited to.
    /// @param caller The caller of the deposit function, for which tokens are taken from.
    /// @param receiver The receiver of the LP balance.
    /// @param id The ID of the pool deposting to.
    /// @param amount The token amount deposited.
    /// @param shares The amount of shares received.
    event Deposit(
        address indexed router,
        address caller,
        address indexed receiver,
        uint256 indexed id,
        uint256 amount,
        uint256 shares
    );

    /// @notice Emitted when a withdraw is made.
    /// @param router The router of the pool withdrawn from.
    /// @param user The user who withdrew.
    /// @param amount The token amount the user receives.
    event Withdraw(address indexed router, address indexed user, uint256 indexed amount);

    /// @notice Emitted when a perp withdrawal is queued.
    /// @param spot The spot added to the queue.
    /// @param queueCount The queue count.
    /// @param queueUpTo The queue up to.
    event Queued(Spot spot, uint128 queueCount, uint128 queueUpTo);

    /// @notice Emitted when a claim is made.
    /// @param user The user for which the tokens were claimed.
    /// @param token The token claimed.
    /// @param amount The token amount claimed.
    event Claim(address indexed user, address indexed token, uint256 indexed amount);

    /// @notice Emitted when the pause statuses are updated.
    /// @param depositPaused True if deposits are paused, false otherwise.
    /// @param withdrawPaused True if withdrawals are paused, false otherwise.
    /// @param claimPaused True if claims are paused, false otherwise.
    event PauseUpdated(bool indexed depositPaused, bool indexed withdrawPaused, bool indexed claimPaused);

    /// @notice Emitted when a pool is added.
    /// @param id The ID of the pool.
    /// @param poolType The type of the pool.
    /// @param router The router address of the pool.
    /// @param hardcap The hardcap of the pool.
    event PoolAdded(uint256 indexed id, PoolType poolType, address indexed router, uint256 hardcap);

    /// @notice Emitted when tokens are added to a pool.
    /// @param id The ID of the pool.
    /// @param tokens The new tokens of the pool.
    /// @param hardcaps The hardcaps of the added tokens.
    event PoolTokensAdded(uint256 indexed id, address[] tokens, uint256[] hardcaps);

    /// @notice Emitted when a pool's hardcap is updated.
    /// @param id The ID of the pool.
    /// @param hardcap The new hardcap of the pool.
    event PoolHardcapUpdated(uint256 indexed id, uint256 indexed hardcap);

    /// @notice Emitted when the RabbitX product ID of a token is updated.
    /// @param token The token address.
    /// @param productId The new RabbitX product ID of the token.
    event TokenUpdated(address indexed token, uint256 indexed productId);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when the receiver is the zero address.
    error ZeroAddress();

    /// @notice Emitted when a token is duplicated.
    /// @param token The duplicated token.
    error DuplicatedToken(address token);

    /// @notice Emitted when a token is already supported.
    /// @param token The token address.
    /// @param id The ID of the pool.
    error AlreadySupported(address token, uint256 id);

    /// @notice Emitted when deposits are paused.
    error DepositsPaused();

    /// @notice Emitted when withdrawals are paused.
    error WithdrawalsPaused();

    /// @notice Emitted when claims are paused.
    error ClaimsPaused();

    /// @notice Emitted when the length of two arrays don't match.
    /// @param array1 The uint256 array input.
    /// @param array2 The address array input.
    error MismatchInputs(uint256[] array1, address[] array2);

    /// @notice Emitted when the hardcap of a pool would be exceeded.
    /// @param hardcap The hardcap of the pool given the token.
    /// @param activeAmount The active amount of tokens in the pool.
    /// @param amount The amount of tokens being deposited.
    error HardcapReached(uint256 hardcap, uint256 activeAmount, uint256 amount);

    /// @notice Emitted when the slippage is too high.
    /// @param amount The amount of tokens given.
    /// @param amountLow The low limit of token amounts.
    /// @param amountHigh The high limit of token amounts.
    error SlippageTooHigh(uint256 amount, uint256 amountLow, uint256 amountHigh);

    /// @notice Emitted when the pool is not valid or used in the incorrect function.
    /// @param id The ID of the pool.
    error InvalidPool(uint256 id);

    /// @notice Emitted when a token is not supported for a pool.
    /// @param token The address of the unsupported token.
    /// @param id The ID of the pool.
    error UnsupportedToken(address token, uint256 id);

    /// @notice Emitted when the token is not valid because it has more than 18 decimals.
    /// @param token The address of the token.
    error InvalidToken(address token);

    /// @notice Emitted when the new fee is above 100 USDC.
    /// @param newFee The new fee.
    error FeeTooHigh(uint256 newFee);

    /// @notice Emitted when the amount given to withdraw is less than the fee to pay.
    /// @param amount The amount given to withdraw.
    /// @param fee The fee to pay.
    error AmountTooLow(uint256 amount, uint256 fee);

    /// @notice Emitted when the given spot ID to unqueue is not valid.
    error InvalidSpot(uint128 spotId, uint128 queueUpTo);

    /// @notice Emitted when the caller is not the external account of the pool's router.
    error NotExternalAccount(address router, address externalAccount, address caller);

    /// @notice Emitted when the queue spot type is invalid.
    error InvalidSpotType(Spot spot);

    /// @notice Emitted when the caller is not the smart contract itself.
    error NotSelf();

    /// @notice Emitted when the msg.value of the call is too low for the fee.
    /// @param value The msg.value.
    /// @param fee The fee to pay.
    error FeeTooLow(uint256 value, uint256 fee);

    /// @notice Emitted when the fee transfer fails.
    error FeeTransferFailed();

    /*//////////////////////////////////////////////////////////////
                                MODIFIERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Reverts when deposits are paused.
    modifier whenDepositNotPaused() {
        if (depositPaused) revert DepositsPaused();
        _;
    }

    /// @notice Reverts when withdrawals are paused.
    modifier whenWithdrawNotPaused() {
        if (withdrawPaused) revert WithdrawalsPaused();
        _;
    }

    /// @notice Reverts when claims are paused.
    modifier whenClaimNotPaused() {
        if (claimPaused) revert ClaimsPaused();
        _;
    }

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
    function initialize(address _rabbit, uint256 _slowModeFee) public initializer {
        __UUPSUpgradeable_init();
        __Ownable_init();

        // Set RabbitX contract.
        rabbit = IRabbitX(_rabbit);

        // Set the slow mode fee.
        slowModeFee = _slowModeFee;

        // Set the deposit token for the pools.
        token = IERC20Metadata(rabbit.paymentToken());
    }

    /*//////////////////////////////////////////////////////////////
                        DEPOSIT/WITHDRAWAL ENTRY
    //////////////////////////////////////////////////////////////*/

    /// @notice Deposit a token into a perp pool.
    /// @param id The pool ID.
    /// @param amount The token amount to deposit.
    /// @param receiver The receiver of the virtual LP balance.
    function deposit(uint256 id, uint256 amount, address receiver) external payable whenDepositNotPaused nonReentrant {
        // Fetch the pool storage.
        Pool storage pool = pools[id];

        // Check that the pool exists.
        if (pool.poolType != PoolType.Perp) revert InvalidPool(id);

        // Check that the receiver is not the zero address.
        if (receiver == address(0)) revert ZeroAddress();

        // Take fee for unqueue transaction.
        // TODO: Uncomment
        // takeElixirFee(pool.router);

        // Add to queue.
        queue[queueCount++] = Spot(
            msg.sender,
            pool.router,
            SpotType.Deposit,
            abi.encode(DepositQueue({id: id, amount: amount, receiver: receiver}))
        );

        emit Queued(queue[queueCount - 1], queueCount, queueUpTo);
    }

    /// @notice Requests to withdraw a token from a perp pool.
    /// @dev Requests are placed into a FIFO queue, which is processed by the Elixir market-making network and passed on to RabbitX via the `unqueue` function.
    /// @dev After processed by RabbitX, the user (or anyone on behalf of it) can call the `claim` function.
    /// @param id The ID of the pool to withdraw from.
    /// @param amount The amount of token shares to withdraw.
    function withdraw(uint256 id, uint256 amount) external payable whenWithdrawNotPaused nonReentrant {
        // Fetch the pool storage.
        Pool storage pool = pools[id];

        // Check that the pool exists.
        if (pool.poolType != PoolType.Perp) revert InvalidPool(id);

        // Take fee for unqueue transaction.
        // TODO: Uncomment
        // takeElixirFee(pool.router);

        // Add to queue.
        queue[queueCount++] =
            Spot(msg.sender, pool.router, SpotType.Withdraw, abi.encode(WithdrawQueue({id: id, amount: amount})));

        emit Queued(queue[queueCount - 1], queueCount, queueUpTo);
    }

    /// @notice Claim received tokens from the pending balance and fees.
    /// @param user The address to claim for.
    /// @param token The token to claim.
    /// @param id The ID of the pool to claim from.
    function claim(address user, address token, uint256 id) external whenClaimNotPaused nonReentrant {
        // Fetch the pool data.
        Pool storage pool = pools[id];

        // Check that the pool exists.
        if (pool.router == address(0)) revert InvalidPool(id);

        // Check that the user is not the zero address.
        if (user == address(0)) revert ZeroAddress();

        // Fetch the user's pending balance. No danger if amount is 0.
        uint256 amount = pool.userPendingAmount[user];

        // Fetch Elixir's pending fee balance.
        uint256 fee = pool.fees[user];

        // Resets the pending balance of the user.
        pool.userPendingAmount[user] = 0;

        // Resets the Elixir pending fee balance.
        pool.fees[user] = 0;

        // Fetch the tokens from the router.
        RabbitRouter(pool.router).claimToken(token, amount + fee);

        // Transfers the tokens after to prevent reentrancy.
        IERC20Metadata(token).safeTransfer(owner(), fee);
        IERC20Metadata(token).safeTransfer(user, amount);

        emit Claim(user, token, amount);
    }

    /*//////////////////////////////////////////////////////////////
                                HELPERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns a user's active amount for a token within a pool.
    /// @param id The ID of the pool to fetch the active amounts of.
    /// @param user The user to fetch the active amounts of.
    function getUserActiveAmount(uint256 id, address user) external view returns (uint256) {
        return pools[id].userActiveAmount[user];
    }

    /// @notice Returns a user's pending amount for a token within a pool.
    /// @param id The ID of the pool to fetch the pending amount of.
    /// @param user The user to fetch the pending amount of.
    function getUserPendingAmount(uint256 id, address user) external view returns (uint256) {
        return pools[id].userPendingAmount[user];
    }

    /// @notice Returns a user's reimbursement fee for a token within a pool.
    /// @param id The ID of the pool to fetch the fee for.
    /// @param user The user to fetch the fee for.
    function getUserFee(uint256 id, address user) external view returns (uint256) {
        return pools[id].fees[user];
    }

    // TODO: Update
    // /// @notice Enforce the Elixir fee in native ETH.
    // /// @param router The pool router.
    // function takeElixirFee(address router) private {
    //     // Get the Elixir processing fee for unqueue transaction using WETH as token.
    //     // Safely assumes that WETH ID on RabbitX is 3.
    //     uint256 fee = getTransactionFee(productToToken[3]);

    //     // Check that the msg.value is equal or more than the fee.
    //     if (msg.value < fee) revert FeeTooLow(msg.value, fee);

    //     // Transfer fee to the external account EOA.
    //     (bool sent,) = payable(getExternalAccount(router)).call{value: msg.value}("");
    //     if (!sent) revert FeeTransferFailed();
    // }

    /// @notice Returns the next spot in the queue to process.
    function nextSpot() external view returns (Spot memory) {
        return queue[queueUpTo];
    }

    /// @notice Processes a spot transaction given a response.
    /// @param spot The spot to process.
    /// @param response The response for the spot in queue.
    function processSpot(Spot calldata spot, bytes memory response) public {
        if (msg.sender != address(this)) revert NotSelf();

        if (spot.spotType == SpotType.Deposit) {
            DepositQueue memory spotTxn = abi.decode(spot.transaction, (DepositQueue));

            DepositResponse memory responseTxn = abi.decode(response, (DepositResponse));

            // Get the pool storage.
            Pool storage pool = pools[spotTxn.id];

            // Check if the amount exceeds the pool's hardcap.
            if (pool.activeAmount + responseTxn.shares > pool.hardcap) {
                revert HardcapReached(pool.hardcap, pool.activeAmount, responseTxn.shares);
            }

            // Fetch the router of the pool.
            RabbitRouter router = RabbitRouter(pool.router);

            // Transfer tokens from the caller to the router.
            token.safeTransferFrom(spot.sender, address(router), spotTxn.amount);

            // Deposit funds to RabbitX through router.
            router.deposit(spotTxn.amount);

            // Add amount to the active market making balance of the user.
            pool.userActiveAmount[spotTxn.receiver] += responseTxn.shares;

            // Add amount to the active pool market making balance.
            pool.activeAmount += responseTxn.shares;

            emit Deposit(address(router), spot.sender, spotTxn.receiver, spotTxn.id, spotTxn.amount, responseTxn.shares);
        } else if (spot.spotType == SpotType.Withdraw) {
            WithdrawQueue memory spotTxn = abi.decode(spot.transaction, (WithdrawQueue));

            WithdrawResponse memory responseTxn = abi.decode(response, (WithdrawResponse));

            // Get the pool storage.
            Pool storage pool = pools[spotTxn.id];

            // Substract amount from the active market making balance of the caller.
            pool.userActiveAmount[spot.sender] -= spotTxn.amount;

            // Substract amount from the active pool market making balance.
            pool.activeAmount -= spotTxn.amount;

            // Update the user pending balance.
            pool.userPendingAmount[spot.sender] += (responseTxn.amountToReceive);

            emit Withdraw(address(pool.router), spot.sender, responseTxn.amountToReceive);
        } else {
            revert InvalidSpotType(spot);
        }
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
        address externalAccount = RabbitRouter(spot.router).externalAccount();

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

    /// @notice Manages the paused status of deposits, withdrawals, and claims
    /// @param _depositPaused True to pause deposits, false otherwise.
    /// @param _withdrawPaused True to pause withdrawals, false otherwise.
    /// @param _claimPaused True to pause claims, false otherwise.
    function pause(bool _depositPaused, bool _withdrawPaused, bool _claimPaused) external onlyOwner {
        depositPaused = _depositPaused;
        withdrawPaused = _withdrawPaused;
        claimPaused = _claimPaused;

        emit PauseUpdated(depositPaused, withdrawPaused, claimPaused);
    }

    /// @notice Adds a new pool.
    /// @param id The ID of the new pool.
    /// @param hardcap The hardcap for the pool.
    /// @param poolType The type of the pool.
    /// @param externalAccount The external account to link to RabbitX.
    function addPool(uint256 id, uint256 hardcap, PoolType poolType, address externalAccount) external onlyOwner {
        // Check that the pool doesn't exist.
        if (pools[id].router != address(0)) revert InvalidPool(id);

        // Deploy a new router contract.
        RabbitRouter router = new RabbitRouter(address(rabbit), externalAccount);

        // Approve the fee token to the router.
        router.makeApproval(address(token));

        // Set the router address of the pool.
        pools[id].router = address(router);

        // Set the pool type.
        pools[id].poolType = poolType;

        // Set the hardcap of the pool.
        pools[id].hardcap = hardcap;

        emit PoolAdded(id, poolType, address(router), hardcap);
    }

    /// @notice Updates the hardcap of a pool.
    /// @param id The ID of the pool.
    /// @param hardcap The new pool hardcap.
    function updatePoolHardcap(uint256 id, uint256 hardcap) external onlyOwner {
        pools[id].hardcap = hardcap;

        emit PoolHardcapUpdated(id, hardcap);
    }

    /// @notice Rescues any stuck tokens in the contract.
    /// @param token The token to rescue.
    /// @param amount The amount of token to rescue.
    function rescue(address token, uint256 amount) external onlyOwner {
        IERC20Metadata(token).safeTransfer(owner(), amount);
    }

    /*//////////////////////////////////////////////////////////////
                           INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @dev Upgrades the implementation of the proxy to new address.
    function _authorizeUpgrade(address) internal override onlyOwner {}
}
