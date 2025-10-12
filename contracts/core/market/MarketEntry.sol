// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

// External
import {Proxy} from "@openzeppelin/contracts/proxy/Proxy.sol";

// Interfaces
import {IMarketEntry, IMarketOrderAndOtc, IMarketRiskManagement} from "../../interfaces/IMarket.sol";

// Libraries
import {Err} from "../../lib/Errors.sol";
import {PMath} from "../../lib/math/PMath.sol";

// Types
import {MarketAcc} from "../../types/Account.sol";
import {
    FIndex,
    PayFee,
    LiqResult,
    LongShort,
    TokenId,
    MarketId,
    VMResult,
    GetRequest,
    CancelData
} from "../../types/MarketTypes.sol";
import {OrderId, Side} from "../../types/Order.sol";

// Components
import {MarketInfoAndState} from "./core/MarketInfoAndState.sol";
import {CoreOrderUtils} from "./core/CoreOrderUtils.sol";
import {CoreStateUtils} from "./core/CoreStateUtils.sol";
import {LiquidationViewUtils} from "./margin/LiquidationViewUtils.sol";

contract MarketEntry is IMarketEntry, CoreOrderUtils, CoreStateUtils, LiquidationViewUtils, Proxy {
    using PMath for uint256;

    uint256 public constant VERSION = 2;

    address internal immutable _MARKET_SETTING_AND_VIEW;
    address internal immutable _MARKET_ORDER_AND_OTC;
    address internal immutable _MARKET_RISK_MANAGEMENT;

    constructor(
        address marketHub_,
        address marketSetAndView_,
        address marketOrderAndOtc_,
        address marketRiskManagement_
    ) MarketInfoAndState(marketHub_) {
        _disableInitializers();
        _MARKET_SETTING_AND_VIEW = marketSetAndView_;
        _MARKET_ORDER_AND_OTC = marketOrderAndOtc_;
        _MARKET_RISK_MANAGEMENT = marketRiskManagement_;
    }

    function _implementation() internal view override returns (address) {
        if (msg.sig == IMarketOrderAndOtc.orderAndOtc.selector) {
            return _MARKET_ORDER_AND_OTC;
        }
        if (
            msg.sig == IMarketRiskManagement.forceDeleverage.selector ||
            msg.sig == IMarketRiskManagement.forcePurgeOobOrders.selector
        ) {
            return _MARKET_RISK_MANAGEMENT;
        }
        return _MARKET_SETTING_AND_VIEW;
    }

    function settleAndGet(
        MarketAcc userAddr,
        GetRequest getType
    ) external onlyMarketHub returns (VMResult /*res*/, PayFee /*settle*/, int256 /*signedSize*/, uint256 /*nOrders*/) {
        MarketMem memory market = _readMarket({checkPause: NO, checkMaturity: NO});
        (VMResult res, PayFee settle, int256 signedSize, uint256 nOrders) = _shortcutSettleAndGet(
            userAddr,
            market,
            getType
        );
        _writeMarketSkipOICheck(market);
        return (res, settle, signedSize, nOrders);
    }

    function cancel(
        MarketAcc userAddr,
        CancelData memory cancelData,
        bool isForceCancel
    ) external onlyMarketHub returns (PayFee /*settle*/, OrderId[] memory /*removedIds*/) {
        MarketMem memory market = _readMarket({checkPause: isForceCancel ? NO : YES, checkMaturity: YES});
        (UserMem memory user, PayFee settle) = _initUser(userAddr, market);

        OrderId[] memory removedIds = _coreRemoveAft(market, user, cancelData, isForceCancel);

        if (isForceCancel) {
            _incDelevLiqNonce(userAddr);
        }

        _writeUserNoCheck(user, market);
        _writeMarketSkipOICheck(market);

        return (settle, removedIds);
    }

    function liquidate(
        MarketAcc liqAddr,
        MarketAcc vioAddr,
        int256 sizeToLiq,
        int256 vioHealthRatio,
        int256 critHR
    ) external onlyMarketHub returns (LiqResult memory res) {
        require(liqAddr != vioAddr, Err.MarketInvalidLiquidation());

        MarketMem memory market = _readMarket({checkPause: YES, checkMaturity: YES});
        (UserMem memory liq, PayFee liqSettle) = _initUser(liqAddr, market);
        (UserMem memory vio, PayFee vioSettle) = _initUser(vioAddr, market);

        res.liqSettle = liqSettle;
        res.vioSettle = vioSettle;

        require(_isReducedOnly(vio.signedSize, -sizeToLiq), Err.MarketLiqNotReduceSize());

        _coreRemoveAllAft(market, vio, true);

        uint64 liqFeeRate;
        (res.liqTrade, liqFeeRate) = _calcLiqTradeAft(market, vio, sizeToLiq, vioHealthRatio);
        (res.liqPayment, res.vioPayment) = _mergeOTCAft(liq, vio, market, res.liqTrade, 0, liqFeeRate);

        _incDelevLiqNonce(vioAddr);

        LongShort memory empty;

        (res.isStrictIMLiq, res.finalVMLiq) = _writeUser(liq, market, res.liqPayment, empty, critHR, CLOCheck.SKIP);
        _writeUserNoCheck(vio, market);
        _writeMarketSkipOICheck(market);

        emit Liquidate(liqAddr, vioAddr, res.liqTrade, res.liqPayment.fee());

        return res;
    }

    function getMarkRate() external returns (int256) {
        return _getMarkRate();
    }

    function getImpliedRate()
        external
        view
        returns (
            int128 /*lastTradedRate*/,
            int128 /*oracleRate*/,
            uint32 /*lastTradedTime*/,
            uint32 /*observationWindow*/
        )
    {
        uint8 tickStep = _ctx().k_tickStep;
        return _ctx().impliedRate.getCurrentRate(tickStep);
    }

    function getBestFeeRates(
        MarketAcc user,
        MarketAcc otcCounter
    ) external view returns (uint64 /*takerFee*/, uint64 /*otcFee*/) {
        return (_getTakerFeeRate(user).Uint64(), _getOtcFeeRate(user, otcCounter).Uint64());
    }

    function getNextNTicks(
        Side side,
        int16 startTick,
        uint256 maxNTicks
    ) external view returns (int16[] memory /*ticks*/, uint256[] memory /*tickSizes*/) {
        return _getNextNTicks(side, startTick, maxNTicks);
    }

    function descriptor()
        external
        view
        returns (
            bool /*isIsolatedOnly*/,
            TokenId /*tokenId*/,
            MarketId /*marketId*/,
            uint32 /*maturity*/,
            uint8 /*tickStep*/,
            uint16 /*iTickThresh*/,
            uint32 /*latestFTime*/
        )
    {
        return (
            _ctx().k_isIsolatedOnly,
            _ctx().k_tokenId,
            _ctx().k_marketId,
            _ctx().k_maturity,
            _ctx().k_tickStep,
            _ctx().k_iTickThresh,
            _ctx().latestFTime
        );
    }

    function getLatestFIndex() external view returns (FIndex) {
        return _toFIndex(_ctx().latestFTag);
    }

    function getLatestFTime() external view returns (uint32) {
        return _ctx().latestFTime;
    }

    function getDelevLiqNonce(MarketAcc user) external view returns (uint24) {
        return _accState(user).delevLiqNonce;
    }

    // slither-disable-next-line locked-ether
    receive() external payable {
        revert();
    }
}
