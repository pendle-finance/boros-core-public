// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

// Interfaces
import {IAMM} from "../../../interfaces/IAMM.sol";
import {IRouterEventsAndTypes} from "../../../interfaces/IRouterEventsAndTypes.sol";

// Libraries
import {PMath} from "../../../lib/math/PMath.sol";
import {Err} from "../../../lib/Errors.sol";

// Types
import {MarketAcc} from "../../../types/Account.sol";
import {CancelData, GetRequest, LongShort, OrdersLib, MarketId, OTCTrade} from "../../../types/MarketTypes.sol";
import {OrderId, Side, TimeInForce} from "../../../types/Order.sol";
import {Trade, TradeLib} from "../../../types/Trade.sol";

// Router & Math
import {SwapMathParams} from "../math/SwapMath.sol";
import {TradeStorage} from "../trade-base/TradeStorage.sol";
import {SwapMathLib} from "../math/SwapMath.sol";
import {IMarket} from "../../../interfaces/IMarket.sol";

contract BookAmmSwapBase is IRouterEventsAndTypes, TradeStorage {
    using PMath for uint256;

    constructor(address marketHub_) TradeStorage(marketHub_) {}

    // * Auto split the amount into book & AMM, and perform the swap accordingly
    function _splitAndSwapBookAMM(
        SwapMathParams memory $,
        TimeInForce tif,
        int256 totalSize,
        int16 limitTick,
        OrderId idToCancel
    ) internal returns (Trade /*totalMatched*/, uint256 /*takerOtcFee*/) {
        require(!tif.isALO(), Err.TradeALOAMMNotAllowed());
        (int256 withBook, int256 withAMM) = $.calcSwapAmountBookAMM(totalSize, limitTick);
        LongShort memory orders = OrdersLib.createOrders(tif, withBook, limitTick);
        CancelData memory cancel = OrdersLib.createCancel(idToCancel, true);
        return _swapBookAMM($.user, $.amm, withAMM, orders, cancel);
    }

    function _createSwapMathParams(
        MarketCache memory cache,
        MarketAcc user,
        MarketAcc amm,
        Side side,
        uint32 timeToMat
    ) internal view returns (SwapMathParams memory swaps) {
        return SwapMathLib.create(cache.market, cache.tickStep, _getNumTicksToTryAtOnce(), user, amm, side, timeToMat);
    }

    // * The only entry point for swapping with AMM from the Router. This helps ensure that the path of AMM's returnedData is used
    //          by MarketHub to be the shortest and enforces an invariant that the Router will call MarketHub with exactly the data
    //          returned by the AMM.
    function _swapBookAMM(
        MarketAcc user,
        MarketAcc amm,
        int256 ammSwapSize,
        LongShort memory orders,
        CancelData memory cancelData
    ) internal returns (Trade /*totalMatched*/, uint256 /*takerOtcFee*/) {
        OTCTrade[] memory OTCs;
        Trade totalMatched;

        if (ammSwapSize != 0) {
            int256 ammCost = IAMM(amm.root()).swapByBorosRouter(ammSwapSize);

            OTCs = new OTCTrade[](1);
            OTCs[0] = OTCTrade({counter: amm, trade: TradeLib.from(ammSwapSize, ammCost), cashToCounter: 0});

            totalMatched = OTCs[0].trade;
        }

        (Trade bookMatched, uint256 takerOtcFee) = _MARKET_HUB.orderAndOtc(
            amm.marketId(),
            user,
            orders,
            cancelData,
            OTCs
        );
        totalMatched = totalMatched + bookMatched;

        return (totalMatched, takerOtcFee);
    }

    // * Similar logic to _swapBookAMM
    function _mintAMM(
        MarketAcc user,
        MarketAcc amm,
        int256 maxCashIn,
        int256 exactSizeIn
    ) internal returns (uint256 /*netLpOut*/, int256 /*netCashIn*/, uint256 /*mintOtcFee*/) {
        (int256 ammCash, int256 ammSize) = _settleAndGetCashAMM(amm);

        (int256 cashPreFee, uint256 netLpOut) = IAMM(amm.root()).mintByBorosRouter(
            user,
            ammCash,
            ammSize,
            maxCashIn,
            exactSizeIn
        );

        uint256 mintOtcFee = _otcAndCashTransfer(amm.marketId(), user, amm, TradeLib.from(-exactSizeIn, 0), cashPreFee);
        return (netLpOut, cashPreFee + mintOtcFee.Int(), mintOtcFee);
    }

    // * Similar logic to _mintAMM
    function _burnAMM(
        MarketAcc user,
        MarketAcc amm,
        uint256 lpToRemove
    ) internal returns (int256 /*netCashOut*/, int256 /*netSizeOut*/, uint256 /*burnOtcFee*/) {
        (int256 ammCash, int256 ammSize) = _settleAndGetCashAMM(amm);

        (int256 burnCashOut, int256 burnSizeOut, bool isMatured) = IAMM(amm.root()).burnByBorosRouter(
            user,
            ammCash,
            ammSize,
            lpToRemove
        );

        if (isMatured) {
            _MARKET_HUB.cashTransfer(user, amm, -burnCashOut);
            return (burnCashOut, 0, 0);
        } else {
            uint256 burnOtcFee = _otcAndCashTransfer(
                amm.marketId(),
                user,
                amm,
                TradeLib.from(burnSizeOut, 0),
                -burnCashOut
            );
            return (burnCashOut - burnOtcFee.Int(), burnSizeOut, burnOtcFee);
        }
    }

    function _otcAndCashTransfer(
        MarketId marketId,
        MarketAcc user,
        MarketAcc counter,
        Trade trade,
        int256 cashToCounter
    ) internal returns (uint256 otcFee) {
        LongShort memory emptyOrders;
        CancelData memory emptyCancels;

        OTCTrade[] memory OTCs = new OTCTrade[](1);
        OTCs[0] = OTCTrade({counter: counter, trade: trade, cashToCounter: cashToCounter});

        (, otcFee) = _MARKET_HUB.orderAndOtc(marketId, user, emptyOrders, emptyCancels, OTCs);
    }

    function _settleAndGetCashAMM(MarketAcc amm) internal returns (int256 cash, int256 size) {
        (cash,  /*totalIM*/, size) = _MARKET_HUB.settleAllAndGet(amm, GetRequest.ZERO, amm.marketId());
    }

    function _getTimeToMat(MarketCache memory cache) internal view returns (uint32 /*timeToMat*/) {
        return cache.maturity - IMarket(cache.market).getLatestFTime();
    }
}
