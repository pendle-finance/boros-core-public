// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

// Libraries
import {PMath} from "../../../lib/math/PMath.sol";
import {LowLevelArrayLib} from "../../../lib/ArrayLib.sol";
import {PaymentLib as Pay} from "../../../lib/PaymentLib.sol";

// Types
import {FIndex, FTag, PayFee, PayFeeLib as PLib, PartialData, SweptF} from "../../../types/MarketTypes.sol";
import {Trade, TradeLib, Fill, Side} from "../../../types/Trade.sol";

// Core
import {PendingOIPureUtils} from "./PendingOIPureUtils.sol";

abstract contract ProcessMergeUtils is PendingOIPureUtils {
    using Pay for Trade;
    using PMath for uint256;
    using LowLevelArrayLib for SweptF[];

    /// @dev Aft suffix means the call must only be post-processing the user
    function _mergeNewMatchAft(
        UserMem memory user,
        MarketMem memory market,
        Trade trade
    ) internal view returns (PayFee) {
        if (trade.isZero()) return PLib.ZERO;

        user.signedSize += trade.signedSize();
        _updateOIOnNewMatch(market, trade.absSize());

        return
            PLib.from(
                -trade.toUpfrontFixedCost(market.timeToMat),
                Pay.calcFloatingFee(trade.absSize(), _getTakerFeeRate(user.addr), market.timeToMat)
            );
    }

    function _mergeOTCAft(
        UserMem memory user,
        UserMem memory counter,
        MarketMem memory market,
        Trade trade,
        int256 cashToCounter,
        uint256 feeRate
    ) internal pure returns (PayFee /*user*/, PayFee /*counter*/) {
        Trade opposite = trade.opposite();

        user.signedSize += trade.signedSize();
        counter.signedSize += opposite.signedSize();

        int256 paymentUser = -trade.toUpfrontFixedCost(market.timeToMat);
        int256 paymentCounter = -opposite.toUpfrontFixedCost(market.timeToMat);
        uint256 fee = Pay.calcFloatingFee(trade.absSize(), feeRate, market.timeToMat);

        return (PLib.from(paymentUser - cashToCounter, fee), PLib.from(paymentCounter + cashToCounter, 0));
    }

    /// @dev must only be post-process. Fill is a limit order fill
    function _mergePartialFillAft(
        UserMem memory user,
        MarketMem memory market,
        Fill fill
    ) internal pure returns (int256 /*payment*/) {
        Trade trade = fill.toTrade();

        user.signedSize += trade.signedSize();
        _updateOIAndPMOnPartial(user, market, trade.side(), trade.absSize(), _calcPMFromFill(market, fill));

        return -trade.toUpfrontFixedCost(market.timeToMat);
    }

    function _processF(
        UserMem memory user,
        PartialData memory part,
        MarketMem memory market,
        SweptF[] memory longSweptF,
        SweptF[] memory shortSweptF
    ) internal returns (PayFee res) {
        if (longSweptF.length == 0 && shortSweptF.length == 0 && part.isZero() && user.fTag == market.latestFTag)
            return PLib.ZERO;

        __updateOIAndPMOnSettleAndPartial(user, market, longSweptF, shortSweptF, part);

        FIndex userIndex = _toFIndex(user.fTag);
        FIndex origIndex = userIndex;

        if (!part.isZero()) {
            res = __processSweptUntilStop(user, market, longSweptF, shortSweptF, part.fTag, part.getTrade());
        }

        res = res + __processSweptUntilStop(user, market, longSweptF, shortSweptF, market.latestFTag, TradeLib.ZERO);

        (int128 payment, uint128 fees) = res.unpack();
        emit PaymentFromSettlement(user.addr, origIndex.fTime(), market.latestFTime, payment, fees);
    }

    function __processSweptUntilStop(
        UserMem memory user,
        MarketMem memory market,
        SweptF[] memory longSweptF,
        SweptF[] memory shortSweptF,
        FTag stopFTag,
        Trade tradeAtStop
    ) private view returns (PayFee res) {
        FIndex userIndex = _toFIndex(user.fTag);
        do {
            FTag thisTag = stopFTag;
            if (longSweptF.length > 0) thisTag = thisTag.min(longSweptF[longSweptF.length.dec()].fTag);
            if (shortSweptF.length > 0) thisTag = thisTag.min(shortSweptF[shortSweptF.length.dec()].fTag);

            FIndex thisIndex = _toFIndex(thisTag);

            res = res + Pay.calcSettlement(user.signedSize, userIndex, thisIndex);
            (user.fTag, userIndex) = (thisTag, thisIndex);

            Trade sumTrade = thisTag == stopFTag ? tradeAtStop : TradeLib.ZERO;
            sumTrade =
                sumTrade +
                __iterateSweptSameTag(thisTag, longSweptF) +
                __iterateSweptSameTag(thisTag, shortSweptF);

            if (sumTrade.isZero()) continue;
            user.signedSize += sumTrade.signedSize();

            int256 upfrontCost = sumTrade.toUpfrontFixedCost(market.k_maturity - userIndex.fTime());
            res = res.subPayment(upfrontCost);
        } while (user.fTag != stopFTag);
    }

    function __iterateSweptSameTag(FTag tag, SweptF[] memory sweptF) private pure returns (Trade sumTrade) {
        uint256 n = sweptF.length;

        while (n > 0 && sweptF[n.dec()].fTag == tag) {
            n = n.dec();
            (bool isPurged, Fill fill) = sweptF[n].getFill();
            if (!isPurged) {
                sumTrade = sumTrade + fill.toTrade();
            }
        }

        sweptF.setShorterLength(n);
    }

    function __updateOIAndPMOnSettleAndPartial(
        UserMem memory user,
        MarketMem memory market,
        SweptF[] memory longSweptF,
        SweptF[] memory shortSweptF,
        PartialData memory part
    ) private pure {
        for (uint256 i = 0; i < longSweptF.length; i++) {
            _updateOIAndPMOnSwept(user, market, longSweptF[i]);
        }
        for (uint256 i = 0; i < shortSweptF.length; i++) {
            _updateOIAndPMOnSwept(user, market, shortSweptF[i]);
        }

        if (!part.isZero()) {
            _updateOIAndPMOnPartial(user, market, Side.LONG, part.sumLongSize, part.sumLongPM);
            _updateOIAndPMOnPartial(user, market, Side.SHORT, part.sumShortSize, part.sumShortPM);
        }
    }
}
