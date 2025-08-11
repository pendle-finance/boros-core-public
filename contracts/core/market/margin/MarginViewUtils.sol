// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

// Libraries
import {Err} from "../../../lib/Errors.sol";
import {PMath} from "../../../lib/math/PMath.sol";
import {TickMath} from "../../../lib/math/TickMath.sol";
import {PaymentLib as Pay} from "../../../lib/PaymentLib.sol";

// Types
import {VMResult, VMResultLib, LongShort, PayFee} from "../../../types/MarketTypes.sol";
import {Side} from "../../../types/Order.sol";
import {Fill} from "../../../types/Trade.sol";

// Core
import {MarketInfoAndState} from "../core/MarketInfoAndState.sol";

// Interfaces
import {IMarketAllEventsAndTypes} from "../../../interfaces/IMarket.sol";

abstract contract MarginViewUtils is IMarketAllEventsAndTypes, MarketInfoAndState {
    using PMath for int256;
    using PMath for uint256;
    using PMath for uint128;
    using PMath for uint32;

    /// @dev Aft suffix means the call must only be post-processing the user
    function _getIMAft(MarketMem memory market, UserMem memory user) internal view returns (VMResult) {
        return VMResultLib.from(_getValueAft(market, user), _calcIM(market, user, _kIM(user.addr)));
    }

    function _getMMAft(MarketMem memory market, UserMem memory user) internal view returns (VMResult) {
        return VMResultLib.from(_getValueAft(market, user), _calcMM(market, user.signedSize, _kMM(user.addr)));
    }

    function _calcIM(MarketMem memory market, UserMem memory user, uint64 kIM) internal pure returns (uint256) {
        uint256 PM = _calcPM(market, user);
        return (PM * kIM * market.timeToMat.max(market.tThresh)).rawDivUp(PMath.ONE_MUL_YEAR);
    }

    /// @dev long, complicated formulas following the white-paper strictly
    function _calcMM(MarketMem memory market, int256 signedSize, uint64 kMM) internal pure returns (uint256) {
        uint256 absSize = signedSize.abs();
        uint256 absMarkRate = market.rMark.abs();

        if (absMarkRate > market.k_iThresh) {
            uint256 scaledTThresh = market.tThresh.mulUp(kMM);
            if (market.timeToMat < scaledTThresh && signedSize * market.rMark > 0) {
                return
                    (absSize * (absMarkRate * market.timeToMat + market.k_iThresh * (scaledTThresh - market.timeToMat)))
                        .rawDivUp(PMath.ONE_MUL_YEAR);
            }
            // else use the calculation outside
        }

        uint256 PM = __calcPMFromRate(absSize, market.rMark, market.k_iThresh);
        return (PM * kMM * market.timeToMat.max(market.tThresh)).rawDivUp(PMath.ONE_MUL_YEAR);
    }

    function _getValueAft(MarketMem memory market, UserMem memory user) internal pure returns (int256) {
        return Pay.calcPositionValue(user.signedSize, market.rMark, market.timeToMat);
    }

    function _calcPM(MarketMem memory market, UserMem memory user) internal pure returns (uint256) {
        int256 S = user.signedSize;
        uint256 pmAlone = __calcPMFromRate(S.abs(), market.rMark, market.k_iThresh);

        (uint256 B_Long, uint256 pmLong) = (user.pmData.sumLongSize, user.pmData.sumLongPM);
        uint256 pmTotalLong;

        if (S < 0 && B_Long <= S.abs()) pmTotalLong = 0;
        else {
            if (S > 0) pmTotalLong = pmLong + pmAlone;
            else pmTotalLong = pmLong > pmAlone ? pmLong - pmAlone : 0;
        }

        (uint256 B_Short, uint256 pmShort) = (user.pmData.sumShortSize, user.pmData.sumShortPM);
        uint256 pmTotalShort;

        if (S > 0 && B_Short <= S.abs()) pmTotalShort = 0;
        else {
            if (S < 0) pmTotalShort = pmShort + pmAlone;
            else pmTotalShort = pmShort > pmAlone ? pmShort - pmAlone : 0;
        }

        return pmTotalLong.max(pmTotalShort);
    }

    function _calcPMFromFill(MarketMem memory market, Fill fill) internal pure returns (uint256) {
        return fill.absCost().max(fill.absSize().mulDown(market.k_iThresh));
    }

    function _calcPMFromTick(
        MarketMem memory market,
        uint256 absSize,
        int16 tickIndex
    ) internal pure returns (uint256) {
        int256 rate = TickMath.getRateAtTick(tickIndex, market.k_tickStep);
        return __calcPMFromRate(absSize, rate, market.k_iThresh);
    }

    function __calcPMFromRate(uint256 absSize, int256 rate, uint256 k_iThresh) private pure returns (uint256) {
        uint256 absRate = rate.abs();
        return absSize.mulDown(absRate.max(k_iThresh));
    }

    // --

    int256 private constant LONG_SIDE = 1;
    int256 private constant SHORT_SIDE = -1;
    int256 private constant ZERO_SIDE = 0;

    /// @dev Rather complicated conditions, also following the white-paper closely but tweak a bit for ease of implementation
    function _checkMargin(
        MarketMem memory market,
        UserMem memory user,
        PayFee post /*postPayment*/,
        LongShort memory orders,
        int256 critHR
    ) internal view returns (bool /*onlyClosing*/, bool /*isStrictIM*/, VMResult /*finalVM*/) {
        int256 rWorst = _getWorstRate(orders, market); // only valid if orders is not empty
        if (!orders.isEmpty()) {
            // users' orders must always be within bounds
            int256 rateBound = _calcRateBound(market, orders.side);
            require(orders.side.checkRateInBound(rWorst, rateBound), Err.MarketOrderRateOutOfBound());
        }

        if (!_isUserClosingOnly(user, orders)) {
            // if user is not closing only, we definitely check isStrictIM
            return (false, true, _getIMAft(market, user));
        }

        // from here on onlyClosing is true
        if (!orders.isEmpty()) {
            if (
                (market.rMark - rWorst) * user.signedSize.sign() >
                int256(mulBase1e4(market.k_iThresh.max(market.rMark.abs()), _ctx().closingOrderBoundBase1e4))
            ) {
                return (true, true, _getIMAft(market, user));
            }
        }

        // change in value and maintenance margin due to the batch must satisfy a condition
        // v_pre - v_aft
        int256 diffValue = Pay.calcPositionValue(user.postSettleSize, market.rMark, market.timeToMat) -
            Pay.calcPositionValue(user.signedSize, market.rMark, market.timeToMat) -
            post.total();

        (uint256 mmPost, int256 diffMargin) = (0, 0);

        {
            // m_pre - m_aft
            uint64 kMM = _kMM(user.addr);
            uint256 mmPre = _calcMM(market, user.postSettleSize, kMM);

            mmPost = _calcMM(market, user.signedSize, kMM);
            diffMargin = mmPre.Int() - mmPost.Int();
        }

        if (diffValue > diffMargin.mulFloor(critHR)) {
            return (true, true, _getIMAft(market, user));
        }

        // Passed all conditions to be exempt from strictIM
        return (true, false, VMResultLib.from(_getValueAft(market, user), mmPost));
    }

    function _isUserClosingOnly(UserMem memory user, LongShort memory orders) private pure returns (bool) {
        int256 preSize = user.postSettleSize;
        int256 finalSize = user.signedSize;

        // size of the position must be reduced (or stays the same)
        if (finalSize.abs() > preSize.abs() || finalSize.sign() * preSize.sign() < 0) {
            return false;
        }

        int256 finalSign = finalSize.sign();

        // total book size for the opposite side of the position must not exceed the position size
        {
            (uint256 longSize, uint256 shortSize) = (user.pmData.sumLongSize, user.pmData.sumShortSize);
            if (finalSign == ZERO_SIDE) {
                if (longSize != 0 || shortSize != 0) return false;
            } else if (finalSign == LONG_SIDE) {
                if (shortSize > finalSize.abs()) return false;
            } else if (finalSign == SHORT_SIDE) {
                if (longSize > finalSize.abs()) return false;
            }
        }

        // no more limit orders are allowed to open more position
        if (!orders.isEmpty()) {
            if (finalSign == ZERO_SIDE) {
                return false;
            } else if (finalSign == LONG_SIDE) {
                if (orders.side == Side.LONG) return false;
            } else if (finalSign == SHORT_SIDE) {
                if (orders.side == Side.SHORT) return false;
            }
        }

        return true;
    }

    function _getWorstRate(LongShort memory orders, MarketMem memory market) internal pure returns (int256) {
        if (orders.isEmpty()) return 0;
        int16 tickWorst = orders.limitTicks[0];
        if (orders.side == Side.LONG) {
            for (uint256 i = 0; i < orders.limitTicks.length; i++) {
                int16 t = orders.limitTicks[i];
                if (t > tickWorst) tickWorst = t;
            }
        } else {
            for (uint256 i = 0; i < orders.limitTicks.length; i++) {
                int16 t = orders.limitTicks[i];
                if (t < tickWorst) tickWorst = t;
            }
        }
        return TickMath.getRateAtTick(tickWorst, market.k_tickStep);
    }

    function _calcRateBound(MarketMem memory market, Side side) internal view returns (int256) {
        int256 rMark = market.rMark;
        if (rMark >= 0) {
            return __calcRateBoundPositive(rMark, market.k_iThresh, side);
        } else {
            return -__calcRateBoundPositive(-rMark, market.k_iThresh, side.opposite());
        }
    }

    function __calcRateBoundPositive(int256 rMark, uint256 k_iThresh, Side side) private view returns (int256) {
        if (rMark >= int256(k_iThresh)) {
            int16 slope = side == Side.LONG ? _ctx().loUpperSlopeBase1e4 : _ctx().loLowerSlopeBase1e4;
            return mulBase1e4(rMark, slope);
        } else {
            int16 constBase1e4 = side == Side.LONG ? _ctx().loUpperConstBase1e4 : _ctx().loLowerConstBase1e4;
            return addBase1e18And1e4(rMark, constBase1e4);
        }
    }

    function mulBase1e4(uint256 x, uint16 y) internal pure returns (uint256) {
        return (x * y) / 1e4;
    }

    function mulBase1e4(int256 x, int16 y) internal pure returns (int256) {
        return (x * y) / 1e4;
    }

    function addBase1e18And1e4(int256 x, int16 y) internal pure returns (int256) {
        return x + int256(y) * 1e14;
    }
}
