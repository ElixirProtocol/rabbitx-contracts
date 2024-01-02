// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import "forge-std/Script.sol";
import {DeployBase} from "./DeployBase.s.sol";

contract DeploySepolia is DeployBase {
    constructor() DeployBase(0xEE5638aC922f208D26511E7d5fd2bB850bcfAB40, 0x28CcdB531854d09D48733261688dc1679fb9A242) {}

    function run() external {
        setup();
    }

    // Exclude from coverage report
    function test() public override {}
}
