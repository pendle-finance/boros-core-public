// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {OrderStatus} from "../../../types/Order.sol";
import {PMath} from "../../../lib/math/PMath.sol";
import {
    MatchEvent,
    MatchEventLib,
    TickNonceData,
    TickNonceDataLib,
    NodeData,
    NodeDataLib,
    TickInfo,
    TickInfoLib,
    FTag
} from "../../../types/MarketTypes.sol";
import {Err} from "../../../lib/Errors.sol";

struct TickMatchResult {
    uint128 partialSize;
    uint40 partialMakerNonce;
    uint40 beginFullyFilledOrderIndex;
    uint40 endFullyFilledOrderIndex;
}

struct Tick {
    TickInfo info;
    mapping(uint40 nodeId => NodeData) node;
    // Sum of orderSize of all descendants, EXCLUDING itself
    // Underlying, we store the value as uint128, but we use uint256 instead to avoid additional read when writing.
    // Make sure that the value fit in uint128 before writing!
    mapping(uint40 nodeId => uint256) subtreeSum;
    MatchEvent[] matchEvents;
    mapping(uint40 tickNonce => TickNonceData) tickNonceData;
}

using TickLib for Tick global;

library TickLib {
    using FenwickNodeMath for *;
    using PMath for uint256;

    function insertOrder(
        Tick storage $,
        uint128 size,
        uint40 makerNonce
    ) internal returns (uint40 orderIndex, uint128 oldTickSum) {
        (uint128 tickSum, uint40 headIndex, uint40 tailIndex, uint40 tickNonce, uint40 activeTickNonce) = $.info.read();

        (orderIndex, oldTickSum) = (tailIndex, tickSum);

        uint40 nodeId = orderIndex;
        uint256 subtreeSum = 0;
        unchecked {
            uint40 jump = 1;
            uint40 capIndex = nodeId + 1 - nodeId.coverLength();
            if (capIndex < headIndex) capIndex = headIndex;

            while (nodeId >= jump && nodeId - jump >= capIndex) {
                nodeId -= jump;
                (uint256 nodeSum, ) = _getNodeSum($, nodeId);
                subtreeSum += nodeSum;
                jump = nodeId.coverLength();
            }
        }

        tickSum += size;
        tailIndex++;

        $.node[orderIndex] = NodeDataLib.from(size, makerNonce, tickNonce, activeTickNonce);
        if (subtreeSum != 0) $.subtreeSum[orderIndex] = subtreeSum.Uint128();

        TickInfoLib.write($.info, tickSum, headIndex, tailIndex, tickNonce, activeTickNonce);
    }

    /// @return removedSize = 0 when the order is not OPEN.
    function tryRemove(
        Tick storage $,
        uint40 orderIndex,
        bool isStrict
    ) internal returns (uint128 /*removedSize*/, uint128 /*newTickSum*/) {
        (uint128 tickSum, uint40 headIndex, uint40 tailIndex, uint40 tickNonce, uint40 activeTickNonce) = $.info.read();

        require(orderIndex < tailIndex, Err.MarketOrderNotFound());

        uint128 removedSize = $.node[orderIndex].orderSize();
        if (isStrict) {
            require(removedSize != 0, Err.MarketOrderCancelled());
            require(headIndex <= orderIndex, Err.MarketOrderFilled());
        } else if (removedSize == 0 || orderIndex < headIndex) {
            return (0, tickSum);
        }

        unchecked {
            uint40 child = orderIndex;
            uint40 par = child.parent();
            for (; child != par && par < tailIndex; (child, par) = (par, par.parent())) {
                $.subtreeSum[par] -= removedSize;
            }

            tickSum -= removedSize;
        }

        $.node[orderIndex] = NodeDataLib.ZERO;
        TickInfoLib.write($.info, tickSum, headIndex, tailIndex, tickNonce, activeTickNonce);

        return (removedSize, tickSum);
    }

    function matchAllFillResult(Tick storage $, FTag fTag, TickMatchResult memory res) internal {
        (, uint40 headIndex, uint40 tailIndex, uint40 tickNonce, uint40 activeTickNonce) = $.info.read();

        activeTickNonce = _pushNewMatchEvent($, tickNonce, activeTickNonce, headIndex, fTag);

        res.partialSize = 0;
        res.partialMakerNonce = 0;
        res.beginFullyFilledOrderIndex = headIndex;
        res.endFullyFilledOrderIndex = tailIndex;

        unchecked {
            tickNonce++;
        }
        TickInfoLib.write($.info, 0, tailIndex, tailIndex, tickNonce, activeTickNonce);
    }

    function matchPartialFillResult(
        Tick storage $,
        uint128 toMatchSize,
        FTag fTag,
        TickMatchResult memory res
    ) internal {
        (uint128 tickSum, uint40 headIndex, uint40 tailIndex, uint40 tickNonce, uint40 activeTickNonce) = $.info.read();

        activeTickNonce = _pushNewMatchEvent($, tickNonce, activeTickNonce, headIndex, fTag);

        uint40 newHeadIndex;

        (newHeadIndex, res.partialSize, res.partialMakerNonce) = __matchPartialInner(
            $,
            headIndex,
            tailIndex,
            toMatchSize
        );

        res.beginFullyFilledOrderIndex = headIndex;
        res.endFullyFilledOrderIndex = newHeadIndex;

        TickInfoLib.write($.info, tickSum - toMatchSize, newHeadIndex, tailIndex, tickNonce, activeTickNonce);
    }

    function __matchPartialInner(
        Tick storage $,
        uint40 headIndex,
        uint40 tailIndex,
        uint256 remaining
    ) private returns (uint40, /* newHeadIndex */ uint128, /* partialSize */ uint40 /* partialMakerNonce */) {
        unchecked {
            for (
                uint40 coverLen = FenwickNodeMath.MAX_COVER_LENGTH;
                coverLen > 0;
                coverLen /= FenwickNodeMath.SIZE_LEVEL
            ) {
                for (
                    uint40 nodeId = headIndex.ancestorCovering(coverLen);
                    nodeId < tailIndex && nodeId.coverLength() == coverLen;
                    // The following addition can be proven to not exceed type(uint40).max
                    // Indeed, type(uint40).max has maximum possible coverLen, hence it is the root of the last tree.
                    // So it must be the final jumping point.
                    nodeId += coverLen
                ) {
                    (uint256 sum, uint128 subtreeSum) = _getNodeSum($, nodeId);
                    if (sum <= remaining) {
                        remaining -= sum;
                        headIndex = nodeId + 1;
                        continue;
                    }

                    if (remaining < subtreeSum) {
                        $.subtreeSum[nodeId] = subtreeSum - remaining;
                        break; // break inner loop, continue outer loop
                    }

                    uint40 newHeadIndex = nodeId;
                    uint128 partialSize = (remaining - subtreeSum).Uint128();

                    NodeData oldNode = $.node[nodeId];
                    uint40 partialMakerNonce = oldNode.makerNonce();

                    // The case subtreeSum == 0 is common, especially for leaf node (which is 75% of the nodes).
                    if (subtreeSum > 0) $.subtreeSum[nodeId] = 0;
                    $.node[nodeId] = oldNode.decOrderSize(partialSize);
                    return (newHeadIndex, partialSize, partialMakerNonce);
                }
            }
            return (headIndex, 0, 0);
        }
    }

    function _pushNewMatchEvent(
        Tick storage $,
        uint40 curTickNonce,
        uint40 activeTickNonce,
        uint40 headIndex,
        FTag fTag
    ) private returns (uint40 /*newActiveTickNonce*/) {
        TickNonceData refData = $.tickNonceData[activeTickNonce];
        MatchEvent refEvent = refData.lastEvent();
        if (refEvent.fTag() == fTag) return activeTickNonce;

        uint40 newEventId = $.matchEvents.length.Uint40();
        MatchEvent newEvent = MatchEventLib.from(headIndex, fTag);
        $.matchEvents.push(newEvent);

        TickNonceData curData = $.tickNonceData[curTickNonce];
        uint40 firstEventId = !curData.isZero() ? curData.firstEventId() : refData.lastEventId();
        uint40 lastEventId = newEventId;
        $.tickNonceData[curTickNonce] = TickNonceDataLib.from(newEvent, firstEventId, lastEventId, type(uint40).max);

        if (curTickNonce != activeTickNonce)
            $.tickNonceData[activeTickNonce] = refData.replaceNextActiveNonce(curTickNonce);

        return curTickNonce;
    }

    /// @dev Only non-leaf node has positive subtreeSum, which is only 25% of the total nodes.
    function _getNodeSum(Tick storage $, uint40 nodeId) private view returns (uint256 nodeSum, uint128 subtreeSum) {
        nodeSum = $.node[nodeId].orderSize();
        if (!nodeId.isLeaf()) {
            subtreeSum = uint128($.subtreeSum[nodeId]);
            unchecked {
                nodeSum += subtreeSum;
            }
        }
    }

    function getTickSum(Tick storage $) internal view returns (uint128) {
        return $.info.tickSum();
    }

    /// @dev Pre-condition: the order should have positive size (not cancelled).
    function canSettleSkipSizeCheck(Tick storage $, uint40 orderIndex) internal view returns (bool) {
        return orderIndex < $.info.headIndex();
    }

    /// @dev Pre-condition: the order is SETTLED.
    /// @dev To check if the order is not OPEN, call `canSettleSkipSizeCheck`.
    /// @dev To check if the order is not CANCELLED, check its size.
    function getSettleSize(Tick storage $, uint40 orderIndex) internal view returns (uint128) {
        return $.node[orderIndex].orderSize();
    }

    /// @dev Pre-condition: the order is SETTLED.
    /// @dev To check if the order is not OPEN, call `canSettleSkipSizeCheck`.
    /// @dev To check if the order is not CANCELLED, check its size.
    /// @dev return (0, FTagLib.ZERO) for order that is still OPEN.
    function getSettleSizeAndFTag(
        Tick storage $,
        uint40 orderIndex
    ) internal view returns (uint128 /*settledSize*/, FTag) {
        NodeData node = $.node[orderIndex];
        return (node.orderSize(), _getFTag($, orderIndex, node));
    }

    function _getFTag(Tick storage $, uint40 orderId, NodeData nodeData) internal view returns (FTag) {
        return _getFTag($, orderId, nodeData.tickNonce(), nodeData.refTickNonce());
    }

    function _getFTag(
        Tick storage $,
        uint40 orderId,
        uint40 tickNonce,
        uint40 refTickNonce
    ) private view returns (FTag res) {
        if (refTickNonce != tickNonce) {
            TickNonceData refData = $.tickNonceData[refTickNonce];
            if (refData.nextActiveNonce() > tickNonce) return refData.lastEvent().fTag();
        }

        TickNonceData data = $.tickNonceData[tickNonce];
        {
            MatchEvent matchEvent = data.lastEvent();
            if (matchEvent.headIndex() <= orderId) return matchEvent.fTag();
        }

        unchecked {
            uint256 startIndex = data.firstEventId();
            uint256 endIndex = data.lastEventId() - 1;

            while (startIndex <= endIndex) {
                uint256 mid = (startIndex + endIndex) / 2;
                MatchEvent matchEvent = $.matchEvents[mid];
                if (orderId < matchEvent.headIndex()) {
                    assert(mid != 0);
                    endIndex = mid - 1;
                } else {
                    res = matchEvent.fTag();
                    startIndex = mid + 1;
                }
            }
        }
    }

    // ------------ Only used in OffView ------------
    function getOrderStatusAndSize(
        Tick storage $,
        uint40 orderIndex
    ) internal view returns (OrderStatus status, uint256 size) {
        NodeData node = $.node[orderIndex];
        size = node.orderSize();

        if (size == 0) {
            status = OrderStatus.NOT_EXIST;
        } else if (orderIndex >= $.info.headIndex()) {
            status = OrderStatus.OPEN;
        } else {
            FTag fTag = _getFTag($, orderIndex, node);
            status = fTag.isPurge() ? OrderStatus.PURGED : OrderStatus.PENDING_SETTLE;
        }
    }

    function makerNonceOf(Tick storage $, uint40 orderIndex) internal view returns (uint40) {
        return $.node[orderIndex].makerNonce();
    }
}

