// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {GeneratedStorageSlots} from "./../../../generated/slots.sol";
import {Err} from "./../../../lib/Errors.sol";
import {IMarketHub} from "./../../../interfaces/IMarketHub.sol";
import {IMarket} from "./../../../interfaces/IMarket.sol";
import {IRouterEventsAndTypes} from "./../../../interfaces/IRouterEventsAndTypes.sol";
import {MarketAcc} from "./../../../types/Account.sol";
import {AMMId, MarketId} from "./../../../types/MarketTypes.sol";

abstract contract TradeStorage is IRouterEventsAndTypes {
    struct TradeStorageStruct {
        mapping(MarketId marketId => MarketCache cache) marketIdCache;
        mapping(AMMId ammId => MarketAcc amm) ammIdToAcc;
        uint16 numTicksToTryAtOnce;
        uint256 maxIterationAddLiquidity;
        uint256 epsAddLiquidity;
    }

    IMarketHub internal immutable _MARKET_HUB;

    constructor(address _marketHub) {
        _MARKET_HUB = IMarketHub(_marketHub);
    }

    function _getTradeStorage() private pure returns (TradeStorageStruct storage $) {
        bytes32 slot = GeneratedStorageSlots.ROUTER_TRADE_STORAGE_LOCATION;
        assembly {
            $.slot := slot
        }
    }

    function _getMarketCache(MarketId marketId) internal returns (MarketCache memory cache) {
        TradeStorageStruct storage $ = _getTradeStorage();
        cache = $.marketIdCache[marketId];
        if (cache.market == address(0)) {
            cache.market = _MARKET_HUB.marketIdToAddress(marketId);
            (, cache.tokenId, , cache.maturity, cache.tickStep, , ) = IMarket(cache.market).descriptor();
            $.marketIdCache[marketId] = cache;
        }
        return cache;
    }

    function _setAMMIdToAcc(AMMId ammId, MarketAcc amm, bool forceOverride) internal {
        require(_getTradeStorage().ammIdToAcc[ammId].isZero() || forceOverride, Err.TradeAMMAlreadySet());
        _getTradeStorage().ammIdToAcc[ammId] = amm;
    }

    function _getAMMIdToAcc(AMMId ammId) internal view returns (MarketAcc amm) {
        amm = _getTradeStorage().ammIdToAcc[ammId];
        require(!amm.isZero(), Err.AMMNotFound());
    }

    function _setNumTicksToTryAtOnce(uint16 newNumTicksToTryAtOnce) internal {
        _getTradeStorage().numTicksToTryAtOnce = newNumTicksToTryAtOnce;
    }

    function _getNumTicksToTryAtOnce() internal view returns (uint16) {
        return _getTradeStorage().numTicksToTryAtOnce;
    }

    function _setMaxIterationAddLiquidity(uint256 newMaxIteration) internal {
        _getTradeStorage().maxIterationAddLiquidity = newMaxIteration;
    }

    function _getMaxIterationAddLiquidity() internal view returns (uint256) {
        return _getTradeStorage().maxIterationAddLiquidity;
    }

    function _setEpsAddLiquidity(uint256 newEps) internal {
        _getTradeStorage().epsAddLiquidity = newEps;
    }

    function _getEpsAddLiquidity() internal view returns (uint256) {
        return _getTradeStorage().epsAddLiquidity;
    }
}
