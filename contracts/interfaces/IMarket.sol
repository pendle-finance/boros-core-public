// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {MarketAcc} from "./../types/Account.sol";
import {
    FIndex,
    FTag,
    MarginType,
    PayFee,
    LongShort,
    LiqResult,
    DelevResult,
    PMDataMem,
    OTCTrade,
    VMResult,
    GetRequest,
    PartialData,
    AccountData2,
    TokenId,
    MarketId,
    UserResult,
    OTCResult,
    CancelData
} from "./../types/MarketTypes.sol";
import {MarketImpliedRate, MarketImpliedRateLib} from "./../types/MarketImpliedRate.sol";
import {OrderId, Side, OrderStatus} from "./../types/Order.sol";
import {Trade} from "./../types/Trade.sol";
import {StoredOrderIdArr} from "./../types/StoredOrderIdArr.sol";

interface IMarketAllTypes {
    enum MarketStatus {
        PAUSED,
        CLO, // CLOSE-ONLY
        GOOD
    }

    struct MarketCtx {
        // 256 bits
        bool k_isIsolatedOnly;
        uint32 k_maturity;
        TokenId k_tokenId;
        MarketId k_marketId;
        uint8 k_tickStep;
        uint16 k_iTickThresh;
        uint16 maxOpenOrders;
        uint32 tThresh;
        uint16 maxRateDeviationFactorBase1e4;
        uint16 closingOrderBoundBase1e4;
        MarketStatus status;
        FTag latestFTag;
        uint32 latestFTime;
        // 256 bits, bundled since in settle they will be used together
        uint64 kIM;
        uint64 kMM;
        uint128 OI;
        // if takerFee / otcFee is read, hardOICap is also read
        uint128 hardOICap;
        uint64 takerFee;
        uint64 otcFee;
        // 224 bits
        address markRateOracle;
        int16 loUpperConstBase1e4;
        int16 loUpperSlopeBase1e4;
        int16 loLowerConstBase1e4;
        int16 loLowerSlopeBase1e4;
        //
        MarketImpliedRate impliedRate; // 208 bits
        bool useImpliedAsMarkRate;
        //
        mapping(FTag => FIndex) fTagToIndex;
        // not used on hot path
        LiqSettings liqSettings;
        address fIndexOracle;
        // not used on hot path
        string name;
        string symbol;
    }

    struct MarketImmutableDataStruct {
        string name;
        string symbol;
        //
        bool k_isIsolatedOnly; // 8
        uint32 k_maturity; // 32
        TokenId k_tokenId; // 16
        MarketId k_marketId; // 24
        uint8 k_tickStep; // 8
        uint16 k_iTickThresh; // 16
        // Sum = 104
    }

    struct MarketConfigStruct {
        uint16 maxOpenOrders;
        //
        address markRateOracle;
        address fIndexOracle;
        //
        uint128 hardOICap;
        //
        uint64 takerFee;
        uint64 otcFee;
        //
        LiqSettings liqSettings;
        //
        uint64 kIM;
        uint64 kMM;
        uint32 tThresh;
        uint16 maxRateDeviationFactorBase1e4;
        uint16 closingOrderBoundBase1e4;
        //
        int16 loUpperConstBase1e4;
        int16 loUpperSlopeBase1e4;
        int16 loLowerConstBase1e4;
        int16 loLowerSlopeBase1e4;
        //
        MarketStatus status;
        bool useImpliedAsMarkRate;
    }

    // ---------- In-memory state ----------
    struct UserMem {
        MarketAcc addr;
        OrderId[] longIds;
        OrderId[] shortIds;
        FTag fTag;
        int256 preSettleSize;
        int256 postSettleSize;
        int256 signedSize;
        PMDataMem pmData;
    }

    struct MarketMem {
        // write data
        int256 OI;
        int256 origOI;
        // view data
        MarketStatus status;
        uint32 k_maturity;
        uint8 k_tickStep;
        uint256 k_iThresh;
        uint32 tThresh;
        FTag latestFTag;
        uint32 latestFTime;
        uint32 timeToMat;
        int256 rMark;
    }

    // ---------- Market config subtypes ----------

    struct LiqSettings {
        uint64 base;
        uint64 slope;
        uint64 feeRate;
    }

    // ---------- Account related ----------

    struct AccountState {
        AccountData2 data2; // 192 bits
        uint24 delevLiqNonce;
        bool exemptCLOCheck;
        //
        uint64 kIM;
        uint64 kMM;
        uint64 takerDisc;
        uint64 otcDisc;
        //
        StoredOrderIdArr orderIds;
        uint128 sumLongSize;
        uint128 sumLongPM;
        uint128 sumShortSize;
        uint128 sumShortPM;
        PartialData partialData;
    }

