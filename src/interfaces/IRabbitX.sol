// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

interface IRabbitX {
    function paymentToken() external view returns (address);
    function deposit(uint256 amount) external;
    function withdraw(uint256 id, address trader, uint256 amount, uint8 v, bytes32 r, bytes32 s) external;
}
