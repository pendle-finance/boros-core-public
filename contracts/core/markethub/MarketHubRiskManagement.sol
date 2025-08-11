// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IMarketHubRiskManagement} from "../../interfaces/IMarketHub.sol";
import {IMarket} from "../../interfaces/IMarket.sol";

import {MarginManager} from "./MarginManager.sol";
import {Storage} from "./Storage.sol";

import {MarketId, MarketAcc, CancelData, DelevResult, PayFee, Trade} from "../../types/MarketTypes.sol";

import {Err} from "../../lib/Errors.sol";

contract MarketHubRiskManagement is IMarketHubRiskManagement, MarginManager {
    constructor(
        address _permissionController,
        address _marketFactory,
        address _router,
        address _treasury,
        uint256 _maxEnteredMarkets
    ) Storage(_permissionController, _marketFactory, _router, _treasury, _maxEnteredMarkets) {
        _disableInitializers();
    }

    function forceCancel(MarketId marketId, MarketAcc user, CancelData memory cancelData) external onlyAuthorized {
        _checkEnteredMarkets(user, marketId);
        address market = _marketIdToAddrRaw(marketId);
        (PayFee payFee, ) = IMarket(market).cancel(user, cancelData, true);
        _processPayFee(user, payFee);
    }

    function forceDeleverage(
        MarketId marketId,
        MarketAcc win,
        MarketAcc lose,
        int256 sizeToWin,
        uint256 alpha
    ) external onlyAuthorized returns (Trade /*delevTrade*/) {
        _checkEnteredMarkets(win, marketId);
        _checkEnteredMarkets(lose, marketId);

        int256 loseValue = _settleProcessGetTotalValue(lose);

        address market = _marketIdToAddrRaw(marketId);
        DelevResult memory res = IMarket(market).forceDeleverage(win, lose, sizeToWin, loseValue, alpha);

        _processPayFee(win, res.winSettle + res.winPayment);
        _processPayFee(lose, res.loseSettle + res.losePayment);

        return res.delevTrade;
    }

    function forcePurgeOobOrders(
        MarketId[] memory marketIds,
        uint256 maxNTicksPurgeOneSide
    ) external onlyAuthorized returns (uint256 totalTicksPurgedLong, uint256 totalTicksPurgedShort) {
        for (uint256 i = 0; i < marketIds.length; i++) {
            address market = _marketIdToAddrChecked(marketIds[i]);
            (uint256 nTicksLong, uint256 nTicksShort) = IMarket(market).forcePurgeOobOrders(maxNTicksPurgeOneSide);
            totalTicksPurgedLong += nTicksLong;
            totalTicksPurgedShort += nTicksShort;
        }
    }

    function forceCancelAllRiskyUser(MarketAcc riskyUser, MarketId[] memory marketIds) external onlyAuthorized {
        require(!_settleProcessCheckHRAboveThres(riskyUser, riskyThresHR), Err.MMHealthNonRisky());

        CancelData memory cancelData;
        cancelData.isAll = true;

        for (uint256 i = 0; i < marketIds.length; i++) {
            _checkEnteredMarkets(riskyUser, marketIds[i]);
            address market = _marketIdToAddrRaw(marketIds[i]);
            (PayFee payFee, ) = IMarket(market).cancel(riskyUser, cancelData, true);
            _processPayFee(riskyUser, payFee);
        }
    }
}
