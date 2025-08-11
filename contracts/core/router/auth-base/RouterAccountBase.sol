// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {GeneratedStorageSlots} from "./../../../generated/slots.sol";
import {Account, AccountLib} from "./../../../types/Account.sol";

abstract contract RouterAccountBase {
    // * Set the account only when a signature authentication is performed
    modifier setAuth(Account acc) {
        _setUnchecked(acc);
        _;
        _setUnchecked(AccountLib.ZERO_ACC);
    }

    // * Set the account without any message authentication. If an account is already set, it won't be overridden.
    // The case for an account already set is when the call runs through the AuthModule and gets delegated to the
    // TradeModule or AMMModule
    modifier setNonAuth() {
        Account old = _account();
        if (old.isZero()) _setUnchecked(AccountLib.from(msg.sender, 0));
        _;
        if (old.isZero()) _setUnchecked(AccountLib.ZERO_ACC);
    }

    function _setUnchecked(Account acc) internal {
        bytes32 slot = GeneratedStorageSlots.ROUTER_ACCOUNT_SLOT;
        assembly {
            tstore(slot, acc)
        }
    }

    function _account() internal view returns (Account res) {
        bytes32 slot = GeneratedStorageSlots.ROUTER_ACCOUNT_SLOT;
        assembly {
            res := tload(slot)
        }
    }
}
