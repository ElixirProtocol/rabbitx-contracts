// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import {Clones} from "openzeppelin/proxy/Clones.sol";

/// @title Pool factory
/// @author The Elixir Team
/// @custom:security-contact security@elixir.finance
/// @notice Pool factory to create RabbitX minimal proxy pools.
contract RabbitXPoolFactory {
    /*//////////////////////////////////////////////////////////////
                                VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice The pool implementation
    address public implementation;

    /// @notice The created pools by this factory.
    mapping(address => bool) public pools;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a pool is deployed.
    /// @param implementation The implementation of the pool.
    /// @param proxy The proxy address of the pool.
    /// @param deployer The deployer of the pool.
    event PoolDeployed(address indexed implementation, address proxy, address indexed deployer);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice The constructor of the factory.
    constructor(address _implementation) {
        implementation = _implementation;
    }

    /*//////////////////////////////////////////////////////////////
                                FACTORY 
    //////////////////////////////////////////////////////////////*/

    /// @dev Deploys a proxy that points to the given implementation.
    function deployPool(bytes memory _data, bytes32 _salt) external returns (address deployedProxy) {
        bytes32 salthash = keccak256(abi.encodePacked(msg.sender, _salt));
        deployedProxy = Clones.cloneDeterministic(implementation, salthash);

        pools[deployedProxy] = true;

        emit PoolDeployed(implementation, deployedProxy, msg.sender);

        // if (_data.length > 0) {
        //     // slither-disable-next-line unused-return
        //     Address.functionCall(deployedProxy, _data);
        // }
    }
}
