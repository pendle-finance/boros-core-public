// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

// Types
import {OrderId} from "../../../types/Order.sol";

// Libraries
import {LowLevelArrayLib} from "../../../lib/ArrayLib.sol";
import {PRNG} from "../../../lib/PRNGLib.sol";

type OrderIdEntry is uint256;

using {_eq as ==, _lt as <, _gt as >} for OrderIdEntry global;

function _eq(OrderIdEntry u, OrderIdEntry v) pure returns (bool) {
    return OrderIdEntry.unwrap(u) == OrderIdEntry.unwrap(v);
}
function _lt(OrderIdEntry u, OrderIdEntry v) pure returns (bool) {
    return OrderIdEntry.unwrap(u) < OrderIdEntry.unwrap(v);
}
function _gt(OrderIdEntry u, OrderIdEntry v) pure returns (bool) {
    return OrderIdEntry.unwrap(u) > OrderIdEntry.unwrap(v);
}
using OrderIdEntryLib for OrderIdEntry global;

library OrderIdEntryLib {
    function from(OrderId _id, uint256 _index) internal pure returns (OrderIdEntry) {
        uint256 packed = 0;
        packed = OrderId.unwrap(_id);
        packed = (packed << 128) | _index;
        return OrderIdEntry.wrap(packed);
    }

    function id(OrderIdEntry entry) internal pure returns (OrderId) {
        uint256 packed = OrderIdEntry.unwrap(entry);
        return OrderId.wrap(uint64(packed >> 128));
    }

    function index(OrderIdEntry entry) internal pure returns (uint256) {
        uint256 packed = OrderIdEntry.unwrap(entry);
        return uint128(packed);
    }
}

library LibOrderIdSort {
    using LibOrderIdSort for *;

    function makeTempArray(OrderId[] memory ids) internal pure returns (OrderIdEntry[] memory arr) {
        unchecked {
            uint256 n = ids.length;
            arr = _allocOrderIdEntryArrayNoInit(n);
            for (uint256 i = 0; i < n; ++i) {
                arr._set(i, OrderIdEntryLib.from(ids[i], i));
            }
        }
    }

    function _allocOrderIdEntryArrayNoInit(uint256 n) internal pure returns (OrderIdEntry[] memory arr) {
        bytes32[] memory temp = LowLevelArrayLib._allocArrayNoInit(n);
        assembly ("memory-safe") {
            arr := temp
        }
    }

    function randomPivot(
        OrderIdEntry[] memory arr,
        uint256 low,
        uint256 high,
        PRNG memory prng
    ) internal pure returns (uint256 /*pivotPos*/) {
        unchecked {
            uint256 n = high - low;
            if (n == 1) return low;

            if (n == 2) return low + (prng.next() % 2);

            // randPos is in [low + 1, high - 1)
            uint256 randPos = (prng.next() % (n - 2)) + low + 1;
            OrderIdEntry a = arr._get(low);
            OrderIdEntry b = arr._get(randPos);
            OrderIdEntry c = arr._get(high - 1);
            (a, b, c) = _networkSort(a, b, c);
            arr._set(low, a);
            arr._set(randPos, b);
            arr._set(high - 1, c);

            return randPos;
        }
    }

    function randomPartition(
        OrderIdEntry[] memory arr,
        uint256 low,
        uint256 high,
        PRNG memory prng
    ) internal pure returns (uint256 /*partPos*/) {
        unchecked {
            uint256 n = high - low;
            if (n == 1) return (low);

            uint256 pivotPos = randomPivot(arr, low, high, prng);
            return partition(arr, low, high, pivotPos);
        }
    }

    function partition(
        OrderIdEntry[] memory arr,
        uint256 low,
        uint256 high,
        uint256 pivotPos
    ) internal pure returns (uint256 /*partPos*/) {
        unchecked {
            // require(low <= pivotPos && pivotPos < high && high <= arr.length);

            uint256 n = high - low;
            if (n == 1) return low;

            OrderIdEntry pivot = arr._get(pivotPos);

            arr._set(pivotPos, arr._get(low));
            uint256 l = low;
            uint256 r = high;

            while (true) {
                do ++l; while (l < high && arr._get(l) < pivot);
                do --r; while (r > low && arr._get(r) > pivot);
                if (l >= r) break;
                arr._swap(l, r);
            }

            arr._set(low, arr._get(r));
            arr._set(r, pivot);

            return r;
        }
    }

    function _networkSort(
        OrderIdEntry a,
        OrderIdEntry b,
        OrderIdEntry c
    ) internal pure returns (OrderIdEntry, OrderIdEntry, OrderIdEntry) {
        if (b < a) (a, b) = (b, a);
        if (c < a) (a, c) = (c, a);
        if (c < b) (b, c) = (c, b);
        return (a, b, c);
    }

    function _get(OrderIdEntry[] memory arr, uint256 index) internal pure returns (OrderIdEntry res) {
        assembly ("memory-safe") {
            res := mload(add(arr, add(0x20, mul(index, 0x20))))
        }
    }

    function _set(OrderIdEntry[] memory arr, uint256 index, OrderIdEntry val) internal pure {
        assembly ("memory-safe") {
            mstore(add(arr, add(0x20, mul(index, 0x20))), val)
        }
    }

    function _swap(OrderIdEntry[] memory arr, uint256 a, uint256 b) internal pure {
        OrderIdEntry tmp = _get(arr, a);
        _set(arr, a, _get(arr, b));
        _set(arr, b, tmp);
    }
}