    // ---------- Order related ----------
    struct Order {
        OrderStatus status;
        OrderId id;
        MarketAcc maker;
        uint256 size;
        int256 rate;
    }
}

interface IMarketAllEventsAndTypes is IMarketAllTypes {
    event PersonalMarginConfigUpdated(MarketAcc indexed user, uint64 newKIM, uint64 newKMM);

    event PersonalDiscRatesUpdated(MarketAcc indexed user, uint64 newTakerDisc, uint64 newOtcDisc);

    event PersonalExemptCLOCheckUpdated(MarketAcc user, bool exemptCLOCheck);

    event ImpliedRateObservationWindowUpdated(uint32 newWindow);

    event MaxOpenOrdersUpdated(uint16 newMaxOpenOrders);

    event OracleAddressesUpdated(address newMarkRateOracle, address newFIndexOracle);

    event OICapUpdated(uint128 newHardOICap);

    event FeeRatesUpdated(uint64 newTakerFee, uint64 newOtcFee);

    event LiquidationSettingsUpdated(LiqSettings newLiqSettings);

    event MarginConfigUpdated(uint64 newKIM, uint64 newKMM, uint64 newTThresh);

    event RateBoundConfigUpdated(uint16 newMaxRateDeviationFactorBase1e4, uint16 newClosingOrderBoundBase1e4);

    event LimitOrderConfigUpdated(
        int16 loUpperConstBase1e4,
        int16 loUpperSlopeBase1e4,
        int16 loLowerConstBase1e4,
        int16 loLowerSlopeBase1e4
    );

    event StatusUpdated(MarketStatus newStatus);

    event FIndexUpdated(FIndex newIndex, FTag newFTag);

    event FTagUpdatedOnPurge(FIndex newIndex, FTag newFTag);

    event PaymentFromSettlement(MarketAcc user, uint256 lastFTime, uint256 latestFTime, int256 payment, uint256 fees);

    event LimitOrderPlaced(MarketAcc maker, OrderId[] orderIds, uint256[] sizes);

    event LimitOrderCancelled(OrderId[] orderIds);

    event LimitOrderForcedCancelled(OrderId[] orderIds);

    event LimitOrderPartiallyFilled(OrderId orderId, uint256 filledSize);

    event LimitOrderFilled(OrderId from, OrderId to);

    event OobOrdersPurged(OrderId from, OrderId to);

    event MarketOrdersFilled(MarketAcc user, Trade totalTrade, uint256 totalFees);

    event OtcSwap(MarketAcc user, MarketAcc counterParty, Trade trade, int256 cashToCounter, uint256 otcFee);

    event Liquidate(MarketAcc liq, MarketAcc vio, Trade liqTrade, uint256 liqFee);

    event ForceDeleverage(MarketAcc win, MarketAcc lose, Trade delevTrade);
}

interface IMarketOrderAndOtc is IMarketAllEventsAndTypes {
    function orderAndOtc(
        MarketAcc userAddr,
        LongShort memory orders,
        CancelData memory cancels,
        OTCTrade[] memory OTCs,
        int256 critHR
    ) external returns (UserResult memory userRes, OTCResult[] memory otcRes);
}

interface IMarketEntry is IMarketAllEventsAndTypes {
    function cancel(
        MarketAcc userAddr,
        CancelData memory cancelData,
        bool isForceCancel
    ) external returns (PayFee settle, OrderId[] memory removedIds);

    function liquidate(
        MarketAcc liqAddr,
        MarketAcc vioAddr,
        int256 sizeToLiq,
        int256 vioHealthRatio,
        int256 critHR
    ) external returns (LiqResult memory res);

    function settleAndGet(
        MarketAcc user,
        GetRequest getType
    ) external returns (VMResult res, PayFee payFee, int256 signedSize, uint256 nOrders);

    /// Get up to `maxNTicks` ticks that is strictly after `limitTick` in the sweep direction of `side`.
    /// @param limitTick The tick to start from. Pass in `side.tickToGetFirstAvail()` to get from the first available tick.
    function getNextNTicks(
        Side side,
        int16 limitTick,
        uint256 maxNTicks
    ) external view returns (int16[] memory ticks, uint256[] memory tickSizes);

    function descriptor()
        external
        view
        returns (
            bool isIsolatedOnly,
            TokenId tokenId,
            MarketId marketId,
            uint32 maturity,
            uint8 tickStep,
            uint16 iTickThresh,
            uint32 latestFTime
        );

