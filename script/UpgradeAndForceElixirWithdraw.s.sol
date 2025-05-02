// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import "forge-std/Script.sol";
import "forge-std/StdJson.sol";

import {RabbitManager} from "src/RabbitManager.sol";

contract UpgradeContract is Script {
    using stdJson for string;

    RabbitManager internal manager;
    RabbitManager internal newManager;

    function run() external {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/users.json");
        string memory json = vm.readFile(path);

        bytes memory rawUsers = vm.parseJson(json, "$[*].user_address");
        bytes memory rawPoolIds = vm.parseJson(json, "$[*].pool_id");
        bytes memory rawShares = vm.parseJson(json, "$[*].active_shares");
        bytes memory rawAmounts = vm.parseJson(json, "$[*].Override_active_amount");
        address[] memory users = abi.decode(rawUsers, (address[]));
        uint256[] memory poolIds = abi.decode(rawPoolIds, (uint256[]));
        uint256[] memory shares = abi.decode(rawShares, (uint256[]));
        uint256[] memory amounts = abi.decode(rawAmounts, (uint256[]));

        // Start broadcast.
        // vm.startBroadcast(vm.envUint("KEY"));
        vm.startBroadcast();

        // Wrap in ABI to support easier calls.
        manager = RabbitManager(0x82dF40dea5E618725E7C7fB702b80224A1BB771F);
        uint256 queueUpTo = manager.queueUpTo();

        // Get the RabbitX address before upgrading.
        address rabbit = address(manager.rabbit());

        // Deploy new implementation.
        newManager = new RabbitManager();

        // Upgrade proxy to new implementation.
        manager.upgradeTo(address(newManager));
        manager.pause(true, true, false);

        uint256[] memory previousPendingAmounts = new uint256[](users.length);
        for (uint256 i = 0; i < users.length; i++) {
          previousPendingAmounts[i] = manager.getUserPendingAmount(poolIds[i], users[i]);
        }

        manager.elixirWithdraw(poolIds, users, shares, amounts);
        for (uint256 i = 0; i < users.length; i++) {
          uint256 newPendingAmount = manager.getUserPendingAmount(poolIds[i], users[i]);
          require(newPendingAmount - previousPendingAmounts[i] == amounts[i]);
          uint256 newActiveAmount = manager.getUserActiveAmount(poolIds[i], users[i]);
          require(newActiveAmount == 0);
        }

        vm.stopBroadcast();

        // Check upgrade by ensuring storage is not changed.
        require(address(manager.rabbit()) == rabbit, "Invalid upgrade");
        require(manager.queueUpTo() == queueUpTo, "Invalid upgrade");
    }

    // Exclude from coverage report
    function test() public {}
}
