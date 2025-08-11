// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

// Libraries
import {Err} from "../../../lib/Errors.sol";
import {PMath} from "../../../lib/math/PMath.sol";
import {TickMath} from "../../../lib/math/TickMath.sol";

// Types
import {MarketAcc, AccountLib} from "../../../types/Account.sol";
import {
    AccountData2Lib,
    Fill,
    FTag,
    LongShort,
    PartialData,
    PayFee,
    VMResult,
    GetRequest
} from "../../../types/MarketTypes.sol";
import {OrderId, Side} from "../../../types/Order.sol";

// Core
import {PendingOIPureUtils} from "../settle/PendingOIPureUtils.sol";
import {SweepProcessUtils} from "../settle/SweepProcessUtils.sol";
import {RateUtils} from "./RateUtils.sol";

abstract contract CoreStateUtils is PendingOIPureUtils, RateUtils, SweepProcessUtils {
    enum CLOCheck {
        YES,
        SKIP
    }

    using PMath for int256;
    using PMath for uint256;

    function _initUser(MarketAcc addr, MarketMem memory market) internal returns (UserMem memory user, PayFee settle) {
        _initUserCoreData({user: user, addr: addr, allowShortcut: false});
        settle = _sweepProcess(user, _readAndClearPartial(_accState(addr)), market);
        user.postSettleSize = user.signedSize;
    }

    function _shortcutSettleAndGet(
        MarketAcc addr,
        MarketMem memory market,
        GetRequest getType
    ) internal returns (VMResult /*res*/, PayFee /*settle*/, int256 /*signedSize*/, uint256 /*nOrders*/) {
        AccountState storage $ = _accState(addr);
        UserMem memory user;
        (uint16 nLongOrders, uint16 nShortOrders, bool shortcutted) = _initUserCoreData({
            user: user,
            addr: addr,
            allowShortcut: true
        });

        PayFee settle = _sweepProcess(user, _readAndClearPartial($), market);
        user.postSettleSize = user.signedSize;

        VMResult res = _getVMAft(user, market, getType);
        if (shortcutted) {
            // no orders or partial to settle. fTag can still change
            // must not rely on longIds & shortIds in this branch
            $.data2 = AccountData2Lib.from(user.signedSize.Int128(), user.fTag, nLongOrders, nShortOrders);
            return (res, settle, user.signedSize, nLongOrders + nShortOrders);
        } else {
            _writeUserNoCheck(user, market);
            return (res, settle, user.signedSize, user.longIds.length + user.shortIds.length);
        }
    }

    /// @dev The term "shortcut" here means we allow skipping the reading of longIds/shortIds/partialData if none has any
    /// items to settle. The shortcut is used solely for settlement to enable the quickest exit in cases with no orders
    /// to settle.
    function _initUserCoreData(
        UserMem memory user,
        MarketAcc addr,
        bool allowShortcut
    ) internal view returns (uint16 /*nLongOrders*/, uint16 /*nShortOrders*/, bool /*shortcutted*/) {
        AccountState storage $ = _accState(addr);

        user.addr = addr;

        (int128 signedSize, FTag fTag, uint16 nLongOrders, uint16 nShortOrders) = $.data2.unpack();
        user.signedSize = user.preSettleSize = signedSize;
        user.fTag = fTag;

        // Special provision of pmData: If there is no order on that side, we can skip reading pmData since we will
        // also skip writing it to zero if there is no order. This avoids the expensive zero-to-non-zero transition.
        if (nLongOrders > 0) {
            (user.pmData.sumLongSize, user.pmData.sumLongPM) = ($.sumLongSize, $.sumLongPM);
        }
        if (nShortOrders > 0) {
            (user.pmData.sumShortSize, user.pmData.sumShortPM) = ($.sumShortSize, $.sumShortPM);
        }

        if (allowShortcut && !_hasAtLeastOneSettle($, nLongOrders, nShortOrders)) {
            return (nLongOrders, nShortOrders, true);
        }

        // If there is no order, we don't need to read the content of the array.
        if (nLongOrders > 0 || nShortOrders > 0) {
            // If shortcuts are not allowed or there is something to resolve, we read the orders.
            (user.longIds, user.shortIds) = $.orderIds.read(nLongOrders, nShortOrders);
        }

        return (nLongOrders, nShortOrders, false);
    }

    /// @dev we read & clear together since we will immediately settle the user's partial after this
    function _readAndClearPartial(AccountState storage $) internal returns (PartialData memory part) {
        part.copyFromStorageAndClear($.partialData);
    }

    function _hasAtLeastOneSettle(
        AccountState storage $,
        uint16 nLongOrders,
        uint16 nShortOrders
    ) internal view returns (bool) {
        if (nLongOrders > 0) {
            OrderId lastLong = $.orderIds.readLast(Side.LONG, nLongOrders);
            if (_bookCanSettleSkipSizeCheck(lastLong)) return true;
        }

        if (nShortOrders > 0) {
            OrderId lastShort = $.orderIds.readLast(Side.SHORT, nShortOrders);
            if (_bookCanSettleSkipSizeCheck(lastShort)) return true;
        }

        if (nLongOrders > 0 || nShortOrders > 0) {
            if (!$.partialData.isZeroStorage()) return true;
        }

        return false;
    }

    function _getVMAft(
        UserMem memory user,
        MarketMem memory market,
        GetRequest getType
    ) internal view returns (VMResult res) {
        if (getType == GetRequest.IM) {
            res = _getIMAft(market, user);
        } else if (getType == GetRequest.MM) {
            res = _getMMAft(market, user);
        } else {
            assert(getType == GetRequest.ZERO);
        }
    }

    function _writeUser(
        UserMem memory user,
        MarketMem memory market,
        PayFee postPayment,
        LongShort memory orders,
        int256 critHR,
        CLOCheck checkCLO
    ) internal returns (bool /*isStrictIM*/, VMResult /*finalVM*/) {
        (bool onlyClosingOrders, bool isStrictIM, VMResult finalVM) = _checkMargin(
            market,
            user,
            postPayment,
            orders,
            critHR
        );

        if (checkCLO == CLOCheck.YES && market.status == MarketStatus.CLO) {
            require(onlyClosingOrders || _accState(user.addr).exemptCLOCheck, Err.MarketCLO());
        }

        _writeUserNoCheck(user, market);
        return (isStrictIM, finalVM);
    }

    /// @notice For cases where absolutely no checks are needed, like deleverage, or cancel. We will skip CLO check &
    /// margin check
    function _writeUserNoCheck(UserMem memory user, MarketMem memory market) internal {
        assert(!user.addr.isZero());

        AccountState storage $ = _accState(user.addr);

        _updateOIOnUserWrite(user, market);

        $.data2 = AccountData2Lib.from(
            user.signedSize.Int128(),
            user.fTag,
            uint16(user.longIds.length),
            uint16(user.shortIds.length)
        );

        // as explained in _initUserCoreData, we skip writing pmData to zero if there is no order. pmData needs to be interpreted together with nOrders
        if (user.longIds.length > 0 || user.shortIds.length > 0) {
            if (user.longIds.length > 0) {
                ($.sumLongSize, $.sumLongPM) = (user.pmData.sumLongSize.Uint128(), user.pmData.sumLongPM.Uint128());
            }
            if (user.shortIds.length > 0) {
                ($.sumShortSize, $.sumShortPM) = (user.pmData.sumShortSize.Uint128(), user.pmData.sumShortPM.Uint128());
            }
            $.orderIds.write(user.longIds, user.shortIds);
        }

        user.addr = AccountLib.ZERO_MARKET_ACC;
    }

    function _readMarket(bool checkPause, bool checkMaturity) internal returns (MarketMem memory market) {
        market.rMark = _getMarkRate();
        _readMarketExceptMarkRate(market);

        if (checkMaturity) {
            require(!_isMatured(market), Err.MarketMatured());
        }
        if (checkPause) {
            require(market.status != MarketStatus.PAUSED, Err.MarketPaused());
        }
    }

    /// @dev This reading follows ctx structure to minimize sloads. Some variables won't be read here if they are only used selectively in some functions. They will be read directly later on.
    function _readMarketExceptMarkRate(MarketMem memory market) internal view {
        market.OI = market.origOI = uint256(_ctx().OI).Int();
        market.status = _ctx().status;
        market.k_maturity = _ctx().k_maturity;
        market.k_tickStep = _ctx().k_tickStep;
        market.k_iThresh = uint128(TickMath.getRateAtTick(int16(_ctx().k_iTickThresh), market.k_tickStep));
        market.tThresh = _ctx().tThresh;

        market.latestFTag = _ctx().latestFTag;
        market.latestFTime = _ctx().latestFTime;
        bool isMatured = _isMatured(market);

        if (isMatured) {
            market.timeToMat = 0;
            market.tThresh = 0;
        } else {
            market.timeToMat = market.k_maturity - market.latestFTime;
        }
    }

    function _writeMarket(MarketMem memory market) internal {
        require(market.OI <= market.origOI || market.OI.Uint128() <= _ctx().hardOICap, Err.MarketOICapExceeded());
        _writeMarketSkipOICheck(market);
    }

    function _writeMarketSkipOICheck(MarketMem memory market) internal {
        _ctx().OI = market.OI.Uint128();
    }

    function _squashPartial(
        MarketAcc addr,
        Fill partialFill,
        MarketMem memory market
    ) internal returns (bool /*squashed*/) {
        PartialData storage stored = _accState(addr).partialData;
        uint256 partialPM = _calcPMFromFill(market, partialFill);
        return stored.addToStorageIfAllowed(market.latestFTag, partialFill, partialPM.Uint128());
    }
}
