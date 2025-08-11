// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// OpenZeppelin
import {SlotDerivation} from "@openzeppelin/contracts/utils/SlotDerivation.sol";
import {TransientSlot} from "@openzeppelin/contracts/utils/TransientSlot.sol";

// Types
import {OrderId} from "./Order.sol";

type OrderIdBoolMapping is bytes32;

using TransientOrderIdMapping for OrderIdBoolMapping global;

library TransientOrderIdMapping {
    using TransientSlot for *;
    using SlotDerivation for bytes32;

    function set(OrderIdBoolMapping slot, OrderId id, bool value) internal {
        slot.asBytes32().deriveMapping(OrderId.unwrap(id)).asBoolean().tstore(value);
    }

    function get(OrderIdBoolMapping slot, OrderId id) internal view returns (bool) {
        return slot.asBytes32().deriveMapping(OrderId.unwrap(id)).asBoolean().tload();
    }

    function asBytes32(OrderIdBoolMapping slot) internal pure returns (bytes32) {
        return OrderIdBoolMapping.unwrap(slot);
    }
}
