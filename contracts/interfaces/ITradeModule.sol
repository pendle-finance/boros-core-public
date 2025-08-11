// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {BulkOrderResult, TokenId, MarketId} from "./../types/MarketTypes.sol";
import {Trade} from "./../types/Trade.sol";
import {IRouterEventsAndTypes} from "./IRouterEventsAndTypes.sol";

interface ITradeModule is IRouterEventsAndTypes {
    function vaultDeposit(uint8 accountId, TokenId tokenId, MarketId marketId, uint256 amount) external;

    function vaultPayTreasury(TokenId tokenId, uint256 amount) external;

    function requestVaultWithdrawal(TokenId tokenId, uint256 amount) external;

    function cancelVaultWithdrawal(TokenId tokenId) external;

    function subaccountTransfer(
        uint8 accountId,
        TokenId tokenId,
        MarketId marketId,
        uint256 amount,
        bool isDeposit
    ) external;

    function cashTransfer(CashTransferReq memory transfer) external;

    function ammCashTransfer(AMMCashTransferReq memory req) external;

    function payTreasury(PayTreasuryReq memory req) external;

    function placeSingleOrder(
        SingleOrderReq memory req
    ) external returns (Trade matched, uint256 takerOtcFee, int256 cashWithdrawn);

    function bulkOrders(BulkOrdersReq memory req) external returns (BulkOrderResult[] memory results);

    function bulkCancels(BulkCancels memory req) external;

    function enterExitMarkets(EnterExitMarketsReq memory req) external;
}
