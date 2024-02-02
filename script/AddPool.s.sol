// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import "forge-std/Script.sol";

import {RabbitManager} from "src/RabbitManager.sol";

contract AddPool is Script {
    RabbitManager internal manager;

    function run() external {
        // Start broadcast.
        vm.startBroadcast(vm.envUint("KEY"));

        // Wrap in ABI to support easier calls.
        manager = RabbitManager(0x82dF40dea5E618725E7C7fB702b80224A1BB771F);

        // Deploy all 31 pools.
        for (uint256 i = 2; i < 32; i++) {
            manager.addPool(i, type(uint256).max, 0xD7cb7F791bb97A1a8B5aFc3aec5fBD0BEC4536A5);
            (address router,,,) = manager.pools(i);
            console.log("Pool %s: %s", i, router);
        }

        vm.stopBroadcast();
    }

    // Exclude from coverage report
    function test() public {}
}
