// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

// Generated
import {GeneratedStorageSlots} from "../../../generated/slots.sol";

// Interfaces
import {IMarketAllEventsAndTypes} from "../../../interfaces/IMarket.sol";

// Libraries
import {LowLevelArrayLib} from "../../../lib/ArrayLib.sol";
import {PMath} from "../../../lib/math/PMath.sol";
import {TickMath} from "../../../lib/math/TickMath.sol";

// Types
import {AccountLib, MarketAcc} from "../../../types/Account.sol";
import {LongShort, SweptF, FTag} from "../../../types/MarketTypes.sol";
import {OrderId, OrderIdLib, OrderStatus, Side} from "../../../types/Order.sol";
import {Trade, TradeLib, Fill, FillLib} from "../../../types/Trade.sol";

// Components
import {Tick, TickMatchResult} from "./Tick.sol";
import {TickBitmap} from "./TickBitmap.sol";

abstract contract OrderBookUtils is IMarketAllEventsAndTypes {
    using PMath for uint256;
    using LowLevelArrayLib for OrderId[];
    using LowLevelArrayLib for uint256[];
    using LowLevelArrayLib for int16[];

    struct OrderBook {
        TickBitmap tickBitmap;
        mapping(int16 => Tick) ticks;
    }

    struct OrderBookStorageStruct {
        OrderBook bookLong;
        OrderBook bookShort;
        mapping(MarketAcc => uint40) makerToNonce;
        mapping(uint40 => MarketAcc) nonceToMaker;
        uint40 countMaker;
        // empty for upgradability
    }

    function _OS() internal pure returns (OrderBookStorageStruct storage $) {
        bytes32 slot = GeneratedStorageSlots.ORDERBOOK_STORAGE_LOCATION;
        assembly {
            $.slot := slot
        }
    }

    function _bookAdd(MarketAcc maker, LongShort memory orders, OrderId[] memory orderIds, uint256 appendPos) internal {
        OrderBook storage self = _getBook(orders.side);
        uint40 makerNonce = __getOrCreateMakerNonce(maker);

        for (uint256 i = 0; i < orders.sizes.length; i++) {
            uint128 curSize128 = orders.sizes[i].Uint128();
            int16 tickIndex = orders.limitTicks[i];

            (uint40 orderIndex, uint256 oldTickSum) = self.ticks[tickIndex].insertOrder(curSize128, makerNonce);

            if (oldTickSum == 0) {
                self.tickBitmap.set(tickIndex);
            }

            unchecked {
                orderIds[appendPos + i] = OrderIdLib.from(orders.side, tickIndex, orderIndex);
            }
        }

        (OrderId[] memory addedIds, bytes32 borrow) = LowLevelArrayLib.sliceFromTemp(orderIds, appendPos);
        emit LimitOrderPlaced(maker, addedIds, orders.sizes);
        LowLevelArrayLib.restoreSlice(addedIds, borrow);
    }

    function _bookRemove(
        OrderId[] memory ids,
        bool isStrict,
        bool isForced
    ) internal returns (uint256[] memory removedSizes) {
        uint256 len = ids.length;
        if (len == 0) return removedSizes;

        uint256 removedCnt = 0;
        removedSizes = new uint256[](len);
        for (uint256 i = 0; i < len; ++i) {
            (Side side, int16 tickIndex, uint40 orderIndex) = ids[i].unpack();

            OrderBook storage self = _getBook(side);
            Tick storage tick = self.ticks[tickIndex];
            (uint256 removedSize, uint256 newTickSum) = tick.tryRemove(orderIndex, isStrict);
            if (removedSize > 0) {
                if (newTickSum == 0) {
                    self.tickBitmap.reset(tickIndex);
                }

                ids[removedCnt] = ids[i];
                removedSizes[removedCnt] = removedSize;
                removedCnt = removedCnt.inc();
            }
        }

        ids.setShorterLength(removedCnt);
        removedSizes.setShorterLength(removedCnt);

        if (removedCnt > 0) {
            if (isForced) {
                emit LimitOrderForcedCancelled(ids);
            } else {
                emit LimitOrderCancelled(ids);
            }
        }
    }

    function _bookCanSettleSkipSizeCheck(OrderId id) internal view returns (bool) {
        (Side side, int16 tickIndex, uint40 orderIndex) = id.unpack();
        Tick storage tick = _getBook(side).ticks[tickIndex];
        return tick.canSettleSkipSizeCheck(orderIndex);
    }

    /// @dev Pre-condition: the order is SETTLED.
    /// @dev `sweptF.fTag` will be retrieved from tick when the passed in `fTag == FTagLib.ZERO`.
    /// @dev `sweptF.fTag` will be `fTag` when the passed in `fTag != FTagLib.ZERO`.
    function _bookGetSettleInfo(OrderId id, uint8 tickStep, FTag fTag) internal view returns (SweptF memory sweptF) {
        (Side side, int16 tickIndex, uint40 orderIndex) = id.unpack();
        Tick storage tick = _getBook(side).ticks[tickIndex];

        uint256 settledSize = 0;
        if (fTag.isZero()) {
            (settledSize, fTag) = tick.getSettleSizeAndFTag(orderIndex);
        } else {
            settledSize = tick.getSettleSize(orderIndex);
        }

        sweptF.assign(fTag, FillLib.from3(side, settledSize, TickMath.getRateAtTick(tickIndex, tickStep)));
    }

    struct MatchAux {
        Side side;
        uint256[] sizes;
        int16[] limitTicks;
        uint8 tickStep;
        FTag latestFTag;
    }

    /// @dev sizes will become the remaining (unmatched) sizes after this function.
    /// @dev For each index i, if sizes[i] is **FULLY** matched (become zero), sizes[i] and limitTicks[i] will be removed.
    function _bookMatch(
        uint8 _tickStep,
        FTag _latestFTag,
        LongShort memory orders
    )
        internal
        returns (
            Trade totalMatched,
            Fill partialFill,
            MarketAcc partialMaker,
            int16 lastMatchedTick,
            int256 lastMatchedRate
        )
    {
        MatchAux memory $ = MatchAux({
            side: orders.side.opposite(),
            sizes: orders.sizes,
            limitTicks: orders.limitTicks,
            tickStep: _tickStep,
            latestFTag: _latestFTag
        });

        if (orders.tif.shouldSkipMatchableOrders()) {
            _removeMatchableOrders($);
            return (TradeLib.ZERO, FillLib.ZERO, AccountLib.ZERO_MARKET_ACC, 0, 0);
        }

        OrderBook storage self = _getBook($.side);
        TickMatchResult memory result;

        uint256 curOrder = 0;
        while (true) {
            (int16 curTick, bool found) = self.tickBitmap.begin($.side);
            if (!found) break;

            curOrder = __nextMatchableOrder($.side, curTick, $.limitTicks, curOrder);
            if (curOrder == $.sizes.length) break;

            uint256 matched;
            (matched, curOrder) = _processTickMatches(self, $, curOrder, curTick, result);

            lastMatchedTick = curTick;
            lastMatchedRate = TickMath.getRateAtTick(curTick, $.tickStep);
            totalMatched = totalMatched + TradeLib.from3($.side, matched, lastMatchedRate);

            if (result.beginFullyFilledOrderIndex != result.endFullyFilledOrderIndex) {
                OrderId from = OrderIdLib.from($.side, curTick, result.beginFullyFilledOrderIndex);
                OrderId to = OrderIdLib.from($.side, curTick, result.endFullyFilledOrderIndex - 1);
                emit LimitOrderFilled(from, to);
            }

            if (result.partialSize > 0) {
                // assert($.sizes[curOrder] == 0); // can be proven to be true

                partialMaker = _OS().nonceToMaker[result.partialMakerNonce];
                partialFill = FillLib.from3($.side, result.partialSize, lastMatchedRate);

                OrderId id = OrderIdLib.from($.side, curTick, result.endFullyFilledOrderIndex);
                emit LimitOrderPartiallyFilled(id, result.partialSize);
                break;
            }

            if ($.sizes[curOrder] == 0) {
                break;
            }
        }

        __removeZeroSizes($.sizes, $.limitTicks);
        totalMatched = totalMatched.opposite();
    }

    function _removeMatchableOrders(MatchAux memory $) private view {
        OrderBook storage self = _getBook($.side);
        (int16 bestTick, bool found) = self.tickBitmap.begin($.side);
        if (!found) return;

        for (uint256 i = 0; i < $.sizes.length; ++i) {
            if ($.side.canMatch($.limitTicks[i], bestTick)) {
                $.sizes[i] = 0;
            }
        }
        __removeZeroSizes($.sizes, $.limitTicks);
    }

    /// @dev Process all matches at current tick level, including accumulation and matching
    function _processTickMatches(
        OrderBook storage self,
        MatchAux memory $,
        uint256 startOrder,
        int16 curTick,
        TickMatchResult memory result
    ) private returns (uint256 matched, uint256 curOrder) {
        Tick storage tick = self.ticks[curTick];
        uint256 curTickSum = tick.getTickSum();

        curOrder = startOrder;
        // First accumulate any fully matchable orders
        while ($.sizes[curOrder] <= curTickSum) {
            uint256 nxtOrder = __nextMatchableOrder($.side, curTick, $.limitTicks, curOrder.inc());
            if (nxtOrder == $.sizes.length) break;

            $.sizes[nxtOrder] += $.sizes[curOrder];
            $.sizes[curOrder] = 0;
            curOrder = nxtOrder;
        }

        // Then process the final match (either full or partial)
        if (curTickSum <= $.sizes[curOrder]) {
            matched = curTickSum;
            tick.matchAllFillResult($.latestFTag, result);
            self.tickBitmap.reset(curTick);
        } else {
            matched = $.sizes[curOrder];
            tick.matchPartialFillResult(matched.Uint128(), $.latestFTag, result);
        }

        $.sizes[curOrder] -= matched;
    }

    /// @dev only called by forcePurgeOobOrders
    function _bookPurgeOob(
        uint8 tickStep,
        int256 boundRate,
        FTag purgeTag,
        Side side,
        uint256 maxNTicksToPurge
    ) internal returns (uint256 /*nTicksPurged*/) {
        // assert(purgeTag.isPurge());

        OrderBook storage self = _getBook(side);
        TickMatchResult memory result;

        uint256 nTicksPurged = 0;
        for (; nTicksPurged < maxNTicksToPurge; nTicksPurged++) {
            (int16 curTick, bool found) = self.tickBitmap.begin(side);
            if (!found) {
                break;
            }

            int256 tickRate = TickMath.getRateAtTick(curTick, tickStep);
            if (side.checkRateInBound(tickRate, boundRate)) break;

            self.ticks[curTick].matchAllFillResult(purgeTag, result);
            self.tickBitmap.reset(curTick);

            OrderId from = OrderIdLib.from(side, curTick, result.beginFullyFilledOrderIndex);
            OrderId to = OrderIdLib.from(side, curTick, result.endFullyFilledOrderIndex - 1);

            emit OobOrdersPurged(from, to);
        }

        return nTicksPurged;
    }

    function __nextMatchableOrder(
        Side side,
        int16 curTick,
        int16[] memory limitTicks,
        uint256 curOrder
    ) private pure returns (uint256) {
        uint256 n = limitTicks.length;
        while (curOrder < n && !side.canMatch(limitTicks[curOrder], curTick)) curOrder = curOrder.inc();
        return curOrder;
    }

    function __removeZeroSizes(uint256[] memory sizes, int16[] memory limitTicks) private pure {
        uint256 keepCnt = 0;
        for (uint256 i = 0; i < sizes.length; i++) {
            if (sizes[i] == 0) continue;
            (sizes[keepCnt], limitTicks[keepCnt]) = (sizes[i], limitTicks[i]);
            keepCnt = keepCnt.inc();
        }
        sizes.setShorterLength(keepCnt);
        limitTicks.setShorterLength(keepCnt);
    }

    function _getNextNTicks(
        Side side,
        int16 startTick,
        uint256 nTicks
    ) internal view returns (int16[] memory ticks, uint256[] memory sizes) {
        unchecked {
            if (nTicks == 0) return (ticks, sizes);
            OrderBook storage self = _getBook(side);

            uint256 nFound;
            bool found;

            if (startTick == side.tickToGetFirstAvail()) {
                (startTick, found) = self.tickBitmap.begin(side);
                if (!found) return (ticks, sizes);

                ticks = new int16[](nTicks);
                ticks[0] = startTick;
                nFound = 1;
            } else {
                ticks = new int16[](nTicks);
            }

            for (int16 iTick = startTick; nFound < nTicks; ) {
                (iTick, found) = self.tickBitmap.next(iTick, side);
                if (!found) break;
                ticks[nFound++] = iTick;
            }

            ticks.setShorterLength(nFound);

            sizes = new uint256[](nFound);
            for (uint256 i = 0; i < nFound; i++) {
                sizes[i] = self.ticks[ticks[i]].getTickSum();
            }
        }
    }

    function _getBook(Side side) internal view returns (OrderBook storage) {
        return side == Side.LONG ? _OS().bookLong : _OS().bookShort;
    }

    function __getOrCreateMakerNonce(MarketAcc maker) private returns (uint40 /*makerNonce*/) {
        uint40 makerNonce = _OS().makerToNonce[maker];
        if (makerNonce == 0) {
            makerNonce = _OS().countMaker + 1;
            _OS().countMaker = makerNonce;
            _OS().makerToNonce[maker] = makerNonce;
            _OS().nonceToMaker[makerNonce] = maker;
        }

        return makerNonce;
    }

    // ------------ Only used in OffView ------------

    function _getOrderStatus(OrderId id) internal view returns (OrderStatus status) {
        (Side side, int16 tickIndex, uint40 orderIndex) = id.unpack();
        Tick storage tick = _getBook(side).ticks[tickIndex];
        (status, ) = tick.getOrderStatusAndSize(orderIndex);
    }
}
