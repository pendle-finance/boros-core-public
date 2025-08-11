// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

// Interfaces
import {IPAccessManager} from "../../interfaces/IPAccessManager.sol";

// Libraries
import {Err} from "../../lib/Errors.sol";

// Not all contract uses all roles
// slither-disable-start unused-state

abstract contract PendleRolesConstants {
    bytes32 internal constant _DIRECT_MARKET_HUB_ROLE = keccak256("DIRECT_MARKET_HUB_ROLE");
    bytes32 internal constant _INITIALIZER_ROLE = keccak256("INITIALIZER_ROLE");
}

abstract contract PendleRolesPlugin is PendleRolesConstants {
    IPAccessManager internal immutable _PERM_CONTROLLER;

    constructor(address permController_) {
        _PERM_CONTROLLER = IPAccessManager(permController_);
    }

    modifier onlyAuthorized() {
        require(_PERM_CONTROLLER.canCall(msg.sender, address(this), msg.sig), Err.Unauthorized());
        _;
    }

    modifier onlyRole(bytes32 role) {
        require(_PERM_CONTROLLER.hasRole(role, msg.sender), Err.Unauthorized());
        _;
    }
}
// slither-disable-end unused-state
