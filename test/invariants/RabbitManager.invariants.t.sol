// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import "forge-std/Test.sol";

import {MockToken} from "test/utils/MockToken.sol";

import {IERC20Metadata} from "openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";
import {ERC1967Proxy} from "openzeppelin/proxy/ERC1967/ERC1967Proxy.sol";

import {IRabbitX} from "src/interfaces/IRabbitX.sol";

import {RabbitManager, IRabbitManager} from "src/RabbitManager.sol";
import {Handler} from "test/invariants/RabbitManagerHandler.sol";

contract TestInvariantsRabbitManager is Test {
    /*//////////////////////////////////////////////////////////////
                                VARIABLES
    //////////////////////////////////////////////////////////////*/

    // RabbitX addresses
    IRabbitX public rabbit = IRabbitX(0x3b8F6D6970a24A58b52374C539297ae02A3c4Ae4);

    // Elixir contracts
    RabbitManager public rabbitManagerImplementation;
    ERC1967Proxy public proxy;
    RabbitManager public manager;

    // Tokens
    IERC20Metadata public USDT = IERC20Metadata(0xdAC17F958D2ee523a2206206994597C13D831ec7);

    uint256 public USDT_TOTAL;

    // Handler
    Handler public handler;

    /*//////////////////////////////////////////////////////////////
                                 HELPERS
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), 18829846);

        // Deploy Manager implementation
        rabbitManagerImplementation = new RabbitManager();

        // Deploy and initialize the proxy contract.
        proxy = new ERC1967Proxy(
            address(rabbitManagerImplementation),
            abi.encodeWithSignature("initialize(address,uint256)", address(rabbit), 1000000)
        );

        // Wrap in ABI to support easier calls
        manager = RabbitManager(address(proxy));

        // Wrap into the handler.
        handler = new Handler(rabbit, manager, USDT, address(this));

        // Add pool.
        manager.addPool(1, type(uint256).max, address(this));

        // Add second pool.
        manager.addPool(2, type(uint256).max, address(this));

        // Set the total supply.
        USDT_TOTAL = USDT.totalSupply();

        // Mint tokens.
        deal(address(USDT), address(handler), USDT_TOTAL, true);

        // Select the selectors to use for fuzzing.
        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = Handler.deposit.selector;
        selectors[1] = Handler.withdraw.selector;
        selectors[2] = Handler.claim.selector;

        // Set the target selector.
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));

        // Set the target contract.
        targetContract(address(handler));
    }

    /*//////////////////////////////////////////////////////////////
                  DEPOSIT/WITHDRAWAL INVARIANT TESTS
    //////////////////////////////////////////////////////////////*/

    // The sum of the Handler's balances, the active amounts, and the pending amounts should always equal the total amount given.
    // Aditionally, the total amounts given must match the total supply of the tokens.
    function invariant_conservationOfTokens() public {
        // Active amounts
        (,, uint256 activeAmount,) = manager.pools(1);

        // Pending amounts
        uint256 pendingAmount = handler.reduceActors(0, this.accumulatePendingBalance);

        assertEq(USDT_TOTAL, USDT.balanceOf(address(handler)) + activeAmount + pendingAmount + handler.ghost_fees());
    }

    // The active amounts should always be equal to the sum of individual active balances. Obtained by the ghost values.
    function invariant_solvencyDeposits() public {
        // Active amounts
        (,, uint256 activeAmount,) = manager.pools(1);

        assertEq(activeAmount, handler.ghost_deposits() - handler.ghost_withdraws());
    }

    // The active amounts should always be equal to the sum of individual active balances. Obtained by the sum of each user.
    function invariant_solvencyBalances() public {
        uint256 sumOfActiveBalance = handler.reduceActors(0, this.accumulateActiveBalance);

        (,, uint256 activeAmount,) = manager.pools(1);

        assertEq(activeAmount, sumOfActiveBalance);
    }

    // No individual account balance can exceed the tokens totalSupply().
    function invariant_depositorBalances() public {
        handler.forEachActor(this.assertAccountBalanceLteTotalSupply);
    }

    // The sum of the deposits must always be greater or equal than the sum of withdraws.
    function invariant_depositsAndWithdraws() public {
        uint256 sumOfDeposits = handler.ghost_deposits();

        uint256 sumOfWithdraws = handler.ghost_withdraws();

        assertGe(sumOfDeposits, sumOfWithdraws);
    }

    // The sum of ghost withdrawals must be equal to the sum of pending balances, claims and ghost fees.
    function invariant_withdrawBalances() public {
        uint256 sumOfClaims = handler.ghost_claims();

        uint256 sumOfPendingBalances = handler.reduceActors(0, this.accumulatePendingBalance);

        assertEq(handler.ghost_withdraws(), sumOfPendingBalances + sumOfClaims + handler.ghost_fees());
    }

    // Two pools cannot share the same router. Each pool must have a unique and constant router for all tokens supported by it.
    function invariant_router() public {
        (address router1,,,) = manager.pools(1);
        (address router2,,,) = manager.pools(2);

        assertTrue(router1 != router2);
    }

    /*//////////////////////////////////////////////////////////////
                                HELPERS
    //////////////////////////////////////////////////////////////*/

    function assertAccountBalanceLteTotalSupply(address account) external {
        uint256 activeAmount = manager.getUserActiveAmount(1, account);

        assertLe(activeAmount, USDT.totalSupply());
    }

    function accumulateActiveBalance(uint256 balance, address caller) external view returns (uint256) {
        return balance + manager.getUserActiveAmount(1, caller);
    }

    function accumulatePendingBalance(uint256 balance, address caller) external view returns (uint256) {
        return balance + manager.getUserPendingAmount(1, caller);
    }

    receive() external payable {}

    // Exclude from coverage report
    function test() public {}
}
