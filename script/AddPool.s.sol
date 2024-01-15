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

        manager.addPool(2, type(uint256).max, 0x28CcdB531854d09D48733261688dc1679fb9A242);
        manager.addPool(3, type(uint256).max, 0x28CcdB531854d09D48733261688dc1679fb9A242);
        manager.addPool(4, type(uint256).max, 0x28CcdB531854d09D48733261688dc1679fb9A242);

        vm.stopBroadcast();
    }

    // Exclude from coverage report
    function test() public {}
}
