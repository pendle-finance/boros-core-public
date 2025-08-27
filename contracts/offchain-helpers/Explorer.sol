// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IExplorer} from "./../interfaces/IExplorer.sol";
import {IFIndexOracle} from "./../interfaces/IFIndexOracle.sol";
import {IMarketAllTypes, IMarketOff} from "./../interfaces/IMarket.sol";
import {IMarketHub} from "./../interfaces/IMarketHub.sol";
import {IRouterEventsAndTypes} from "./../interfaces/IRouterEventsAndTypes.sol";
import {ITradeModule} from "./../interfaces/ITradeModule.sol";
import {PMath} from "./../lib/math/PMath.sol";
import {TickMath} from "./../lib/math/TickMath.sol";
import {MarketAcc} from "./../types/Account.sol";
import {AMMId, GetRequest, MarginType, MarketId, MarketIdLib, TokenId} from "./../types/MarketTypes.sol";
import {OrderId, OrderIdLib, Side, TimeInForce} from "./../types/Order.sol";
import {PendleRolesPlugin} from "./../core/roles/PendleRoles.sol";
import {Trade} from "./../types/Trade.sol";
import {IMiscModule} from "./../interfaces/IMiscModule.sol";
import {IRouter} from "./../interfaces/IRouter.sol";
import {CreateCompute} from "./../types/createCompute.sol";

