// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import {CommonBase} from "forge-std/Base.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {StdUtils} from "forge-std/StdUtils.sol";
import {console} from "forge-std/console.sol";

import {IERC20Metadata} from "openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";

import {AddressSet, LibAddressSet} from "test/utils/AddressSet.sol";
import {MockToken} from "test/utils/MockToken.sol";

import {IRabbitX} from "src/interfaces/IRabbitX.sol";

import {RabbitManager, IRabbitManager} from "src/RabbitManager.sol";

contract Handler is CommonBase, StdCheats, StdUtils {
    using SafeERC20 for IERC20Metadata;
    using LibAddressSet for AddressSet;

    /*//////////////////////////////////////////////////////////////
                                VARIABLES
    //////////////////////////////////////////////////////////////*/

    // RabbitX contracts
    IRabbitX public rabbit;

    // Elixir contracts
    RabbitManager public manager;

    // Elixir external account
    address public externalAccount;

    // Tokens
    IERC20Metadata public USDT;

    // Ghost balances
    uint256 public ghost_deposits;
    uint256 public ghost_withdraws;
    uint256 public ghost_fees;
    uint256 public ghost_claims;

    // Current actor
    address public currentActor;

    // Actors
    AddressSet internal _actors;

    // Elixir fee
    uint256 public fee;

    /*//////////////////////////////////////////////////////////////
                                MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier createActor() {
        currentActor = msg.sender;
        _actors.add(msg.sender);
        _;
    }

    modifier useActor(uint256 actorIndexSeed) {
        currentActor = _actors.rand(actorIndexSeed);
        _;
    }

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(IRabbitX _rabbit, RabbitManager _manager, IERC20Metadata _usdt, address _externalAccount) {
        rabbit = _rabbit;
        manager = _manager;
        USDT = _usdt;
        externalAccount = _externalAccount;

        // Store the Elixir gas fee for later use.
        uint256 gasPrice;
        assembly {
            gasPrice := gasprice()
        }
        fee = manager.elixirGas() * gasPrice;
    }

    /*//////////////////////////////////////////////////////////////
                                FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function deposit(uint256 amount) public createActor {
        amount = bound(amount, 0, USDT.balanceOf(address(this)));

        _pay(currentActor, amount);

        vm.startPrank(currentActor);

        USDT.safeApprove(address(manager), amount);

        manager.deposit{value: fee}(1, amount, currentActor);

        vm.stopPrank();

        processQueue();

        ghost_deposits += amount;
    }

    function withdraw(uint256 actorSeed, uint256 amount) public useActor(actorSeed) {
        amount = bound(amount, 0, manager.getUserActiveAmount(1, currentActor));

        ghost_fees += amount * manager.elixirFee() / 10_000;

        vm.startPrank(currentActor);

        manager.withdraw{value: fee}(1, amount);

        vm.stopPrank();

        processQueue();

        ghost_withdraws += amount;
    }

    function claim(uint256 actorSeed) public useActor(actorSeed) {
        if (currentActor == address(0)) return;

        simulate(1, currentActor);

        vm.startPrank(currentActor);

        uint256 beforeUSDT = USDT.balanceOf(currentActor);

        manager.claim(currentActor, 1);

        uint256 receivedUSDT = USDT.balanceOf(currentActor) - beforeUSDT;

        _pay(address(this), receivedUSDT);

        vm.stopPrank();

        ghost_claims += receivedUSDT;
    }

    /*//////////////////////////////////////////////////////////////
                                HELPERS
    //////////////////////////////////////////////////////////////*/

    function _pay(address to, uint256 amount) internal {
        USDT.safeTransfer(to, amount);
    }

    function forEachActor(function(address) external func) public {
        return _actors.forEach(func);
    }

    function reduceActors(uint256 acc, function(uint256,address) external returns (uint256) func)
        public
        returns (uint256)
    {
        return _actors.reduce(acc, func);
    }

    function actors() external view returns (address[] memory) {
        return _actors.addrs;
    }

    function simulate(uint256 id, address user) public {
        (address router,,,) = manager.pools(1);

        // Simulate RabbitX withdrawal of tokens.
        vm.startPrank(address(rabbit));
        USDT.safeTransfer(address(router), manager.getUserPendingAmount(id, user) + manager.getUserFee(id, user));
        vm.stopPrank();
    }

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

                manager.unqueue(
                    i,
                    abi.encode(
                        IRabbitManager.WithdrawResponse({
                            amountToReceive: spotTxn.amount,
                            withdrawalId: i,
                            v: 0,
                            r: bytes32(0),
                            s: bytes32(0)
                        })
                    )
                );
            } else {}
        }

        vm.stopPrank();
    }

    // Exclude from coverage report
    function test() public {}
}
