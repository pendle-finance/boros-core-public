// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

// Interfaces
import {IMarketOffViewOnly} from "../../interfaces/IMarket.sol";

// Libraries
import {PaymentLib as Pay} from "../../lib/PaymentLib.sol";
import {TickMath} from "../../lib/math/TickMath.sol";

// Types
import {MarketAcc} from "../../types/Account.sol";
import {MarginType, VMResult} from "../../types/MarketTypes.sol";
import {OrderId, Side, OrderStatus} from "../../types/Order.sol";
import {Trade} from "../../types/Trade.sol";

// Components
import {CoreOrderUtils} from "./core/CoreOrderUtils.sol";
import {CoreStateUtils} from "./core/CoreStateUtils.sol";
import {LiquidationViewUtils} from "./margin/LiquidationViewUtils.sol";
import {Tick} from "./orderbook/Tick.sol";

abstract contract MarketOffView is IMarketOffViewOnly, CoreOrderUtils, CoreStateUtils, LiquidationViewUtils {
    // --- Various misc view function---
    function name() external view returns (string memory) {
        return _ctx().name;
    }

    function symbol() external view returns (string memory) {
        return _ctx().symbol;
    }

    function marketHub() external view returns (address) {
        return _MARKET_HUB;
    }

    function getOI() external view returns (uint256) {
        return _ctx().OI;
    }

    function getMarkRateView() external view returns (int256) {
        return _getMarkRateView();
    }

    function getTickSumSize(Side side, int16 fromTick, int16 toTick) external view returns (uint256[] memory sizes) {
        OrderBook storage self = _getBook(side);
        int256 fromTick256 = int256(fromTick);
        int256 toTick256 = int256(toTick);
        sizes = new uint256[](uint256(toTick256 - fromTick256 + 1));
        for (int256 i = fromTick256; i <= toTick256; i++) {
            sizes[uint256(i - fromTick256)] = self.ticks[int16(i)].getTickSum();
        }
        return sizes;
    }

    function getPendingSizes(
        MarketAcc userAddr
    ) external view returns (uint256 /*pendingLongSize*/, uint256 /*pendingShortSize*/) {
        UserMem memory user = _readUserView(userAddr);
        return (user.pmData.sumLongSize, user.pmData.sumShortSize);
    }

    function getAllOpenOrders(MarketAcc userAddr) external view returns (Order[] memory orders) {
        UserMem memory user = _readUserView(userAddr);

        uint256 count = 0;
        orders = new Order[](user.longIds.length + user.shortIds.length);
        for (uint256 i = 0; i < user.longIds.length; ++i) {
            if (_getOrderStatus(user.longIds[i]) == OrderStatus.OPEN) {
                orders[count++] = getOrder(user.longIds[i]);
            }
        }
        for (uint256 i = 0; i < user.shortIds.length; ++i) {
            if (_getOrderStatus(user.shortIds[i]) == OrderStatus.OPEN) {
                orders[count++] = getOrder(user.shortIds[i]);
            }
        }

        assembly ("memory-safe") {
            mstore(orders, count)
        }
    }

    function getOrder(OrderId id) public view returns (Order memory order) {
        (Side side, int16 tickIndex, uint40 orderIndex) = id.unpack();
        Tick storage tick = _getBook(side).ticks[tickIndex];

        (OrderStatus status, uint256 size) = tick.getOrderStatusAndSize(orderIndex);
        if (status != OrderStatus.NOT_EXIST) {
            order = Order({
                status: status,
                id: id,
                maker: _OS().nonceToMaker[tick.makerNonceOf(orderIndex)],
                size: size,
                rate: TickMath.getRateAtTick(tickIndex, _ctx().k_tickStep)
            });
        }
    }

    function calcPositionValueNoSettle(MarketAcc userAddr) external view returns (int256) {
        MarketMem memory market = _readMarketView();
        UserMem memory user = _readUserView(userAddr);

        return Pay.calcPositionValue(user.signedSize, market.rMark, market.timeToMat);
    }

    function calcMarginNoSettle(MarketAcc userAddr, MarginType marginType) external view returns (uint256) {
        MarketMem memory market = _readMarketView();
        if (_isMatured(market)) {
            return 0;
        }

        UserMem memory user = _readUserView(userAddr);

        VMResult res;
        if (marginType == MarginType.IM) {
            res = _getIMAft(market, user);
        } else {
            res = _getMMAft(market, user);
        }

        (, uint256 margin) = res.unpack();
        return margin;
    }

    function calcLiqTradeNoSettle(
        MarketAcc vioAddr,
        int256 sizeToLiq,
        int256 vioHealthRatio
    ) external view returns (Trade liqTrade) {
        MarketMem memory market = _readMarketView();
        UserMem memory vio = _readUserView(vioAddr);

        (liqTrade, ) = _calcLiqTradeAft(market, vio, sizeToLiq, vioHealthRatio);
    }

    function getSignedSizeNoSettle(MarketAcc userAddr) external view returns (int256) {
        UserMem memory user = _readUserView(userAddr);
        return user.signedSize;
    }

    function getMarketConfig() external view returns (MarketConfigStruct memory) {
        return
            MarketConfigStruct({
                maxOpenOrders: _ctx().maxOpenOrders,
                markRateOracle: _ctx().markRateOracle,
                fIndexOracle: _ctx().fIndexOracle,
                hardOICap: _ctx().hardOICap,
                takerFee: _ctx().takerFee,
                otcFee: _ctx().otcFee,
                liqSettings: _ctx().liqSettings,
                kIM: _ctx().kIM,
                kMM: _ctx().kMM,
                tThresh: _ctx().tThresh,
                maxRateDeviationFactorBase1e4: _ctx().maxRateDeviationFactorBase1e4,
                closingOrderBoundBase1e4: _ctx().closingOrderBoundBase1e4,
                loUpperConstBase1e4: _ctx().loUpperConstBase1e4,
                loUpperSlopeBase1e4: _ctx().loUpperSlopeBase1e4,
                loLowerConstBase1e4: _ctx().loLowerConstBase1e4,
                loLowerSlopeBase1e4: _ctx().loLowerSlopeBase1e4,
                status: _ctx().status,
                useImpliedAsMarkRate: _ctx().useImpliedAsMarkRate
            });
    }

    function getDiscRates(MarketAcc user) external view returns (uint64 takerDisc, uint64 otcDisc) {
        return (_accState(user).takerDisc, _accState(user).otcDisc);
    }

    function getMarginFactor(MarketAcc user) external view returns (uint64 kIM, uint64 kMM) {
        return (_kIM(user), _kMM(user));
    }

    function getExemptCLOCheck(MarketAcc user) external view returns (bool exemptCLOCheck) {
        return _accState(user).exemptCLOCheck;
    }

    function _readMarketView() internal view returns (MarketMem memory market) {
        market.rMark = _getMarkRateView();
        _readMarketExceptMarkRate(market);
    }

    function _readUserView(MarketAcc userAddr) internal view returns (UserMem memory user) {
        _initUserCoreData(user, userAddr, false);
    }
}
