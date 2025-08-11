// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

// Libraries
import {Err} from "../../lib/Errors.sol";
import {PMath} from "../../lib/math/PMath.sol";

// Types
import {AccountLib, MarketAcc} from "../../types/Account.sol";
import {CancelData, LongShort, OTCTrade, PayFee, UserResult, OTCResult} from "../../types/MarketTypes.sol";
import {Trade, Fill} from "../../types/Trade.sol";
import {Side, OrderId} from "../../types/Order.sol";

// Interfaces
import {IMarketOrderAndOtc} from "../../interfaces/IMarket.sol";

// Core
import {CoreOrderUtils} from "./core/CoreOrderUtils.sol";
import {CoreStateUtils} from "./core/CoreStateUtils.sol";
import {MarketInfoAndState} from "./core/MarketInfoAndState.sol";

contract MarketOrderAndOtc is IMarketOrderAndOtc, CoreOrderUtils, CoreStateUtils {
    using PMath for int256;
    using PMath for uint256;

    constructor(address marketHub_) MarketInfoAndState(marketHub_) {
        _disableInitializers();
    }

    function orderAndOtc(
        MarketAcc userAddr,
        LongShort memory orders,
        CancelData memory cancels,
        OTCTrade[] memory OTCs,
        int256 critHR
    ) external onlyMarketHub returns (UserResult memory res, OTCResult[] memory otcRes) {
        _validateOrderAndOtc(userAddr, orders, OTCs);

        // Phase 1: Read market & user
        MarketMem memory market = _readMarket({checkPause: YES, checkMaturity: YES});
        (UserMem memory user, PayFee userSettle) = _initUser(userAddr, market);
        res.settle = userSettle;

        // Phase 2: remove orders
        res.removedIds = _coreRemoveAft(market, user, cancels, false);

        // Phase 3: Place orders & sum up payment
        _matchOrder(market, user, orders, res);
        _coreAdd(market, user, orders, res.bookMatched);

        // Phase 4: OTC
        if (OTCs.length != 0) {
            otcRes = new OTCResult[](OTCs.length);
            _otc(user, OTCs, res, otcRes, market, critHR);
        }

        // Phase 5: Write state
        (res.isStrictIM, res.finalVM) = _writeUser(user, market, res.payment, orders, critHR, CLOCheck.YES);
        _writeMarket(market);
    }

    function _matchOrder(
        MarketMem memory market,
        UserMem memory user,
        LongShort memory orders,
        UserResult memory res
    ) internal {
        (
            Trade bookMatched,
            Fill partialFill,
            MarketAcc partialMaker,
            int16 lastMatchedTick,
            int256 lastMatchedRate
        ) = _bookMatch(market.k_tickStep, market.latestFTag, orders);

        // check validity of the match
        if (bookMatched.isZero()) return;

        require(!_hasSelfFilledAfterMatch(user, partialMaker, orders.side, lastMatchedTick), Err.MarketSelfSwap());
        require(_checkRateDeviation(lastMatchedRate, market), Err.MarketLastTradedRateTooFar());

        // update oracle & merge new match
        _updateImpliedRate(lastMatchedTick, market.k_tickStep);

        (res.bookMatched, res.partialMaker) = (bookMatched, partialMaker);
        res.payment = _mergeNewMatchAft(user, market, bookMatched);
        emit MarketOrdersFilled(user.addr, bookMatched, res.payment.fee());

        // handle partial fill
        if (partialFill.isZero()) return;

        if (_squashPartial(res.partialMaker, partialFill, market)) {
            res.partialMaker = AccountLib.ZERO_MARKET_ACC;
            return;
        }

        (UserMem memory partialUser, PayFee partialSettle) = _initUser(res.partialMaker, market);
        res.partialPayFee = partialSettle.addPayment(_mergePartialFillAft(partialUser, market, partialFill));
        _writeUserNoCheck(partialUser, market);
    }

    function _hasSelfFilledAfterMatch(
        UserMem memory user,
        MarketAcc partialMaker,
        Side orderSide,
        int16 lastMatchedTick
    ) internal view returns (bool) {
        if (partialMaker == user.addr) return true;

        uint256 nLong = user.longIds.length;
        uint256 nShort = user.shortIds.length;
        Side matchingSide = orderSide.opposite();

        if (matchingSide == Side.LONG && nLong > 0) {
            OrderId bestLong = user.longIds[nLong - 1];
            return
                Side.LONG.possibleToBeFilled(bestLong.tickIndex(), lastMatchedTick) &&
                _bookCanSettleSkipSizeCheck(bestLong);
        }
        if (matchingSide == Side.SHORT && nShort > 0) {
            OrderId bestShort = user.shortIds[nShort - 1];
            return
                Side.SHORT.possibleToBeFilled(bestShort.tickIndex(), lastMatchedTick) &&
                _bookCanSettleSkipSizeCheck(bestShort);
        }

        return false;
    }

    function _checkRateDeviation(int256 lastMatchedRate, MarketMem memory market) internal view returns (bool) {
        return
            (market.rMark - lastMatchedRate).abs() <=
            mulBase1e4(market.k_iThresh.max(market.rMark.abs()), _ctx().maxRateDeviationFactorBase1e4);
    }

    function _otc(
        UserMem memory user,
        OTCTrade[] memory OTCs,
        UserResult memory userRes,
        OTCResult[] memory otcResArr,
        MarketMem memory market,
        int256 critHR
    ) internal {
        uint256[] memory feeRates = _getOtcFeeRates(user.addr, OTCs);

        LongShort memory empty;
        for (uint256 i = 0; i < OTCs.length; i++) {
            OTCResult memory otcRes = otcResArr[i];
            (Trade trade, int256 cashToCounter) = (OTCs[i].trade, OTCs[i].cashToCounter);

            (UserMem memory counter, PayFee counterSettle) = _initUser(OTCs[i].counter, market);
            otcRes.settle = counterSettle;

            PayFee paymentUser;

            (paymentUser, otcRes.payment) = _mergeOTCAft(user, counter, market, trade, cashToCounter, feeRates[i]);
            userRes.payment = userRes.payment + paymentUser;

            emit OtcSwap(user.addr, counter.addr, trade, cashToCounter, paymentUser.fee());

            (otcRes.isStrictIM, otcRes.finalVM) = _writeUser(
                counter,
                market,
                otcRes.payment,
                empty,
                critHR,
                CLOCheck.YES
            );
        }
    }

    function _validateOrderAndOtc(MarketAcc user, LongShort memory orders, OTCTrade[] memory OTCs) internal pure {
        // Validate orders
        require(orders.sizes.length == orders.limitTicks.length, Err.InvalidLength());
        for (uint256 i = 0; i < orders.sizes.length; i++) {
            require(orders.sizes[i] != 0, Err.MarketZeroSize());
        }

        // Validate OTCs
        for (uint256 i = 0; i < OTCs.length; i++) {
            require(OTCs[i].counter != user, Err.MarketSelfSwap());
            for (uint256 j = i + 1; j < OTCs.length; j++) {
                require(OTCs[i].counter != OTCs[j].counter, Err.MarketDuplicateOTC());
            }
        }
    }
}
