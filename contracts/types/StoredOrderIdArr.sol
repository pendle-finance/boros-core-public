// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

// Types
import {OrderId, Side} from "./Order.sol";

// OpenZeppelin
import {StorageSlot} from "@openzeppelin/contracts/utils/StorageSlot.sol";
import {SlotDerivation} from "@openzeppelin/contracts/utils/SlotDerivation.sol";

struct StoredOrderIdArr {
    uint256 __DUMMY__;
}

using StoredOrderIdArrLib for StoredOrderIdArr global;

library StoredOrderIdArrLib {
    using StorageSlot for bytes32;
    using SlotDerivation for bytes32;

    uint256 internal constant GROUP_SIZE = 4;

    function read(
        StoredOrderIdArr storage arr,
        uint16 longLen,
        uint16 shortLen
    ) internal view returns (OrderId[] memory longIds, OrderId[] memory shortIds) {
        unchecked {
            if (longLen != 0) {
                longIds = new OrderId[](longLen);
                _read(__arrBeginSlot(arr, Side.LONG), longLen, longIds);
            }

            if (shortLen != 0) {
                shortIds = new OrderId[](shortLen);
                _read(__arrBeginSlot(arr, Side.SHORT), shortLen, shortIds);
            }
        }
    }

    function readLast(StoredOrderIdArr storage arr, Side side, uint16 len) internal view returns (OrderId last) {
        return _readSingle(__arrBeginSlot(arr, side), len - 1);
    }

    function write(StoredOrderIdArr storage arr, OrderId[] memory longIds, OrderId[] memory shortIds) internal {
        unchecked {
            assert(longIds.length <= type(uint16).max && shortIds.length <= type(uint16).max);

            if (longIds.length > 0) _write(__arrBeginSlot(arr, Side.LONG), longIds.length, longIds);
            if (shortIds.length > 0) _write(__arrBeginSlot(arr, Side.SHORT), shortIds.length, shortIds);
        }
    }

    function _readSingle(bytes32 slotPos, uint256 i) internal view returns (OrderId) {
        unchecked {
            uint256 group = i / GROUP_SIZE;
            uint256 offset = i % GROUP_SIZE;
            uint256 curWord = slotPos.offset(group).getUint256Slot().value;
            return OrderId.wrap(uint64(curWord >> (offset * 64)));
        }
    }

    function _read(bytes32 slotPos, uint256 len, OrderId[] memory dest) internal view {
        unchecked {
            uint256 curWord = 0;
            for (uint256 i = 0; i < len; i++) {
                if (i % GROUP_SIZE == 0) {
                    curWord = slotPos.getUint256Slot().value;
                    slotPos = __nextSlot(slotPos);
                }
                dest[i] = OrderId.wrap(uint64(curWord));
                curWord >>= 64;
            }
        }
    }

    function _write(bytes32 slotPos, uint256 len, OrderId[] memory src) internal {
        unchecked {
            slotPos = slotPos.offset((len + GROUP_SIZE - 1) / GROUP_SIZE);

            uint256 curWord = 0;
            for (uint256 i = len; i > 0; ) {
                i--;
                curWord = (curWord << 64) | OrderId.unwrap(src[i]);
                if (i % GROUP_SIZE == 0) {
                    slotPos = __prevSlot(slotPos);
                    slotPos.getUint256Slot().value = curWord;
                }
            }
        }
    }

    function __arrBeginSlot(StoredOrderIdArr storage arr, Side side) private pure returns (bytes32 _slot) {
        assembly {
            _slot := arr.slot
        }
        return _slot.deriveMapping(uint256(side));
    }

    function __nextSlot(bytes32 _slot) internal pure returns (bytes32) {
        unchecked {
            return bytes32(uint256(_slot) + 1);
        }
    }

    function __prevSlot(bytes32 _slot) internal pure returns (bytes32) {
        unchecked {
            return bytes32(uint256(_slot) - 1);
        }
    }
}
