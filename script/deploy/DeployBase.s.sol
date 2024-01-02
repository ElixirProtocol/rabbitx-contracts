// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import "forge-std/Script.sol";

import {IRabbitX, RabbitManager, IRabbitManager} from "src/RabbitManager.sol";
import {ERC1967Proxy} from "openzeppelin/proxy/ERC1967/ERC1967Proxy.sol";

abstract contract DeployBase is Script {
    // Environment specific variables.
    IRabbitX public rabbit;
    address public externalAccount;

    // Deploy addresses.
    RabbitManager internal managerImplementation;
    ERC1967Proxy internal proxy;
    RabbitManager internal manager;

    constructor(address _rabbit, address _externalAccount) {
        rabbit = IRabbitX(_rabbit);
        externalAccount = _externalAccount;
    }

    function setup() internal {
        // Start broadcast.
        vm.startBroadcast(vm.envUint("KEY"));

        // Deploy Factory implementation.
        managerImplementation = new RabbitManager();

        // Deploy and initialize the proxy contract.
        proxy = new ERC1967Proxy(
            address(managerImplementation), abi.encodeWithSignature("initialize(address)", address(rabbit))
        );

        // Wrap in ABI to support easier calls
        manager = RabbitManager(address(proxy));

        // Add pool.
        manager.addPool(1, type(uint256).max, externalAccount);

        vm.stopBroadcast();
    }

    // Exclude from coverage report
    function test() public virtual {}
}
