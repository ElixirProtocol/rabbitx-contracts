// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import "forge-std/Test.sol";

import {Utils} from "test/utils/Utils.sol";
import {MockToken} from "test/utils/MockToken.sol";
import {MockRabbit} from "test/utils/MockRabbit.sol";

import {ERC1967Proxy} from "openzeppelin/proxy/ERC1967/ERC1967Proxy.sol";

import {RabbitXPool} from "src/RabbitXPool.sol";
import {RabbitXPoolFactory} from "src/RabbitXPoolFactory.sol";

contract TestRabbitX is Test {
    /*//////////////////////////////////////////////////////////////
                                CONTRACTS
    //////////////////////////////////////////////////////////////*/

    // RabbitX contracts
    MockRabbit public rabbit;

    // Elixir contracts
    RabbitXPoolFactory public factory;

    /*//////////////////////////////////////////////////////////////
                                  USERS
    //////////////////////////////////////////////////////////////*/

    // Elixir users
    address public owner;

    /*//////////////////////////////////////////////////////////////
                                  MISC
    //////////////////////////////////////////////////////////////*/

    // Utils contract.
    Utils public utils;

    /*//////////////////////////////////////////////////////////////
                                 SET UP
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        utils = new Utils();
        address payable[] memory users = utils.createUsers(1);

        owner = users[0];
        vm.label(owner, "Owner");

        rabbit = new MockRabbit();

        vm.startPrank(owner);

        // Deploy pool implementation.
        address poolImplementation = address(new RabbitXPool());

        // Deploy pool factory.
        factory = new RabbitXPoolFactory(poolImplementation);

        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                        DEPOSIT/WITHDRAWAL TESTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Unit test to test if pools are deployed correctly.
    function testDeployPool() public {
        vm.startPrank(owner);

        address token = address(new MockToken());

        RabbitXPool pool = RabbitXPool(factory.deployPool(address(rabbit), token));

        vm.stopPrank();

        assertEq(pool.owner(), owner);
        assertEq(address(pool.rabbit()), address(rabbit));
        pool.rabbit();
        assertEq(address(pool.paymentToken()), token);
    }
}