contract Explorer is IExplorer, PendleRolesPlugin {
    using PMath for int256;
    using PMath for uint32;
    using PMath for uint256;

    address public immutable MARKET_FACTORY;
    address public immutable MARKET_HUB;
    address public immutable ROUTER;

    constructor(
        address permissionController_,
        address marketFactory_,
        address marketHub_,
        address router_
    ) PendleRolesPlugin(permissionController_) {
        MARKET_FACTORY = marketFactory_;
        MARKET_HUB = marketHub_;
        ROUTER = router_;
    }

    function _offchainSimulate(MarketAcc user, bytes memory data) internal returns (bytes memory, UserInfo memory) {
        IMiscModule.SimulateData[] memory calls = new IMiscModule.SimulateData[](2);
        calls[0] = IMiscModule.SimulateData({account: user.account(), target: ROUTER, data: data});
        calls[1] = IMiscModule.SimulateData({
            account: user.account(),
            target: address(this),
            data: abi.encodeCall(IExplorer.getUserInfo, (user))
        });
        (bytes[] memory results, ) = IRouter(ROUTER).batchSimulate(calls);
        return (results[0], abi.decode(results[1], (UserInfo)));
    }

    function _settleAll(MarketAcc user) internal {
        IMarketHub(MARKET_HUB).settleAllAndGet(user, GetRequest.ZERO, MarketIdLib.ZERO);
    }

    function getUserInfo(MarketAcc user) public returns (UserInfo memory userInfo) {
        _settleAll(user);

        MarketId[] memory marketIds = IMarketHub(MARKET_HUB).getEnteredMarkets(user);

        userInfo.totalCash = IMarketHub(MARKET_HUB).accCash(user);
        userInfo.positions = new PositionInfo[](marketIds.length);

        int256 totalValue = userInfo.totalCash;
        uint256 totalInitialMargin = 0;
        uint256 totalMaintMargin = 0;

        for (uint256 i = 0; i < marketIds.length; i++) {
            IMarketOff market = IMarketOff(marketIdToAddress(marketIds[i]));

            int256 signedSize = market.getSignedSizeNoSettle(user);
            int256 positionValue = market.calcPositionValueNoSettle(user);
            uint256 initialMargin = market.calcMarginNoSettle(user, MarginType.IM);
            uint256 maintMargin = market.calcMarginNoSettle(user, MarginType.MM);

            userInfo.positions[i] = PositionInfo({
                marketId: marketIds[i],
                signedSize: signedSize,
                positionValue: positionValue,
                liquidationApr: 0, // calculated below
                initialMargin: initialMargin,
                maintMargin: maintMargin,
                orders: market.getAllOpenOrders(user)
            });

            totalValue += positionValue;
            totalInitialMargin += initialMargin;
            totalMaintMargin += maintMargin;
        }
        userInfo.availableInitialMargin = totalValue - totalInitialMargin.Int();
        userInfo.availableMaintMargin = totalValue - totalMaintMargin.Int();

        for (uint256 i = 0; i < marketIds.length; i++) {
            PositionInfo memory position = userInfo.positions[i];
            int256 signedSize = position.signedSize;
            if (signedSize == 0) continue;

            IMarketOff market = IMarketOff(marketIdToAddress(marketIds[i]));
            try
                Explorer(address(this)).calcLiquidationRate(
                    market,
                    user,
                    signedSize,
                    (totalValue - position.positionValue) - (totalMaintMargin - position.maintMargin).Int()
                )
            returns (int256 liquidationApr) {
                position.liquidationApr = liquidationApr;
            } catch {
                position.liquidationApr = 0;
            }
        }
    }

    function getUserInfoAfterPlaceOrder(
        MarketAcc user,
        MarketId marketId,
        AMMId ammId,
        Side side,
        TimeInForce tif,
        uint256 size,
        int16 tick,
        int128 desiredMatchRate
    )
        external
        returns (UserInfo memory preUserInfo, UserInfo memory postUserInfo, Trade matched, uint256 marginRequired)
    {
        preUserInfo = getUserInfo(user);

        IRouterEventsAndTypes.OrderReq memory order = IRouterEventsAndTypes.OrderReq({
            cross: user.isCross(),
            marketId: marketId,
            ammId: ammId,
            side: side,
            tif: tif,
            size: size,
            tick: tick
        });

        IRouterEventsAndTypes.SingleOrderReq memory singleOrderReq = IRouterEventsAndTypes.SingleOrderReq({
            order: order,
            enterMarket: false,
            exitMarket: false,
            idToStrictCancel: OrderIdLib.ZERO,
            isolated_cashIn: 0,
            isolated_cashTransferAll: false,
            desiredMatchRate: desiredMatchRate
        });

        bytes memory result;
        (result, postUserInfo) = _offchainSimulate(
            user,
            abi.encodeCall(ITradeModule.placeSingleOrder, (singleOrderReq))
        );
        matched = abi.decode(result, (Trade));

        if (postUserInfo.availableInitialMargin < preUserInfo.availableInitialMargin) {
            marginRequired = uint256(preUserInfo.availableInitialMargin - postUserInfo.availableInitialMargin);
        }
    }

    function getUserInfoAfterBulkCancels(
        MarketAcc user,
        MarketId marketId,
        bool cancelAll,
        OrderId[] memory orderIds
    ) external returns (UserInfo memory preUserInfo, UserInfo memory postUserInfo) {
        preUserInfo = getUserInfo(user);

        IRouterEventsAndTypes.BulkCancels memory cancels = IRouterEventsAndTypes.BulkCancels({
            cross: user.isCross(),
            marketId: marketId,
            cancelAll: cancelAll,
            orderIds: orderIds
        });

        (, postUserInfo) = _offchainSimulate(user, abi.encodeCall(ITradeModule.bulkCancels, (cancels)));
    }

    function getMarketInfo(MarketId marketId) external view returns (MarketInfo memory info) {
        IMarketOff market = IMarketOff(marketIdToAddress(marketId));
        address fIndexOracle = market.getMarketConfig().fIndexOracle;

        (
            bool isIsolatedOnly,
            TokenId tokenId,
            ,
            uint32 maturity,
            uint8 tickStep,
            uint16 iTickThresh,
            uint32 latestFTime
        ) = market.descriptor();
        (int256 impliedApr, , , ) = market.getImpliedRate();

        int256 markApr = market.getMarkRateView();
        int256 underlyingApr = IFIndexOracle(fIndexOracle).latestAnnualizedRate();
        uint32 nextSettleTime = IFIndexOracle(fIndexOracle).nextFIndexUpdateTime();

        info = MarketInfo({
            name: market.name(),
            symbol: market.symbol(),
            isIsolatedOnly: isIsolatedOnly,
            tokenId: tokenId,
            marketId: marketId,
            maturity: maturity,
            tickStep: tickStep,
            iTickThresh: iTickThresh,
            isMatured: latestFTime >= maturity,
            impliedApr: impliedApr,
            markApr: markApr,
            underlyingApr: underlyingApr,
            nextSettleTime: nextSettleTime
        });
    }

    function getMarketOrderBook(
        MarketId marketId,
        Side side,
        int16 from,
        int16 to
    ) external view returns (uint256[] memory size) {
        assert(from <= to);
        IMarketOff market = IMarketOff(marketIdToAddress(marketId));
        return market.getTickSumSize(side, from, to);
    }

    function marketIdToAddress(MarketId marketId) internal view returns (address) {
        return CreateCompute.compute(MARKET_FACTORY, marketId);
    }

    function calcLiquidationRate(
        IMarketOff market,
        MarketAcc user,
        int256 size,
        int256 availValueExclude
    ) external view returns (int256 liqRate) {
        if (size.abs() < 1000) {
            return 0;
        }

        IMarketAllTypes.MarketConfigStruct memory config = market.getMarketConfig();

        int256 kMM;
        {
            (, uint256 _kMM) = market.getMarginFactor(user);
            kMM = _kMM.Int();
        }

        int256 timeToMat;
        int256 iThresh;
        {
            (, , , uint32 maturity, uint8 tickStep, uint16 iTickThresh, uint32 latestFTime) = market.descriptor();
            timeToMat = (maturity - latestFTime).Int();
            iThresh = TickMath.getRateAtTick(int16(iTickThresh), tickStep);
        }

        if (timeToMat == 0) {
            return 0;
        }

        int256 absSize = size.abs().Int();
        int256 scaledTThresh = config.tThresh.Int().mulDown(kMM);
        int256 sizeTimeToMat = (size * timeToMat) / 365 days;
        int256 marginDuration = timeToMat.max(config.tThresh.Int());

        /*
        Case 1: absMarkRate <= iThresh
        MM = absSize * iThresh * kMM * marginDuration
        */
        {
            // availValueExclude + size * markRate * timeToMat =  MM
            int256 MM = (absSize.mulDown(iThresh).mulDown(kMM) * marginDuration) / 365 days;
            if (sizeTimeToMat != 0) {
                int256 markRate = (MM - availValueExclude).divDown(sizeTimeToMat);
                if (markRate.abs().Int() <= iThresh) {
                    return markRate;
                }
            }
        }

        /*
        Case 2a: markRate > iThresh
        MM = absSize * markRate * kMM * marginDuration
        */
        {
            // availValueExclude + size * markRate * timeToMat = mm * markRate
            int256 mm = (absSize.mulDown(kMM) * marginDuration) / 365 days;
            if (sizeTimeToMat - mm != 0) {
                int256 markRate = -availValueExclude.divDown(sizeTimeToMat - mm);

                bool switchedMM = timeToMat < scaledTThresh && size * markRate > 0;
                if (markRate > iThresh && !switchedMM) {
                    return markRate;
                }
            }
        }

        /*
        Case 2b: markRate < -iThresh
        MM = absSize * -markRate * kMM * marginDuration
        */
        {
            // availValueExclude + size * markRate * timeToMat = -mm * markRate
            int256 mm = (absSize.mulDown(kMM) * marginDuration) / 365 days;
            if (sizeTimeToMat + mm != 0) {
                int256 markRate = -availValueExclude.divDown(sizeTimeToMat + mm);

                bool switchedMM = timeToMat < scaledTThresh && size * markRate > 0;
                if (markRate < -iThresh && !switchedMM) {
                    return markRate;
                }
            }
        }
    }
}
