// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

interface IRabbitX {
    function paymentToken() external view returns (address);
    function deposit(uint256 amount) external;
}
