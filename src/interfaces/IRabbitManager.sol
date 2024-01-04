// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

interface IRabbitManager {
    /// @notice The types of spots supported by this contract.
    enum SpotType {
        Empty,
        Deposit,
        Withdraw
    }

    /// @notice The structure for perp deposits to be processed by Elixir.
    struct DepositQueue {
        // The ID of the pool.
        uint256 id;
        // The amount of token to deposit.
        uint256 amount;
        // The receiver address.
        address receiver;
    }

    /// @notice The structure of perp withdrawals to be processed by Elixir.
    struct WithdrawQueue {
        // The ID of the pool.
        uint256 id;
        // The amount of token shares to withdraw.
        uint256 amount;
    }

    /// @notice The response structure for DepositPerp.
    struct DepositResponse {
        // The amount of shares to receive.
        uint256 shares;
    }

    /// @notice The response structure for WithdrawPerp.
    struct WithdrawResponse {
        // The amount of of tokens the user should receive.
        uint256 amountToReceive;
        // The withdrawal ID received from RabbitX.
        uint256 withdrawalId;
        // The signature parameters received from RabbitX to claim withdrawal.
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    /// @notice The types of pools supported by this contract.
    enum PoolType {
        Inactive,
        Perp
    }

    /// @notice The data structure of pools.
    struct Pool {
        // The router address of the pool.
        address router;
        // The pool type.
        PoolType poolType;
        // The active market making balance of users for a token within a pool.
        mapping(address user => uint256 balance) userActiveAmount;
        // The pending amounts of users for a token within a pool.
        mapping(address user => uint256 amount) userPendingAmount;
        // The pending fees of a token within a pool.
        mapping(address user => uint256 amount) fees;
        // The total active amounts of a token within a pool.
        uint256 activeAmount;
        // The hardcap of the token within a pool.
        uint256 hardcap;
    }

    /// @notice The data structure of queue spots.
    struct Spot {
        // The sender of the request.
        address sender;
        // The router address of the pool.
        address router;
        // The type of request.
        SpotType spotType;
        // The transaction to process.
        bytes transaction;
    }
}
