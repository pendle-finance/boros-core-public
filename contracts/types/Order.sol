// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {LowLevelArrayLib} from "../lib/ArrayLib.sol";
import {PMath} from "../lib/math/PMath.sol";

enum TimeInForce {
    GTC,
    IOC,
    FOK,
    ALO,
    SOFT_ALO
}

enum OrderStatus {
    NOT_EXIST,
    OPEN,
    PENDING_SETTLE,
    PURGED
}

type OrderId is uint64;

enum Side {
    LONG,
    SHORT
}

using TimeInForceLib for TimeInForce global;

using SideLib for Side global;

using OrderIdLib for OrderId global;
using {_ltOrderId as <} for OrderId global;

/// @notice See notes in OrderIdLib for the encoding details.
function _ltOrderId(OrderId u, OrderId v) pure returns (bool) {
    return OrderId.unwrap(u) < OrderId.unwrap(v);
}

library TimeInForceLib {
    function isALO(TimeInForce tif) internal pure returns (bool) {
        return tif == TimeInForce.ALO || tif == TimeInForce.SOFT_ALO;
    }

    function shouldSkipMatchableOrders(TimeInForce tif) internal pure returns (bool) {
        return tif == TimeInForce.SOFT_ALO;
    }
}

library SideLib {
    function opposite(Side side) internal pure returns (Side) {
        return side == Side.LONG ? Side.SHORT : Side.LONG;
    }

    function sweepTickTopDown(Side side) internal pure returns (bool) {
        return side == Side.LONG;
    }

    function endTick(Side side) internal pure returns (int16) {
        return side == Side.LONG ? type(int16).min : type(int16).max;
    }

    function possibleToBeFilled(Side side, int16 orderTick, int16 lastTickFilled) internal pure returns (bool) {
        return side.sweepTickTopDown() ? lastTickFilled <= orderTick : lastTickFilled >= orderTick;
    }

    /// Special tick value for IMarket.getNextNTicks()
    function tickToGetFirstAvail(Side side) internal pure returns (int16) {
        // return the stopTick, because per wrap-around logic, stopTick is the tick before the very first possible tick.
        return endTick(side);
    }

    function canMatch(Side side, int16 limitTick, int16 bestTick) internal pure returns (bool) {
        return side.sweepTickTopDown() ? limitTick <= bestTick : limitTick >= bestTick;
    }

    function toSignedSize(uint256 size, Side side) internal pure returns (int256) {
        return side == Side.LONG ? PMath.Int(size) : PMath.neg(size);
    }

    function isOfSide(int256 size, Side side) internal pure returns (bool) {
        return (size > 0 && side == Side.LONG) || (size < 0 && side == Side.SHORT);
    }

    function checkRateInBound(Side side, int256 rate, int256 bound) internal pure returns (bool) {
        if (side == Side.LONG) return rate <= bound;
        else return rate >= bound;
    }
}

/// @dev OrderId's **unwrapped** value is mapped onto the number line such that
/// an order with lower **unwrapped** value has higher priority in the order book.
///
/// This structure ensures the following property:
/// - For a list of sorted orders id **of the same side**, if there are any
///   orders that need to be settled, all of them would have ids that lie at the
///   beginning of the list, starting from the one with the highest priority.
library OrderIdLib {
    OrderId internal constant ZERO = OrderId.wrap(0);
    uint64 internal constant INITIALIZED_MARKER = 1 << 63;

    function from(Side _side, int16 _tickIndex, uint40 _orderIndex) internal pure returns (OrderId) {
        uint16 encodedTickIndex = _encodeTickIndex(_tickIndex, _side);

        uint64 packed = 0;
        packed = uint64(_side);
        packed = (packed << 16) | encodedTickIndex;
        packed = (packed << 40) | _orderIndex;
        packed |= INITIALIZED_MARKER;
        return OrderId.wrap(packed);
    }

    function unpack(OrderId orderId) internal pure returns (Side _side, int16 _tickIndex, uint40 _orderIndex) {
        uint16 encodedTickIndex;

        uint64 packed = OrderId.unwrap(orderId);

        _orderIndex = uint40(packed);
        packed >>= 40;

        encodedTickIndex = uint16(packed);
        packed >>= 16;

        _side = Side(packed & 1);

        _tickIndex = _decodeTickIndex(encodedTickIndex, _side);
    }

    function isZero(OrderId orderId) internal pure returns (bool) {
        return OrderId.unwrap(orderId) == 0;
    }

    function orderIndex(OrderId orderId) internal pure returns (uint40 _orderIndex) {
        return uint40(OrderId.unwrap(orderId));
    }

    function tickIndex(OrderId orderId) internal pure returns (int16 _tickIndex) {
        uint16 encodedTickIndex = uint16(OrderId.unwrap(orderId) >> 40);
        return _decodeTickIndex(encodedTickIndex, side(orderId));
    }

    function side(OrderId orderId) internal pure returns (Side _side) {
        return Side((OrderId.unwrap(orderId) >> 56) & 1);
    }

    function _encodeTickIndex(int16 _tickIndex, Side _side) internal pure returns (uint16 encoded) {
        encoded = uint16(_tickIndex) ^ (1 << 15);
        if (_side.sweepTickTopDown()) encoded = ~encoded;
    }

    function _decodeTickIndex(uint16 encoded, Side _side) internal pure returns (int16 _tickIndex) {
        if (_side.sweepTickTopDown()) encoded = ~encoded;
        return int16(encoded ^ (1 << 15));
    }
}

library OrderIdArrayLib {
    using LowLevelArrayLib for OrderId[];

    function removeZeroesAndUpdateBestSameSide(OrderId[] memory ids) internal pure {
        uint256 len = ids.length;
        if (len == 0) return;

        for (uint256 i = 0; i < len; ++i) {
            while (i < len && ids[i].isZero()) ids[i] = ids[--len];
        }
        ids.setShorterLength(len);

        updateBestSameSide(ids, 0);
    }

    function updateBestSameSide(OrderId[] memory ids, uint256 preLen) internal pure {
        unchecked {
            uint256 len = ids.length;
            if (len == 0) return;

            uint256 bestPos;
            OrderId bestId;
            if (preLen > 0) {
                bestId = ids[preLen - 1];
                bestPos = preLen - 1;
            }

            for (uint256 i = preLen; i < len; ++i) {
                OrderId curId = ids[i];
                if (bestId.isZero() || curId < bestId) (bestPos, bestId) = (i, curId);
            }

            (ids[bestPos], ids[len - 1]) = (ids[len - 1], ids[bestPos]);
        }
    }
}
