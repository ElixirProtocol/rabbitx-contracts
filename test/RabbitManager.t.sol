// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import "forge-std/Test.sol";

import {Utils} from "./utils/Utils.sol";

import {IERC20Metadata} from "openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";
import {ERC1967Proxy} from "openzeppelin/proxy/ERC1967/ERC1967Proxy.sol";
import {Math} from "openzeppelin/utils/math/Math.sol";

import {IRabbitX} from "src/interfaces/IRabbitX.sol";

import {RabbitManager, IRabbitManager} from "src/RabbitManager.sol";
import {RabbitRouter} from "src/RabbitRouter.sol";

contract TestRabbitManager is Test {
    using Math for uint256;

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

    // Network fork ID.
    uint256 public networkFork;

    // RPC URL for Arbitrum fork.
    string public networkRpcUrl = vm.envString("ARBITRUM_RPC_URL");

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

        networkFork = vm.createFork(networkRpcUrl, 18829846);

        vm.selectFork(networkFork);

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
        manager.addPool(1, type(uint256).max, IRabbitManager.PoolType.Perp, externalAccount);

        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                        DEPOSIT/WITHDRAWAL TESTS
    //////////////////////////////////////////////////////////////*/
}