// zero-base quaternary Fenwick tree math
library FenwickNodeMath {
    using FenwickNodeMath for *;

    uint40 internal constant SIZE_LEVEL = 4;
    uint40 internal constant HIGHEST_LEVEL = 9;
    uint40 internal constant MAX_COVER_LENGTH = (uint40(1) << HIGHEST_LEVEL) << HIGHEST_LEVEL;

    /// Mask that has 1s in all even bits, and 0s in all odd bits (0b0101010101...0101).
    uint256 internal constant EVEN_BIT_MASK =
        0x5555_5555_5555_5555_5555_5555_5555_5555_5555_5555_5555_5555_5555_5555_5555_5555; // = type(uint256).max / 3

    /// `coverLength(nodeId)` is min(4 ** x, MAX_COVER_LENGTH)
    /// where `x` is the number of trailing 3s of nodeId in *quaternary* representation.
    ///
    /// Here are some first values of coverLength:
    /// i               | 0, 1, 2, 3,  4,  5,  6,  7,  8,  9, 10, 11, 12, 13, 14, 15, ...
    /// quaternary(i)   | 0, 1, 2, 3, 10, 11, 12, 13, 20, 21, 22, 23, 30, 31, 32, 33, ...
    /// coverLength(i)  | 1, 1, 1, 4,  1,  1,  1,  4,  1,  1,  1,  4,  1,  1,  1, 16, ...
    ///
    /// Some other values:
    /// coverLength(63) = 64
    /// coverLength(127) = 64
    /// coverLength(191) = 64
    /// coverLength(255) = 256
    function coverLength(uint40 nodeId) internal pure returns (uint40) {
        uint256 res = rawCoverLength(nodeId);
        // cap at MAX_COVER_LENGTH so that tree height won't be too large
        if (res > MAX_COVER_LENGTH) res = MAX_COVER_LENGTH;
        return uint40(res);
    }

    // @dev This function returns 0 for `nodeId = type(uint256).max`, which is not correct.
    // However, we do not need to handle this case, because normal `nodeId` has type of `uint40`.
    function rawCoverLength(uint256 nodeId) private pure returns (uint256 res) {
        // let y be the number of trailing 1s of nodeId in **binary** (not quaternary) representation,
        // then res is (2 ** y).
        unchecked {
            res = (nodeId + 1) & ~nodeId;
        }

        // Now in quaternary representation, res can have the following forms:
        // - 1000000...000  (2 ** (2k))
        // - 2000000...000  (2 ** (2k + 1))
        // The result must be power of 4, so we need to divide by 2 for the later case.
        bool isPowerOf4 = (res & EVEN_BIT_MASK) > 0;
        if (!isPowerOf4) res >>= 1;
    }

    function isLeaf(uint40 nodeId) internal pure returns (bool) {
        return (nodeId & 3) != 3;
    }

    /// @dev return `nodeId` itself if it is tree root
    function parent(uint40 nodeId) internal pure returns (uint40) {
        uint256 coverLength_ = rawCoverLength(nodeId);
        if (coverLength_ < MAX_COVER_LENGTH) {
            unchecked {
                // In quaternary, set the last non-3 digit into 3.
                nodeId = uint40(nodeId | (coverLength_ * 3));
            }
        }
        return nodeId;
    }

    /// return ancestor `anc` of `nodeId` such that `anc.coverLength()` is at least `_coverLength`.
    /// Pre-condition: _coverLength must be a valid node coverLength. That is, it must be a power of 4.
    function ancestorCovering(uint40 nodeId, uint40 _coverLength) internal pure returns (uint40 anc) {
        unchecked {
            // bool isPowerOf4 = (_coverLength > 0 &&
            //     _coverLength & (_coverLength - 1) == 0 &&
            //     (_coverLength & (EVEN_BIT_MASK)) > 0);
            // require(isPowerOf4, "coverLength must be power of 4,");
            anc = nodeId | (_coverLength - 1);
        }
    }
}
