# Elixir <> RabbitX Documentation

Overview of Elixir's smart contract architecture integrating to RabbitX.

## Table of Contents

- [Background](#background)
- [Overview](#overview)
- [Sequence of Events](#sequence-of-events)
- [Lifecycle](#example-lifecycle-journey)
- [Incident Response & Monitoring](#incident-response--monitoring)
- [Aspects](#aspects)

## Background

Elixir is building the industry's decentralized, algorithmic market-making protocol. The protocol algorithmically deploys supplied liquidity on the order books, utilizing the equivalent of x*y=k curves to build liquidity and tighten the bid/ask spread. The protocol provides crucial decentralized infrastructure, allowing exchanges and protocols to easily bootstrap liquidity to their books. It also enables crypto projects to incentivize liquidity to their centralized exchange pairs via LP tokens.

This repository contains the smart contracts to power the first native integration between Elixir and RabbitX, a permissionless perpetuals and derivatives exchange. This integration aims to unlock retail liquidity for algorithmic market-making on RabbitX.

More information:
- [Elixir Protocol Documentation](https://docs.elixir.finance/)
- [RabbitX Dcoumentation](https://docs.rabbitx.io/)

## Overview

This integration comprises two Elixir smart contracts a singleton (RabbitManager) and a router (RabbitRouter). RabbitManager allows users to deposit and withdraw liquidity for perpetual markets on RabbitX. By depositing liquidity, users earn rewards from the market-making done by the Elixir validator network off-chain. On the RabbitManager smart contract, each RabbitX market is associated with a pool structure, which contains router (RabbitRouter) and balance data. In order to accurately calculate balances, the RabbitManager contract implements a FIFO queue to process deposits and withdrawals using the latest data off-chain. Aditionally, a RabbitRouter is asigned to each pool, allowing the off-chain Elixir network market make on behalf of it. Regarding RabbitX, the Elixir smart contract interacts only with Rabbit smart contract.

- [RabbitManager](src/RabbitManager.sol): Elixir smart contract to deposit, withdraw, claim and manage product pools.
- [RabbitRouter](src/RabbitRouter.sol): Elixir smart contract to market make on behalf of a RabbitManager pool.
- [Rabbit](https://github.com/rabbitx-io/rabbitx-contracts/blob/main/Rabbit.sol): RabbitX smart contract that serves as the entry point for deposits and withdrawals.

## Sequence of Events

### Deposit Liquidity
Liquidity is deposited into the RabbitManager smart contract by calling the `deposit` function, limited to USDT. Deposits are queued and processed by Elixir, returning an accurate amount of LP shares the user should receive. In order to sustain this, Elixir takes a fee in native ETH for deposits and withdrawals.

The `deposit` flow is the following:

1. Check that deposits are not paused.
2. Check that the reentrancy guard is not active.
3. Check that the pool given exists.
4. Check that the receiver is not a zero address (for the good of the user).
5. Get the Elixir processing fee in native ETH
6. Queue the deposit.

Afterwards, the Elixir sequencer will call the `unqueue` function which processes the next transaction in the queue. For deposits, the process flow is the following:

1. Checks that the token amount to deposit will not exceed the liquidity hardcap of the pool.
2. Transfer the tokens from the depositor to the smart contract.
3. Deposit into RabbitX, redirecting the liquidity to the Elixir market making network via the RabbitRouter smart contract assigned to this pool.
4. Update the pool data and balances with the shares amount.
5. Emit the `Deposit` event.
6. Update the queue state to mark this deposit as processed.

### Withdraw Liquidity
To start a withdrawal, the user needs to signal this by calling `withdraw` function. The withdrawal will be queued and when processed by Elixir, the user's shares will be burned and a withdrawal request will be sent to RabbitX (which takes no more than 6 hours). When the request is processed by RabbitX, the liquidity is transfered to the pool's RabbitRouter smart contract. Here, the user needs to "manually" claim the liquidity via the `claim` function on the Elixir RabbitManager smart contract, as no RabbitX callback is available. Anyone can call this function on behalf of any address, allowing us to monitor pending claims and process them for users. When calling the `claim` function, the RabbitManager smart contract will transfer the liquidity from the pool's RabbitRouter into the RabbitManager smart contract, which is then transferred to the user.

The `withdraw` flow is the following:

1. Check that withdrawals are not paused.
2. Check that the reentrancy guard is not active.
3. Check that the pool given exists.
4. Get the Elixir processing fee in native ETH
5. Queue the withdrawal.

Afterwards, the Elixir sequencer will call the `unqueue` function which processes the next transaction in the queue. For withdrawals, the process flow is the following:

1. Subtract the amount of tokens given from the user's balance on the pool data. Reverts if the user does not have enough balance.
2. Add fee amount to the balance of Elixir, which is automatically reimbursed with user claims, but it can also reimburse itself by calling the `claim` function on behalf of a user.
3. Substract fee amount from the calculated token amount to withdraw and stored as the pending balance for claims afterward.
4. Build and send the withdrawal request to RabbitX.
5. Emit the `Withdraw` event.
6. Update the queue state to mark this withdraw as processed.

### Claim Liquidity
After the RabbitX fulfills a withdrawal request, the funds will be available to claim on the RabbitManager smart contract by calling the `claim` function. This function can be called by anyone on behalf of a user, allowing us to monitor the pending claims and process them for users. The flow of the `claim` function is the following:

1. Check that claims are not paused.
2. Check that the reentrancy guard is not active.
3. Check that the pool exists.
4. Check that the user to claim for is not the zero address.
5. Fetch and store the pending balance of the user.
6. Fetch and store the Elixir fee amount.
7. Reset the pending balance and fee to 0.
8. Transfer the token amount to the user.
9. Transfer the fee amount to the owner (Elixir).
10. Emit the `Claim` event.

> Note: As pending balances are not stored sequentially, users are able to claim funds in any order as they arrive at the RabbitRouter smart contract. This is expected behavior and does not affect the user's funds as the RabbitX will continue to fulfill withdrawal requests.

### Reward Distribution
By market-making (creating and filling orders on the RabbitX order book), the Elixir validator network earns rewards. These rewards are distributed to the users who deposited liquidity on the RabbitManager smart contract, depending on the amount and time of their liquidity.

Learn more about the RBX reward mechanism [here](https://docs.rabbitx.io/token/rbx).

## Example Lifecycle Journey

- A user approves the RabbitManager smart contract to spend their token.
- User calls `deposit` and passes the following parameters:
   * `id`: The ID of the pool to deposit to.
   * `amount`: The amount of tokens to deposit.
   * `receiver`: The receiver of the virtual LP balance.
- Elixir processes the deposit from the queue.
- The `_deposit` redirects liquidity to RabbitX and updates the LP balances, giving the shares to the receiver.
- The Elixir network of decentralized validators receives the liquidity and market makes with it, generating rewards.
- After some time, the user (i.e., receiver) calls the `withdraw` function to initiate a withdrawal, passing the following parameters:
   * `id`: The ID of the pool to withdraw from.
   * `amount`: The amount of shares to withdraw.
- Elixir processes the withdrawal from the queue.
- The `_withdraw` function updates the LP balances and sends the withdrawal requests to RabbitX.
- After the RabbitX fulfills the withdrawal request, the funds are available to be claimed via the `claim` function.

## Incident Response & Monitoring

The Elixir team is planning to protect the smart contracts with Chainalysis Incident Response (CIR) in the event of a hack or exploit. The benefits of CIR include:

- CIR helps deter hackers by letting them know a leading global crypto investigative team is on our side.
- With CIR, we can tap into Chainalysis’ expertise for complex blockchain analysis and investigations. The CIR team is ready to respond to cybersecurity breaches, ransomware attacks, recovery of stolen cryptocurrency, and perform other analyses involving blockchain data. The team consists of respected professional investigators, cybersecurity experts, and data engineers.
- Having a proactive solution in place decreases the time to respond and increases the likelihood of asset freezing and recovery or law enforcement should the worst happen.
- The ability to trace funds through various types of complex platforms is a crucial part of the CIR incident response and the ability to recover funds successfully. This applies to identified mixer platforms but also unidentified mixers and new bridging protocols between blockchains.
- Chainalysis has a huge customer base and, with it, a sizable network with personal connections to almost all significant exchanges and services in the crypto space. Also, their strong relationship with Law Enforcement Agencies around the world makes them very efficient in engaging the relevant entities when needed.
- In over 80% of all cases where an incident has occurred, Chainalysis investigators have been able to give our customers valuable information that leads to recovery of more than what their CIR fee was.

## General Aspects

### Authentication / Access Control

Appropiate access controls are in place for all priviliged operations. The only privliged role in the smart contract is the owner, which is the Elixir multisig. The capabilities of the owner are the following:

- `pause`: Update the pause status of deposits, withdraws, and claims in case of malicious activity or incidents. Allows to pause each operation modularly; for example, pause deposits but allow withdrawals and claims.
- `addPool`: Adds a new pool, deploying a unique router for it.
- `updatePoolHardcap`: Updates the hardcap of a pool. Used to limit and manage market making activity on RabbitX for scaling purposes. An alternative to pausing deposits too.
- `rescue`: Allows the owner to rescue any stuck tokens in the RabbitManager smart contract. It's not possible to mistakenly rescue non-stuck tokens.

Aditionally, the Elixir network is the only party authorized to market make with the pool balances.