    function getLatestFIndex() external view returns (FIndex);

    function getLatestFTime() external view returns (uint32);

    function getDelevLiqNonce(MarketAcc user) external view returns (uint24);

    function getBestFeeRates(
        MarketAcc user,
        MarketAcc otcCounter
    ) external view returns (uint64 takerFee, uint64 otcFee);

    function getImpliedRate()
        external
        view
        returns (int128 lastTradedRate, int128 oracleRate, uint32 lastTradedTime, uint32 observationWindow);

    function getMarkRate() external returns (int256);
}

interface IMarketSetting is IMarketAllEventsAndTypes {
    function initialize(
        MarketImmutableDataStruct memory initialImmData,
        MarketConfigStruct memory initialConfig,
        MarketImpliedRateLib.InitStruct memory impliedRateInit
    ) external;

    function setPersonalMarginConfig(MarketAcc user, uint64 newKIM, uint64 newKMM) external;

    function setPersonalDiscRates(MarketAcc user, uint64 newTakerDisc, uint64 newOtcDisc) external;

    function setPersonalExemptCLOCheck(MarketAcc user, bool exemptCLOCheck) external;

    function setGlobalImpliedWindow(uint32 newWindow) external;

    function setGlobalMaxOpenOrders(uint16 newMaxOpenOrders) external;

    function setGlobalOracleAddresses(address newMarkRateOracle, address newFIndexOracle) external;

    function setGlobalHardOICap(uint128 newHardOICap) external;

    function setGlobalFeeRates(uint64 newTakerFee, uint64 newOtcFee) external;

    function setGlobalLiquidationSettings(LiqSettings memory newLiqSettings) external;

    function setGlobalMarginConfig(uint64 newKIM, uint64 newKMM, uint32 newTThresh) external;

    function setGlobalRateBoundConfig(
        uint16 newMaxRateDeviationFactorBase1e4,
        uint16 newClosingOrderBoundBase1e4
    ) external;

    function setGlobalLimitOrderConfig(
        int16 loUpperConstBase1e4,
        int16 loUpperSlopeBase1e4,
        int16 loLowerConstBase1e4,
        int16 loLowerSlopeBase1e4
    ) external;

    function setGlobalStatus(MarketStatus newStatus) external;

    function updateFIndex(FIndex newIndex) external;
}

interface IMarketRiskManagement is IMarketAllEventsAndTypes {
    function forceDeleverage(
        MarketAcc winAddr,
        MarketAcc loseAddr,
        int256 sizeToWin,
        int256 loseValue,
        uint256 alpha
    ) external returns (DelevResult memory res);

    function forcePurgeOobOrders(
        uint256 maxNTicksPurgeOneSide
    ) external returns (uint256 nTicksPurgedLong, uint256 nTicksPurgedShort);
}

// solhint-disable-next-line no-empty-blocks
interface IMarket is IMarketOrderAndOtc, IMarketEntry, IMarketSetting, IMarketRiskManagement {}

interface IMarketOffViewOnly is IMarketAllEventsAndTypes {
    function marketHub() external view returns (address);

    function getMarkRateView() external view returns (int256);

    function getOI() external view returns (uint256);

    function getTickSumSize(Side side, int16 fromTick, int16 toTick) external view returns (uint256[] memory sizes);

    function getPendingSizes(MarketAcc user) external view returns (uint256 pendingLongSize, uint256 pendingShortSize);

    function getAllOpenOrders(MarketAcc user) external view returns (Order[] memory);

    function getOrder(OrderId id) external view returns (Order memory order);

    function calcPositionValueNoSettle(MarketAcc user) external view returns (int256);

    function calcMarginNoSettle(MarketAcc user, MarginType marginType) external view returns (uint256);

    function calcLiqTradeNoSettle(
        MarketAcc vioAddr,
        int256 sizeToLiq,
        int256 vioHealthRatio
    ) external view returns (Trade liqTrade);

    function getSignedSizeNoSettle(MarketAcc user) external view returns (int256);

    function getMarketConfig() external view returns (MarketConfigStruct memory);

    function getDiscRates(MarketAcc user) external view returns (uint64 takerDisc, uint64 otcDisc);

    function getMarginFactor(MarketAcc user) external view returns (uint64 kIM, uint64 kMM);

    function getExemptCLOCheck(MarketAcc user) external view returns (bool exemptCLOCheck);

    function name() external view returns (string memory);

    function symbol() external view returns (string memory);
}

// solhint-disable-next-line no-empty-blocks
interface IMarketOff is IMarket, IMarketOffViewOnly {}
