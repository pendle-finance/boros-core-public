// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {GeneratedStorageSlots} from "./../../../generated/slots.sol";
import {Account} from "./../../../types/Account.sol";

abstract contract AuthStorage {
    struct AuthModuleStorage {
        mapping(Account => mapping(address => uint256)) agentExpiry;
        mapping(address agent => uint64 nonce) signerNonce;
        mapping(Account account => address) accManager;
        mapping(address relayer => bool) allowedRelayer;
    }

    function _AMS() internal pure returns (AuthModuleStorage storage $) {
        bytes32 slot = GeneratedStorageSlots.AUTH_MODULE_STORAGE_LOCATION;
        assembly {
            $.slot := slot
        }
    }

    function _isAllowedRelayer(address relayer) internal view returns (bool) {
        return _AMS().allowedRelayer[relayer];
    }
}
