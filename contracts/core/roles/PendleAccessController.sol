// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {AccessControlEnumerableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";
import {IPAccessManagerCore} from "../../interfaces/IPAccessManager.sol";
import {PendleRolesConstants} from "./PendleRoles.sol";

/// @notice This will be deployed as TransparentUpgradeableProxy
contract PendleAccessController is IPAccessManagerCore, AccessControlEnumerableUpgradeable, PendleRolesConstants {
    mapping(address target => mapping(bytes4 selector => bytes32 roles)) public __unused__AllowedRoles;
    mapping(address target => mapping(bytes4 selector => mapping(address caller => bool))) public allowedAddresses;

    constructor() {
        _disableInitializers();
    }

    function initialize(address initialDefaultAdmin) external initializer {
        __AccessControlEnumerable_init();
        _grantRole(DEFAULT_ADMIN_ROLE, initialDefaultAdmin);
    }

    // function setAllowedRole(address target, bytes4 selector, bytes32 role) external onlyRole(DEFAULT_ADMIN_ROLE) {
    //     allowedRoles[target][selector] = role;
    //     emit AllowedRoleSet(target, selector, role);
    // }

    function setAllowedAddress(AllowedAddressRequest[] calldata requests) external onlyRole(DEFAULT_ADMIN_ROLE) {
        for (uint256 i = 0; i < requests.length; i++) {
            AllowedAddressRequest calldata req = requests[i];
            allowedAddresses[req.target][req.selector][req.caller] = req.allowed;
            emit AllowedAddressSet(req.target, req.selector, req.caller, req.allowed);
        }
    }

    function canCall(address caller, address target, bytes4 selector) external view returns (bool) {
        return allowedAddresses[target][selector][caller] || hasRole(DEFAULT_ADMIN_ROLE, caller);
    }

    function canDirectCallMarketHub(address caller) external view returns (bool) {
        return hasRole(_DIRECT_MARKET_HUB_ROLE, caller);
    }
}
