// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import "forge-std/Test.sol";

import {Utils} from "./utils/Utils.sol";

import {IERC20Metadata} from "openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {ERC1967Proxy} from "openzeppelin/proxy/ERC1967/ERC1967Proxy.sol";
import {Math} from "openzeppelin/utils/math/Math.sol";

import {IRabbitX} from "src/interfaces/IRabbitX.sol";

import {RabbitManager, IRabbitManager} from "src/RabbitManager.sol";
import {RabbitRouter} from "src/RabbitRouter.sol";

contract TestRabbitManager is Test {
    using Math for uint256;
    using SafeERC20 for IERC20Metadata;

    /*//////////////////////////////////////////////////////////////
                                CONTRACTS
    //////////////////////////////////////////////////////////////*/

    // RabbitX addresses
    IRabbitX public rabbit = IRabbitX(0x3b8F6D6970a24A58b52374C539297ae02A3c4Ae4);

    // Elixir contracts
    RabbitManager public rabbitManagerImplementation;
    ERC1967Proxy public proxy;
    RabbitManager public manager;

    // Tokens
    IERC20Metadata public USDT = IERC20Metadata(0xdAC17F958D2ee523a2206206994597C13D831ec7);

    /*//////////////////////////////////////////////////////////////
                                  USERS
    //////////////////////////////////////////////////////////////*/

    // Elixir users
    address public owner;

    // Off-chain validator account that makes request on behalf of the vaults.
    address public externalAccount;

    /*//////////////////////////////////////////////////////////////
                                  MISC
    //////////////////////////////////////////////////////////////*/

    // Utils contract.
    Utils public utils;

    // RPC for Mainnet fork.
    string public networkRpcUrl = vm.envString("MAINNET_RPC_URL");

    // Elixir fee
    uint256 public fee;

    /*//////////////////////////////////////////////////////////////
                                 HELPERS
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        utils = new Utils();
        address payable[] memory users = utils.createUsers(2);

        owner = users[0];
        vm.label(owner, "Owner");

        externalAccount = users[1];
        vm.label(externalAccount, "External Account");

        vm.createSelectFork(networkRpcUrl, 18829846);

        vm.startPrank(owner);

        // Deploy Manager implementation
        rabbitManagerImplementation = new RabbitManager();

        // Deploy and initialize the proxy contract.
        proxy = new ERC1967Proxy(
            address(rabbitManagerImplementation),
            abi.encodeWithSignature("initialize(address,uint256)", address(rabbit), 1000000)
        );

        // Wrap in ABI to support easier calls
        manager = RabbitManager(address(proxy));

        // Add pool.
        manager.addPool(1, type(uint256).max, externalAccount);

        vm.stopPrank();
    }

    /// @notice Processes any transactions in the Elixir queue.
    function processQueue() public {
        vm.startPrank(externalAccount);

        // Loop through the queue and process each transaction using the idTo provided.
        for (uint128 i = manager.queueUpTo() + 1; i < manager.queueCount() + 1; i++) {
            RabbitManager.Spot memory spot = manager.nextSpot();

            if (spot.spotType == IRabbitManager.SpotType.Deposit) {
                IRabbitManager.DepositQueue memory spotTxn = abi.decode(spot.transaction, (IRabbitManager.DepositQueue));

                manager.unqueue(i, abi.encode(IRabbitManager.DepositResponse({shares: spotTxn.amount})));
            } else if (spot.spotType == IRabbitManager.SpotType.Withdraw) {
                IRabbitManager.WithdrawQueue memory spotTxn =
                    abi.decode(spot.transaction, (IRabbitManager.WithdrawQueue));

                manager.unqueue(i, abi.encode(IRabbitManager.WithdrawResponse({amountToReceive: spotTxn.amount})));
            } else {}
        }

        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                        DEPOSIT/WITHDRAWAL TESTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Unit test for a single deposit and withdraw flow in a perp pool.
    function testSingle(uint248 amount) public {
        vm.assume(amount > 0);

        deal(address(USDT), address(this), amount);

        USDT.safeApprove(address(manager), amount);

        manager.deposit(1, amount, address(this));

        (address router,, uint256 activeAmount,) = manager.pools(1);
        assertEq(activeAmount, 0);
        assertEq(manager.getUserActiveAmount(1, address(this)), activeAmount);
        assertEq(manager.getUserPendingAmount(1, address(this)), 0);
        assertEq(uint256(manager.queueCount()), 1);
        assertEq(uint256(manager.queueUpTo()), 0);

        processQueue();

        (,, activeAmount,) = manager.pools(1);
        assertEq(activeAmount, amount);
        assertEq(manager.getUserActiveAmount(1, address(this)), activeAmount);
        assertEq(manager.getUserPendingAmount(1, address(this)), 0);
        assertEq(uint256(manager.queueCount()), 1);
        assertEq(uint256(manager.queueUpTo()), 1);

        manager.withdraw(1, amount);

        (,, activeAmount,) = manager.pools(1);
        assertEq(activeAmount, amount);
        assertEq(manager.getUserActiveAmount(1, address(this)), activeAmount);
        assertEq(manager.getUserPendingAmount(1, address(this)), 0);
        assertEq(uint256(manager.queueCount()), 2);
        assertEq(uint256(manager.queueUpTo()), 1);

        // Process queue.
        processQueue();

        (,, activeAmount,) = manager.pools(1);
        assertEq(activeAmount, 0);
        assertEq(manager.getUserActiveAmount(1, address(this)), activeAmount);
        assertEq(manager.getUserPendingAmount(1, address(this)), amount);
        assertEq(uint256(manager.queueCount()), 2);
        assertEq(uint256(manager.queueUpTo()), 2);

        // Simulate RabbitX withdrawal of tokens.
        vm.prank(address(rabbit));
        USDT.safeTransfer(address(router), amount);

        // Claim tokens.
        manager.claim(address(this), 1);

        (,, activeAmount,) = manager.pools(1);
        assertEq(activeAmount, 0);
        assertEq(manager.getUserActiveAmount(1, address(this)), activeAmount);
        assertEq(manager.getUserPendingAmount(1, address(this)), 0);
        assertEq(uint256(manager.queueCount()), 2);
        assertEq(uint256(manager.queueUpTo()), 2);
        assertEq(USDT.balanceOf(address(this)), amount);
        // TODO: Add fees.
        // assertEq(USDT.balanceOf(owner), manager.getTransactionFee(address(BTC)));
    }

    /// @notice Unit test for a double deposit and withdraw flow in a perp pool.
    function testDouble(uint256 amount) public {
        vm.assume(amount > 0 && amount < type(uint120).max);

        deal(address(USDT), address(this), amount * 2, true);

        USDT.safeApprove(address(manager), amount * 2);

        manager.deposit(1, amount, address(this));

        (address router,, uint256 activeAmount,) = manager.pools(1);
        assertEq(activeAmount, 0);
        assertEq(manager.getUserActiveAmount(1, address(this)), activeAmount);
        assertEq(manager.getUserPendingAmount(1, address(this)), 0);
        assertEq(uint256(manager.queueCount()), 1);
        assertEq(uint256(manager.queueUpTo()), 0);

        processQueue();

        (,, activeAmount,) = manager.pools(1);
        assertEq(activeAmount, amount);
        assertEq(manager.getUserActiveAmount(1, address(this)), activeAmount);
        assertEq(manager.getUserPendingAmount(1, address(this)), 0);
        assertEq(uint256(manager.queueCount()), 1);
        assertEq(uint256(manager.queueUpTo()), 1);

        manager.deposit(1, amount, address(this));

        (,, activeAmount,) = manager.pools(1);
        assertEq(activeAmount, amount);
        assertEq(manager.getUserActiveAmount(1, address(this)), activeAmount);
        assertEq(manager.getUserPendingAmount(1, address(this)), 0);
        assertEq(uint256(manager.queueCount()), 2);
        assertEq(uint256(manager.queueUpTo()), 1);

        processQueue();

        (,, activeAmount,) = manager.pools(1);
        assertEq(activeAmount, amount * 2);
        assertEq(manager.getUserActiveAmount(1, address(this)), activeAmount);
        assertEq(manager.getUserPendingAmount(1, address(this)), 0);
        assertEq(uint256(manager.queueCount()), 2);
        assertEq(uint256(manager.queueUpTo()), 2);

        manager.withdraw(1, amount);

        (,, activeAmount,) = manager.pools(1);
        assertEq(activeAmount, amount * 2);
        assertEq(manager.getUserActiveAmount(1, address(this)), activeAmount);
        assertEq(manager.getUserPendingAmount(1, address(this)), 0);
        assertEq(uint256(manager.queueCount()), 3);
        assertEq(uint256(manager.queueUpTo()), 2);

        // Process queue.
        processQueue();

        (,, activeAmount,) = manager.pools(1);
        assertEq(activeAmount, amount);
        assertEq(manager.getUserActiveAmount(1, address(this)), activeAmount);
        assertEq(manager.getUserPendingAmount(1, address(this)), amount);
        assertEq(uint256(manager.queueCount()), 3);
        assertEq(uint256(manager.queueUpTo()), 3);

        manager.withdraw(1, amount);

        (,, activeAmount,) = manager.pools(1);
        assertEq(activeAmount, amount);
        assertEq(manager.getUserActiveAmount(1, address(this)), activeAmount);
        assertEq(manager.getUserPendingAmount(1, address(this)), amount);
        assertEq(uint256(manager.queueCount()), 4);
        assertEq(uint256(manager.queueUpTo()), 3);

        // Process queue.
        processQueue();

        (,, activeAmount,) = manager.pools(1);
        assertEq(activeAmount, 0);
        assertEq(manager.getUserActiveAmount(1, address(this)), activeAmount);
        assertEq(manager.getUserPendingAmount(1, address(this)), amount * 2);
        assertEq(uint256(manager.queueCount()), 4);
        assertEq(uint256(manager.queueUpTo()), 4);

        // Simulate RabbitX withdrawal of tokens.
        vm.prank(address(rabbit));
        USDT.safeTransfer(address(router), amount * 2);

        // Claim tokens.
        manager.claim(address(this), 1);

        (,, activeAmount,) = manager.pools(1);
        assertEq(activeAmount, 0);
        assertEq(manager.getUserActiveAmount(1, address(this)), activeAmount);
        assertEq(manager.getUserPendingAmount(1, address(this)), 0);
        assertEq(uint256(manager.queueCount()), 4);
        assertEq(uint256(manager.queueUpTo()), 4);
        assertEq(USDT.balanceOf(address(this)), amount * 2);
        // TODO: Add fees.
        // assertEq(USDT.balanceOf(owner), manager.getTransactionFee(address(BTC)));
    }

    /// @notice Unit test for a single deposit and withdraw flow in a perp pool for a different receiver.
    function testOtherReceiver(uint248 amount) public {
        vm.assume(amount > 0);

        deal(address(USDT), address(this), amount);

        USDT.safeApprove(address(manager), amount);

        manager.deposit(1, amount, address(0xbeef));

        (address router,, uint256 activeAmount,) = manager.pools(1);
        assertEq(activeAmount, 0);
        assertEq(manager.getUserActiveAmount(1, address(this)), 0);
        assertEq(manager.getUserActiveAmount(1, address(0xbeef)), activeAmount);
        assertEq(manager.getUserPendingAmount(1, address(this)), 0);
        assertEq(manager.getUserPendingAmount(1, address(0xbeef)), 0);
        assertEq(uint256(manager.queueCount()), 1);
        assertEq(uint256(manager.queueUpTo()), 0);

        processQueue();

        (,, activeAmount,) = manager.pools(1);
        assertEq(activeAmount, amount);
        assertEq(manager.getUserActiveAmount(1, address(this)), 0);
        assertEq(manager.getUserActiveAmount(1, address(0xbeef)), activeAmount);
        assertEq(manager.getUserPendingAmount(1, address(this)), 0);
        assertEq(manager.getUserPendingAmount(1, address(0xbeef)), 0);
        assertEq(uint256(manager.queueCount()), 1);
        assertEq(uint256(manager.queueUpTo()), 1);

        vm.prank(address(0xbeef));
        manager.withdraw(1, amount);

        (,, activeAmount,) = manager.pools(1);
        assertEq(activeAmount, amount);
        assertEq(manager.getUserActiveAmount(1, address(this)), 0);
        assertEq(manager.getUserActiveAmount(1, address(0xbeef)), activeAmount);
        assertEq(manager.getUserPendingAmount(1, address(this)), 0);
        assertEq(manager.getUserPendingAmount(1, address(0xbeef)), 0);
        assertEq(uint256(manager.queueCount()), 2);
        assertEq(uint256(manager.queueUpTo()), 1);

        // Process queue.
        processQueue();

        (,, activeAmount,) = manager.pools(1);
        assertEq(activeAmount, 0);
        assertEq(manager.getUserActiveAmount(1, address(this)), 0);
        assertEq(manager.getUserActiveAmount(1, address(0xbeef)), activeAmount);
        assertEq(manager.getUserPendingAmount(1, address(this)), 0);
        assertEq(manager.getUserPendingAmount(1, address(0xbeef)), amount);
        assertEq(uint256(manager.queueCount()), 2);
        assertEq(uint256(manager.queueUpTo()), 2);

        // Simulate RabbitX withdrawal of tokens.
        vm.prank(address(rabbit));
        USDT.safeTransfer(address(router), amount);

        // Claim tokens.
        manager.claim(address(0xbeef), 1);

        (,, activeAmount,) = manager.pools(1);
        assertEq(activeAmount, 0);
        assertEq(manager.getUserActiveAmount(1, address(this)), 0);
        assertEq(manager.getUserActiveAmount(1, address(0xbeef)), activeAmount);
        assertEq(manager.getUserPendingAmount(1, address(this)), 0);
        assertEq(manager.getUserPendingAmount(1, address(0xbeef)), 0);
        assertEq(uint256(manager.queueCount()), 2);
        assertEq(uint256(manager.queueUpTo()), 2);
        assertEq(USDT.balanceOf(address(this)), 0);
        assertEq(USDT.balanceOf(address(0xbeef)), amount);
        // TODO: Add fees.
        // assertEq(USDT.balanceOf(owner), manager.getTransactionFee(address(BTC)));
    }

    /*//////////////////////////////////////////////////////////////
                     DEPOSIT/WITHDRAWAL SANITY CHECK TESTS
        //////////////////////////////////////////////////////////////*/

    /// @notice Unit test for a failed deposit due to not enough balance but enough approval.
    function testDepositWithNoBalance(uint256 amount) public {
        vm.assume(amount > 0);

        USDT.safeApprove(address(manager), amount);

        deal(address(USDT), address(this), amount);

        manager.deposit(1, amount, address(this));

        USDT.safeTransfer(address(0xbeef), amount);

        uint256 userActiveAmount = manager.getUserActiveAmount(1, address(this));

        assertEq(userActiveAmount, 0);

        // Silently reverts and spot is skipped.
        vm.prank(externalAccount);
        manager.unqueue(1, abi.encode(IRabbitManager.DepositResponse({shares: amount})));

        userActiveAmount = manager.getUserActiveAmount(1, address(this));

        assertEq(userActiveAmount, 0);

        // Check that the spot was indeed skipped.
        assertEq(manager.queueUpTo(), 1);
    }

    /// @notice Unit test for a failed deposit due to zero approval.
    function testDepositWithNoApproval(uint256 amount) public {
        vm.assume(amount > 0);

        deal(address(USDT), address(this), amount);

        manager.deposit(1, amount, address(this));

        uint256 userActiveAmount = manager.getUserActiveAmount(1, address(this));

        assertEq(userActiveAmount, 0);

        // Silently reverts and spot is skipped.
        vm.prank(externalAccount);
        manager.unqueue(1, abi.encode(IRabbitManager.DepositResponse({shares: amount})));

        userActiveAmount = manager.getUserActiveAmount(1, address(this));

        assertEq(userActiveAmount, 0);

        // Check that the spot was indeed skipped.
        assertEq(manager.queueUpTo(), 1);
    }

    /// @notice Unit test for all checks in deposit and withdraw functions for a perp pool.
    function testChecks() public {
        // Deposit checks
        vm.expectRevert(abi.encodeWithSelector(RabbitManager.InvalidPool.selector, 69));
        manager.deposit(69, 1, address(this));

        vm.expectRevert(abi.encodeWithSelector(RabbitManager.ZeroAddress.selector));
        manager.deposit(1, 1, address(0));

        // Withdraw checks
        vm.expectRevert(abi.encodeWithSelector(RabbitManager.InvalidPool.selector, 69));
        manager.withdraw(69, 1);
    }

    /// @notice Unit test for all checks in the claim function
    function testClaimChecks() public {
        vm.expectRevert(abi.encodeWithSelector(RabbitManager.InvalidPool.selector, 69));
        manager.claim(address(0), 69);

        vm.expectRevert(abi.encodeWithSelector(RabbitManager.ZeroAddress.selector));
        manager.claim(address(0), 1);
    }

    /// @notice Unit test for a failed deposit due to exceeding the hardcap.
    function testHardcapReached() public {
        uint256 amount = 100 * 10 ** USDT.decimals();

        deal(address(USDT), address(this), amount * 2);

        USDT.safeApprove(address(manager), amount * 2);

        vm.prank(owner);
        manager.updatePoolHardcap(1, amount);

        // Deposit should succeed because amounts and hardcaps are the same.
        manager.deposit(1, amount, address(this));

        processQueue();

        assertEq(manager.getUserActiveAmount(1, address(this)), amount);

        // Deposit request passes but fails silently when processing, so no change is applied.
        manager.deposit(1, amount, address(this));

        processQueue();

        assertEq(manager.getUserActiveAmount(1, address(this)), amount);

        assertEq(manager.queueUpTo(), 2);
    }

    /// @notice Unit test for safety checks on unqueue function.
    function testUnqueue() public {
        uint256 amount = 100 * 10 ** USDT.decimals();

        deal(address(USDT), address(this), amount);

        USDT.safeApprove(address(manager), amount);

        // Get the pool router.
        (address router,,,) = manager.pools(1);

        // Deposit queued first.
        manager.deposit(1, amount, address(this));

        // Withdraw queued second.
        manager.withdraw(1, amount);

        vm.expectRevert(
            abi.encodeWithSelector(RabbitManager.NotExternalAccount.selector, router, externalAccount, address(this))
        );
        manager.unqueue(1, bytes(""));

        vm.expectRevert(abi.encodeWithSelector(RabbitManager.InvalidSpot.selector, 69, 0));
        vm.prank(externalAccount);
        manager.unqueue(69, abi.encode(IRabbitManager.DepositResponse({shares: amount})));

        vm.prank(externalAccount);
        manager.unqueue(1, abi.encode(IRabbitManager.DepositResponse({shares: amount})));

        assertEq(manager.getUserActiveAmount(1, address(this)), amount);
    }

    /*//////////////////////////////////////////////////////////////
                            POOL MANAGE TESTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Unit test for adding and updating a pool.
    function testAddAndUpdatePool() public {
        vm.startPrank(owner);

        manager.addPool(999, type(uint256).max, externalAccount);

        // Get the pool data.
        (address router, IRabbitManager.PoolType poolType, uint256 activeAmount, uint256 hardcap) = manager.pools(999);

        assertTrue(router != address(0));
        assertEq(uint8(poolType), uint8(IRabbitManager.PoolType.Perp));
        assertEq(activeAmount, 0);
        assertEq(hardcap, type(uint256).max);

        manager.updatePoolHardcap(999, 0);

        (router, poolType, activeAmount, hardcap) = manager.pools(999);

        assertTrue(router != address(0));
        assertEq(uint8(poolType), uint8(IRabbitManager.PoolType.Perp));
        assertEq(activeAmount, 0);
        assertEq(hardcap, 0);
    }

    /*//////////////////////////////////////////////////////////////
                        POOL MANAGE SANITY CHECK TESTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Unit test for unauthorized add and update a pool.
    function testUnauthorizedAddAndUpdate() public {
        vm.expectRevert("Ownable: caller is not the owner");
        manager.updatePoolHardcap(1, 0);

        vm.expectRevert("Ownable: caller is not the owner");
        manager.addPool(999, type(uint256).max, externalAccount);
    }

    /// @notice Unit test for trying to add a pool that already exists with the ID.
    function testDuplicatedPool() public {
        vm.startPrank(owner);

        vm.expectRevert(abi.encodeWithSelector(RabbitManager.InvalidPool.selector, 1));
        manager.addPool(1, 0, externalAccount);
    }

    /*//////////////////////////////////////////////////////////////
                                PAUSED TESTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Unit test for paused deposits.
    function testDepositsPaused() public {
        vm.prank(owner);
        manager.pause(true, false, false);

        vm.expectRevert(RabbitManager.DepositsPaused.selector);
        manager.deposit(1, 1, address(this));
    }

    /// @notice Unit test for paused withdrawals.
    function testWithdrawalsPaused() public {
        vm.prank(owner);
        manager.pause(false, true, false);

        vm.expectRevert(RabbitManager.WithdrawalsPaused.selector);
        manager.withdraw(1, 1);
    }

    /// @notice Unit test for paused claims.
    function testClaimsPaused() public {
        vm.prank(owner);
        manager.pause(false, false, true);

        vm.expectRevert(RabbitManager.ClaimsPaused.selector);
        manager.claim(address(this), 1);
    }

    /*//////////////////////////////////////////////////////////////
                                PROXY TESTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Unit test for initializing the proxy.
    function testInitialize() public {
        // Deploy and initialize the proxy contract.
        new ERC1967Proxy(
            address(rabbitManagerImplementation),
            abi.encodeWithSignature("initialize(address,uint256)", address(rabbit), 1000000)
        );
    }

    /// @notice Unit test for failing to initialize the proxy twice.
    function testFailDoubleInitiliaze() public {
        manager.initialize(address(0), 0);
    }

    // TODO: Uncomment
    // /// @notice Unit test for upgrading the proxy and running a spot single unit test.
    // function testUpgradeProxy() public {
    //     // Deploy another implementation and upgrade proxy to it.
    //     vm.startPrank(owner);
    //     manager.upgradeTo(address(new RabbitManager()));
    //     vm.stopPrank();

    //     testSingle(100 * 10 ** USDT.decimals());
    // }

    /// @notice Unit test for failing to upgrade the proxy.
    function testFailUnauthorizedUpgrade() public {
        manager.upgradeTo(address(0));
    }

    //     /*//////////////////////////////////////////////////////////////
    //                               OTHER TESTS
    //     //////////////////////////////////////////////////////////////*/

    //     /// @notice Unit test for getting the next spot in queue.
    //     function testGetNextSpot() public {
    //         uint256 amountBTC = 10 * 10 ** 8; // 10 BTC
    //         uint256 amountUSDC = 100 * 10 ** 6; // 100 USDC

    //         deal(address(BTC), address(this), amountBTC);
    //         deal(address(USDC), address(this), amountUSDC);

    //         BTC.approve(address(manager), amountBTC);
    //         USDC.approve(address(manager), amountUSDC);

    //         // Deposit 10 BTC and 100 USDC.
    //         manager.depositPerp{value: fee}(2, address(BTC), amountBTC, address(this));
    //         manager.depositPerp{value: fee}(2, address(USDC), amountUSDC, address(this));
    //         processQueue();

    //         // Withdraw 10 BTC paying fee in BTC.
    //         manager.withdrawPerp{value: fee}(2, address(BTC), amountBTC);

    //         IRabbitManager.Spot memory spot = manager.nextSpot();
    //         IRabbitManager.WithdrawPerp memory spotTxn = abi.decode(spot.transaction, (IRabbitManager.WithdrawPerp));

    //         assertEq(spot.sender, address(this));
    //         assertEq(spotTxn.id, 2);
    //         assertEq(spotTxn.tokenId, 1);
    //         assertEq(spotTxn.amount, amountBTC);

    //         // Withdraw 100 USDC paying fee in USDC.
    //         manager.withdrawPerp{value: fee}(2, address(USDC), amountUSDC);

    //         spot = manager.nextSpot();
    //         spotTxn = abi.decode(spot.transaction, (IRabbitManager.WithdrawPerp));

    //         assertEq(spot.sender, address(this));
    //         assertEq(spotTxn.id, 2);
    //         assertEq(spotTxn.tokenId, 1);
    //         assertEq(spotTxn.amount, amountBTC);

    //         vm.startPrank(externalAccount);
    //         manager.unqueue(
    //             manager.queueUpTo() + 1, abi.encode(IRabbitManager.WithdrawPerpResponse({amountToReceive: amountBTC}))
    //         );

    //         spot = manager.nextSpot();
    //         spotTxn = abi.decode(spot.transaction, (IRabbitManager.WithdrawPerp));

    //         assertEq(spot.sender, address(this));
    //         assertEq(spotTxn.id, 2);
    //         assertEq(spotTxn.tokenId, 0);
    //         assertEq(spotTxn.amount, amountUSDC);

    //         manager.unqueue(
    //             manager.queueUpTo() + 1, abi.encode(IRabbitManager.WithdrawPerpResponse({amountToReceive: amountUSDC}))
    //         );

    //         spot = manager.nextSpot();

    //         assertEq(spot.sender, address(0));
    //         assertEq(spot.router, address(0));
    //         assertEq(uint8(spot.spotType), uint8(IRabbitManager.SpotType.Empty));
    //         assertEq(spot.transaction, "");

    //         vm.stopPrank();
    //     }

    //     /// @notice Unit test for a cross product deposit, withdraw, and claim flow.
    //     function testCrossProduct() public {
    //         uint72 amountBTC = 1 * 10 ** 8; // 1 BTC
    //         uint256 amountUSDC = manager.getBalancedAmount(address(BTC), address(USDC), amountBTC);

    //         deal(address(BTC), address(this), amountBTC);
    //         deal(address(USDC), address(this), amountUSDC * 2);

    //         BTC.approve(address(manager), amountBTC);
    //         USDC.approve(address(manager), amountUSDC * 2);

    //         manager.depositSpot{value: fee}(
    //             1, spotTokens[0], spotTokens[1], amountBTC, amountUSDC, amountUSDC, address(this)
    //         );
    //         processQueue();
    //         manager.withdrawSpot{value: fee}(1, spotTokens[0], spotTokens[1], amountBTC);

    //         manager.depositPerp{value: fee}(2, address(USDC), amountUSDC, address(this));
    //         processQueue();
    //         manager.withdrawPerp{value: fee}(2, address(USDC), amountUSDC);

    //         processQueue();
    //         processSlowModeTxs();

    //         assertEq(
    //             sumPendingBalance(address(USDC), address(this)),
    //             (amountUSDC * 2)
    //                 - (
    //                     manager.getUserFee(2, address(USDC), address(this))
    //                         + manager.getUserFee(1, address(USDC), address(this))
    //                 )
    //         );

    //         (address router1,,,) = manager.getPoolToken(1, address(0));
    //         (address router2,,,) = manager.getPoolToken(2, address(0));

    //         assertEq(BTC.balanceOf(router1) + BTC.balanceOf(router2), amountBTC);
    //         assertEq(USDC.balanceOf(router1) + USDC.balanceOf(router2), amountUSDC * 2);

    //         // used to fail because the pending balance is greater than than the USDC balance of the router1 as the pending balances are grouped by token, not by router or product.
    //         manager.claim(address(this), spotTokens[0], 1);
    //         manager.claim(address(this), spotTokens[1], 1);

    //         assertEq(BTC.balanceOf(router1) + BTC.balanceOf(router2), 0);
    //         assertEq(USDC.balanceOf(router1) + USDC.balanceOf(router2), amountUSDC);

    //         manager.claim(address(this), address(USDC), 2);

    //         assertEq(BTC.balanceOf(router1) + BTC.balanceOf(router2), 0);
    //         assertEq(USDC.balanceOf(router1) + USDC.balanceOf(router2), 0);
    //     }

    //     /// @notice Unit test for a different fee used for withdraws.
    //     function testFeesPerPool() public {
    //         uint256 amountBTC = 10 * 10 ** 8; // 10 BTC
    //         uint256 amountUSDC = 100 * 10 ** 6; // 100 USDC

    //         deal(address(BTC), address(this), amountBTC);
    //         deal(address(USDC), address(this), amountUSDC);

    //         BTC.approve(address(manager), amountBTC);
    //         USDC.approve(address(manager), amountUSDC);

    //         // Deposit 10 BTC and 100 USDC.
    //         manager.depositPerp{value: fee}(2, address(BTC), amountBTC, address(this));
    //         manager.depositPerp{value: fee}(2, address(USDC), amountUSDC, address(this));

    //         // Withdraw 10 BTC paying fee in BTC.
    //         manager.withdrawPerp{value: fee}(2, address(BTC), amountBTC);

    //         // Withdraw 100 USDC paying fee in USDC.
    //         manager.withdrawPerp{value: fee}(2, address(USDC), amountUSDC);

    //         processQueue();

    //         // Check that the fees are stored well (are more than 0).
    //         assertGe(manager.getUserFee(2, address(BTC), address(this)), 0);
    //         assertGe(manager.getUserFee(2, address(USDC), address(this)), 0);

    //         processSlowModeTxs();

    //         uint256 beforeClaimUSDC = USDC.balanceOf(owner);
    //         uint256 beforeClaimBTC = BTC.balanceOf(owner);

    //         // Claim and check that the fees and tokens were distributed.
    //         manager.claim(address(this), address(BTC), 2);
    //         manager.claim(address(this), address(USDC), 2);

    //         uint256 afterClaimUSDC = USDC.balanceOf(owner);
    //         uint256 afterClaimBTC = BTC.balanceOf(owner);

    //         assertEq(afterClaimBTC - beforeClaimBTC, manager.getTransactionFee(address(BTC)));
    //         assertEq(afterClaimUSDC - beforeClaimUSDC, manager.getTransactionFee(address(USDC)));
    //         assertEq(BTC.balanceOf(address(this)), amountBTC - (afterClaimBTC - beforeClaimBTC));
    //         assertEq(USDC.balanceOf(address(this)), amountUSDC - (afterClaimUSDC - beforeClaimUSDC));
    //     }

    //     /// @notice Unit test for skipping the spot in the queue.
    //     function testSkipSpot() public {
    //         uint256 amountBTC = manager.getTransactionFee(address(BTC));
    //         deal(address(BTC), address(this), amountBTC);

    //         BTC.approve(address(manager), amountBTC);

    //         // Deposit BTC and withdraw BTC.
    //         manager.depositPerp{value: fee}(2, address(BTC), amountBTC, address(this));
    //         manager.withdrawPerp{value: fee}(2, address(BTC), amountBTC);

    //         RabbitManager.Spot memory spot = manager.nextSpot();
    //         IRabbitManager.DepositPerp memory spotTxn = abi.decode(spot.transaction, (IRabbitManager.DepositPerp));

    //         assertEq(spot.sender, address(this));
    //         assertEq(spotTxn.id, 2);
    //         assertEq(spotTxn.token, address(BTC));
    //         assertEq(spotTxn.amount, amountBTC);
    //         assertEq(spotTxn.receiver, address(this));

    //         assertEq(manager.getUserActiveAmount(2, address(BTC), address(this)), 0);

    //         // Process tx fails silently and spot is skipped. No changes applied.
    //         vm.startPrank(externalAccount);
    //         manager.unqueue(1, "");
    //         manager.unqueue(2, "");

    //         assertEq(manager.getUserActiveAmount(2, address(BTC), address(this)), 0);
    //         assertEq(manager.queueUpTo(), 2);
    //     }

    //     /// @notice Unit test to check that any remaining fee is transfered back to user.
    //     function testElixirFee() public {
    //         uint256 balanceBefore = address(this).balance;

    //         vm.expectRevert(abi.encodeWithSelector(RabbitManager.FeeTooLow.selector, fee - 1, fee));
    //         manager.depositPerp{value: fee - 1}(2, address(0), 1, address(this));

    //         assertEq(address(this).balance, balanceBefore);
    //         assertEq(externalAccount.balance, 0);

    //         // Deposit BTC to perp pool.
    //         manager.depositPerp{value: fee + 1}(2, address(0), 1, address(this));

    //         assertEq(address(this).balance, balanceBefore - (fee + 1));
    //         assertEq(externalAccount.balance, fee + 1);
    //     }
}
