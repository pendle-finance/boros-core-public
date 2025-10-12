// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IMarketRiskManagement} from "../../interfaces/IMarket.sol";

import {MarketInfoAndState} from "./core/MarketInfoAndState.sol";
import {CoreStateUtils} from "./core/CoreStateUtils.sol";
import {CoreOrderUtils} from "./core/CoreOrderUtils.sol";
import {LiquidationViewUtils} from "./margin/LiquidationViewUtils.sol";

import {MarketAcc} from "../../types/Account.sol";
import {FTag, DelevResult, PayFee} from "../../types/MarketTypes.sol";
import {Side} from "../../types/Order.sol";

import {Err} from "../../lib/Errors.sol";

contract MarketRiskManagement is IMarketRiskManagement, CoreOrderUtils, CoreStateUtils, LiquidationViewUtils {
    uint256 public constant VERSION = 2;

    constructor(address marketHub_) MarketInfoAndState(marketHub_) {
        _disableInitializers();
    }

    function forceDeleverage(
        MarketAcc winAddr,
        MarketAcc loseAddr,
        int256 sizeToWin,
        int256 loseValue,
        uint256 alpha
    ) external onlyMarketHub returns (DelevResult memory res) {
        require(winAddr != loseAddr, Err.MarketInvalidDeleverage());

        MarketMem memory market = _readMarket({checkPause: NO, checkMaturity: YES});
        (UserMem memory win, PayFee winSettle) = _initUser(winAddr, market);
        (UserMem memory lose, PayFee loseSettle) = _initUser(loseAddr, market);

        res.winSettle = winSettle;
        res.loseSettle = loseSettle;

        require(_isReducedOnly(win.signedSize, sizeToWin), Err.MarketInvalidDeleverage());
        require(_isReducedOnly(lose.signedSize, -sizeToWin), Err.MarketInvalidDeleverage());

        _coreRemoveAllAft(market, lose, true);

        // no OTC fee
        res.delevTrade = _calcDelevTradeAft(market, lose, sizeToWin, loseValue, alpha);
        (res.winPayment, res.losePayment) = _mergeOTCAft(win, lose, market, res.delevTrade, 0, 0);

        _incDelevLiqNonce(winAddr);
        _incDelevLiqNonce(loseAddr);

        _writeUserNoCheck(win, market);
        _writeUserNoCheck(lose, market);
        _writeMarketSkipOICheck(market);

        emit ForceDeleverage(winAddr, loseAddr, res.delevTrade);

        return res;
    }

    function forcePurgeOobOrders(
        uint256 maxNTicksPurgeOneSide
    ) external onlyMarketHub returns (uint256 /*nTicksPurgedLong*/, uint256 /*nTicksPurgedShort*/) {
        MarketMem memory market = _readMarket({checkPause: NO, checkMaturity: YES});

        FTag purgeTag = market.latestFTag.nextPurgeTag();

        uint256 nTicksPurgedLong = _bookPurgeOob(
            market.k_tickStep,
            _calcRateBound(market, Side.LONG),
            purgeTag,
            Side.LONG,
            maxNTicksPurgeOneSide
        );
        uint256 nTicksPurgedShort = _bookPurgeOob(
            market.k_tickStep,
            _calcRateBound(market, Side.SHORT),
            purgeTag,
            Side.SHORT,
            maxNTicksPurgeOneSide
        );
        if (nTicksPurgedLong == 0 && nTicksPurgedShort == 0) return (0, 0);

        _updateFTagOnPurge(purgeTag, _toFIndex(market.latestFTag));
        _writeMarketSkipOICheck(market);
        return (nTicksPurgedLong, nTicksPurgedShort);
    }
}
