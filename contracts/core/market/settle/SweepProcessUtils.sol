// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

// Libraries
import {ArrayLib, LowLevelArrayLib} from "../../../lib/ArrayLib.sol";
import {PRNG} from "../../../lib/PRNGLib.sol";
import {PMath} from "../../../lib/math/PMath.sol";

// Types
import {FTag, FTagLib, PayFee, PartialData, SweptF} from "../../../types/MarketTypes.sol";
import {OrderId, OrderIdArrayLib, OrderIdLib} from "../../../types/Order.sol";

// Core
import {ProcessMergeUtils} from "./ProcessMergeUtils.sol";

// Components
import {LibOrderIdSort, OrderIdEntry} from "./LibOrderIdSort.sol";
import {OrderBookUtils} from "../orderbook/OrderBookUtils.sol";

abstract contract SweepProcessUtils is OrderBookUtils, ProcessMergeUtils {
    using PMath for uint256;
    using ArrayLib for SweptF[];
    using LowLevelArrayLib for SweptF[];
    using LibOrderIdSort for *;
    using OrderIdArrayLib for OrderId[];

    function _sweepProcess(
        UserMem memory user,
        PartialData memory part,
        MarketMem memory market
    ) internal returns (PayFee) {
        SweptF[] memory longSweptF = __sweepFOneSide(user.longIds, market);
        SweptF[] memory shortSweptF = __sweepFOneSide(user.shortIds, market);

        return _processF(user, part, market, longSweptF, shortSweptF);
    }

    function __sweepFOneSide(
        OrderId[] memory ids,
        MarketMem memory market
    ) internal view returns (SweptF[] memory sweptF) {
        if (ids.length == 0) return (sweptF);

        uint256 bestPos = ids.length.dec();
        if (!_bookCanSettleSkipSizeCheck(ids[bestPos])) return sweptF;

        (ids[0], ids[bestPos]) = (ids[bestPos], ids[0]);
        sweptF = LowLevelArrayLib.allocSweptFArrayNoInit(ids.length);
        sweptF[0] = _bookGetSettleInfo(ids[0], market.k_tickStep, FTagLib.ZERO);

        PRNG memory prng;
        prng.seed(block.number);

        OrderIdEntry[] memory arr = LibOrderIdSort.makeTempArray(ids);
        uint256 partitionPos = __findBoundAndSortSettled(arr, sweptF, market.k_tickStep, prng, market.latestFTag);

        sweptF.setShorterLength(partitionPos);
        sweptF.reverse(0, partitionPos - 1);
        for (uint256 i = 0; i < partitionPos; ++i) ids[arr[i].index()] = OrderIdLib.ZERO;
        ids.removeZeroesAndUpdateBestSameSide();
    }

    // Pre-condition: `out[0]` is set, and it's the one with the lowest fTag.
    /// What this and batchGetSettleInfo achieve: We guarantee the SweptF array is sorted in the order of fTag.
    /// If the two orders have the same fTag, we don't guarantee any orders (nor that it matters).
    /// Algorithm: at each turn, we randomly partition the array. Say segment [L,R) is partitioned at P. Now [L,P] will need to
    /// have its fTag set. We know that all elements in [L,P] have an fTag of at least the element at [L-1] and at most [P+1].
    /// So we check if the fTag of [L-1] == [P+1]; then all elements in [L,P] have the fTag of [L-1]. If this is not the case,
    /// we continue partitioning.
    /// Note that the invariant of [L,R) has tags of at least [L-1] and at most [R] is maintained at all times by the
    /// way we partition. Say for current segment [L,R) the invariant is correct, we will prove it holds for [P+1,R)
    /// Obviously OrderId of all elements in [P+1,R) is greater than [P] (due to partition), then its fTag must be at least
    /// that of [P] too. On fTag being at most [R], this still holds as all elements in [L,R) already has fTag of at most [R]
    function __findBoundAndSortSettled(
        OrderIdEntry[] memory entries,
        SweptF[] memory out,
        uint8 tickStep,
        PRNG memory prng,
        FTag latestFTag
    ) private view returns (uint256 /* bound */) {
        uint256 low = 1;
        uint256 high = entries.length;

        // Loop invariants:
        // - `out[low - 1]` is set.
        // - `high` is `entries.length` or `out[high]` is unset.
        while (low < high) {
            uint256 partPos = entries.randomPartition(low, high, prng);
            OrderId thisId = entries[partPos].id();

            if (_bookCanSettleSkipSizeCheck(thisId)) {
                __batchGetSettleInfo(entries, out, tickStep, prng, low, partPos.inc(), latestFTag);
                low = partPos.inc();
            } else {
                high = partPos;
            }
        }
        return low;
    }

    /// Since `high` can be `out.length`, `highFTag` is passed as a parameter.
    /// Recursion invariants:
    /// - `out[low - 1]` is set.
    /// - `high` is `entries.length` or `out[high]` is unset.
    function __batchGetSettleInfo(
        OrderIdEntry[] memory entries,
        SweptF[] memory out,
        uint8 tickStep,
        PRNG memory prng,
        uint256 low,
        uint256 high,
        FTag highFTag
    ) private view {
        if (low >= high) return;
        if (out[low.dec()].fTag == highFTag) {
            for (uint256 i = low; i < high; ++i) {
                out[i] = _bookGetSettleInfo(entries[i].id(), tickStep, highFTag);
            }
            return;
        }
        uint256 mid = entries.randomPartition(low, high, prng);
        out[mid] = _bookGetSettleInfo(entries[mid].id(), tickStep, FTagLib.ZERO);

        __batchGetSettleInfo(entries, out, tickStep, prng, low, mid, out[mid].fTag);
        __batchGetSettleInfo(entries, out, tickStep, prng, mid.inc(), high, highFTag);
    }
}
