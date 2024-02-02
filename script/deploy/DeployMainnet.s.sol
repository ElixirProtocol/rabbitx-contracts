// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import "forge-std/Script.sol";
import {DeployBase} from "./DeployBase.s.sol";

contract DeployMainnet is DeployBase {
    constructor() DeployBase(0x3b8F6D6970a24A58b52374C539297ae02A3c4Ae4, 0xD7cb7F791bb97A1a8B5aFc3aec5fBD0BEC4536A5) {}

    function run() external {
        setup();
    }

    // Exclude from coverage report
    function test() public override {}
}
