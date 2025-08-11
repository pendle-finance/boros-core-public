// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {MarketAcc} from "./../types/Account.sol";
import {OrderId, Side, TimeInForce} from "./../types/Order.sol";
import {AMMId, MarketId, TokenId} from "./../types/MarketTypes.sol";
import {Trade} from "./../types/Trade.sol";
import {IMarketOff} from "./IMarket.sol";

interface IExplorer {
    struct PositionInfo {
        MarketId marketId;
        int256 signedSize;
        int256 positionValue;
        int256 liquidationApr;
        uint256 initialMargin;
        uint256 maintMargin;
        IMarketOff.Order[] orders;
    }

    struct UserInfo {
        int256 totalCash;
        PositionInfo[] positions;
        int256 availableInitialMargin;
        int256 availableMaintMargin;
    }

    struct MarketInfo {
        string name;
        string symbol;
        bool isIsolatedOnly;
        TokenId tokenId;
        MarketId marketId;
        uint32 maturity;
        uint8 tickStep;
        uint16 iTickThresh;
        bool isMatured;
        int256 impliedApr;
        int256 markApr;
        int256 underlyingApr;
        uint32 nextSettleTime;
    }

    function MARKET_HUB() external view returns (address);

    function ROUTER() external view returns (address);

    function getUserInfo(MarketAcc user) external returns (UserInfo memory userInfo);

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
        returns (UserInfo memory preUserInfo, UserInfo memory postUserInfo, Trade matched, uint256 marginRequired);

    function getUserInfoAfterBulkCancels(
        MarketAcc user,
        MarketId marketId,
        bool cancelAll,
        OrderId[] memory orderIds
    ) external returns (UserInfo memory preUserInfo, UserInfo memory postUserInfo);

    function getMarketInfo(MarketId marketId) external view returns (MarketInfo memory info);

    function getMarketOrderBook(
        MarketId marketId,
        Side side,
        int16 from,
        int16 to
    ) external view returns (uint256[] memory size);
}
