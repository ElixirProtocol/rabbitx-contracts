// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import {BeaconProxy} from "openzeppelin/proxy/beacon/BeaconProxy.sol";
import {UpgradeableBeacon} from "openzeppelin/proxy/beacon/UpgradeableBeacon.sol";
import {RabbitXPool} from "src/RabbitXPool.sol";

/// @title Pool factory
/// @author The Elixir Team
/// @custom:security-contact security@elixir.finance
/// @notice Pool factory to create RabbitX minimal proxy pools.
contract RabbitXPoolFactory is UpgradeableBeacon {
    /*//////////////////////////////////////////////////////////////
                                VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice The created pools by this factory.
    mapping(address => bool) public pools;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a pool is deployed.
    /// @param proxy The proxy address of the pool.
    /// @param deployer The deployer of the pool.
    /// @param rabbit The RabbitX exchange address.
    /// @param token The token address.
    event PoolDeployed(address indexed proxy, address indexed deployer, address rabbit, address indexed token);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice The constructor of the factory, sets the beacon implementation and owner.
    constructor(address _implementation) UpgradeableBeacon(_implementation, msg.sender) {}

    /*//////////////////////////////////////////////////////////////
                                FACTORY 
    //////////////////////////////////////////////////////////////*/

    /// @dev Deploys a proxy that points to this contract as the beacon for the lastest implementation.
    function deployPool(address rabbit, address token) external onlyOwner returns (address proxy) {
        proxy = address(new BeaconProxy(address(this), ""));

        pools[proxy] = true;

        RabbitXPool(proxy).initialize(msg.sender, rabbit, token);

        emit PoolDeployed(proxy, msg.sender, rabbit, token);
    }
}
