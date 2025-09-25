// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {OrderId} from "../types/Order.sol";
import {SweptF, MarketId} from "../types/MarketTypes.sol";

library ArrayLib {
    // @dev Returns the index of the first element that is equal to `id`.
    // @dev Returns `arr.length` if no element is equal to `id`.
    function find(MarketId[] memory arr, MarketId id) internal pure returns (uint256) {
        uint256 i = 0;
        for (; i < arr.length; i++) {
            if (arr[i] == id) break;
        }
        return i;
    }

    function include(MarketId[] memory arr, MarketId id) internal pure returns (bool) {
        for (uint256 i = 0; i < arr.length; i++) {
            if (arr[i] == id) return true;
        }
        return false;
    }

    // @dev This function assumes `arr` does not have duplicate elements.
    function remove(MarketId[] memory arr, MarketId id) internal pure returns (bool) {
        for (uint256 i = 0; i < arr.length; i++) {
            if (arr[i] == id) {
                arr[i] = arr[arr.length - 1];
                LowLevelArrayLib.setShorterLength(arr, arr.length - 1);
                return true;
            }
        }
        return false;
    }

    function reverse(SweptF[] memory arr, uint256 l, uint256 r) internal pure {
        unchecked {
            for (; l < r; (l, r) = (l + 1, r - 1)) {
                (arr[l], arr[r]) = (arr[r], arr[l]);
            }
        }
    }

    function sum(uint256[] memory arr) internal pure returns (uint256 res) {
        for (uint256 i = 0; i < arr.length; i++) res += arr[i];
    }

    function sum(uint256[] memory arr, uint256 start, uint256 end) internal pure returns (uint256 res) {
        for (uint256 i = start; i < end; i++) res += arr[i];
    }

    function extend(OrderId[] memory u, uint256 n) internal pure returns (OrderId[] memory res) {
        res = LowLevelArrayLib.allocOrderIdArrayNoInit(u.length + n);

        assembly ("memory-safe") {
            let uSize := mul(mload(u), 0x20)

            let dest := add(res, 0x20)
            mcopy(dest, add(u, 0x20), uSize)
        }
    }

    function concat(OrderId[] memory u, OrderId[] memory v) internal pure returns (OrderId[] memory res) {
        res = LowLevelArrayLib.allocOrderIdArrayNoInit(u.length + v.length);

        assembly ("memory-safe") {
            let uSize := mul(mload(u), 0x20)
            let vSize := mul(mload(v), 0x20)

            let dest := add(res, 0x20)
            mcopy(dest, add(u, 0x20), uSize)

            dest := add(dest, uSize)
            mcopy(dest, add(v, 0x20), vSize)
        }
    }
}

library LowLevelArrayLib {
    function sliceFromTemp(
        OrderId[] memory orig,
        uint256 from
    ) internal pure returns (OrderId[] memory res, bytes32 borrow) {
        uint256 sliceLen = orig.length - from;

        assembly ("memory-safe") {
            res := add(orig, mul(from, 0x20))
            borrow := mload(res)
            mstore(res, sliceLen)
        }
    }

    function restoreSlice(OrderId[] memory _slice, bytes32 borrow) internal pure {
        assembly ("memory-safe") {
            mstore(_slice, borrow)
        }
    }

    function setShorterLength(uint256[] memory arr, uint256 newLength) internal pure {
        assembly ("memory-safe") {
            mstore(arr, newLength)
        }
    }

    function setShorterLength(MarketId[] memory arr, uint256 newLength) internal pure {
        assembly ("memory-safe") {
            mstore(arr, newLength)
        }
    }

    function setShorterLength(OrderId[] memory arr, uint256 newLength) internal pure {
        assembly ("memory-safe") {
            mstore(arr, newLength)
        }
    }

    function setShorterLength(SweptF[] memory arr, uint256 newLength) internal pure {
        assembly ("memory-safe") {
            mstore(arr, newLength)
        }
    }

    function setShorterLength(int16[] memory arr, uint256 newLength) internal pure {
        assembly ("memory-safe") {
            mstore(arr, newLength)
        }
    }

    function allocOrderIdArrayNoInit(uint256 len) internal pure returns (OrderId[] memory res) {
        bytes32[] memory temp = _allocArrayNoInit(len);
        assembly ("memory-safe") {
            res := temp
        }
    }

    function allocSweptFArrayNoInit(uint256 len) internal pure returns (SweptF[] memory res) {
        bytes32[] memory temp = _allocArrayNoInit(len);
        assembly ("memory-safe") {
            res := temp
        }
    }

    function _allocArrayNoInit(uint256 len) internal pure returns (bytes32[] memory res) {
        assembly ("memory-safe") {
            res := mload(0x40)
            mstore(res, len)
            mstore(0x40, add(res, add(mul(len, 0x20), 0x20)))
        }
    }
}
