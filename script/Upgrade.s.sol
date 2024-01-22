// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import "forge-std/Script.sol";

import {RabbitManager} from "src/RabbitManager.sol";

contract UpgradeContract is Script {
    RabbitManager internal manager;
    RabbitManager internal newManager;

    function run() external {
        // Start broadcast.
        vm.startBroadcast(vm.envUint("KEY"));

        // Wrap in ABI to support easier calls.
        manager = RabbitManager(0x82dF40dea5E618725E7C7fB702b80224A1BB771F);

        // Get the RabbitX address before upgrading.
        address rabbit = address(manager.rabbit());

        // Deploy new implementation.
        newManager = new RabbitManager();

        // Upgrade proxy to new implementation.
        manager.upgradeTo(address(newManager));

        vm.stopBroadcast();

        // Check upgrade by ensuring storage is not changed.
        require(address(manager.rabbit()) == rabbit, "Invalid upgrade");
    }

    // Exclude from coverage report
    function test() public {}
}
