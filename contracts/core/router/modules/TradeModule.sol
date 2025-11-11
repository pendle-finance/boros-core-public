// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

// OpenZeppelin Imports
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// Core & Library Imports
import {PMath} from "../../../lib/math/PMath.sol";

// Interface Imports
import {ITradeModule} from "../../../interfaces/ITradeModule.sol";

// Type Imports
import {MarketAcc, Account, AccountLib} from "../../../types/Account.sol";
import {Trade} from "../../../types/Trade.sol";
import {BulkOrderResult, CancelData, TokenId, MarketId} from "../../../types/MarketTypes.sol";

// Router & Math Imports
import {RouterAccountBase} from "../auth-base/RouterAccountBase.sol";
import {BookAmmSwapBase} from "../trade-base/BookAmmSwapBase.sol";
import {Err} from "../../../lib/Errors.sol";

// * All functions in here are meant to be called both directly or called by Pendle's relayer. For details look it AuthModule.sol
contract TradeModule is ITradeModule, RouterAccountBase, BookAmmSwapBase {
    using AccountLib for address;
    using SafeERC20 for IERC20;
    using PMath for uint256;

    constructor(address marketHub_) BookAmmSwapBase(marketHub_) {}

    function vaultDeposit(uint8 accountIdRcv, TokenId tokenId, MarketId marketId, uint256 amount) external setNonAuth {
        Account account = _account();
        require(account.isMain(), Err.TradeOnlyMainAccount());

        MarketAcc acc = AccountLib.from(account.root(), accountIdRcv, tokenId, marketId);

        address token = _MARKET_HUB.tokenIdToAddress(tokenId);
        IERC20(token).safeTransferFrom(acc.root(), address(this), amount);

        _MARKET_HUB.vaultDeposit(acc, amount);
    }

    function vaultPayTreasury(TokenId tokenId, uint256 amount) external setNonAuth {
        Account account = _account();
        require(account.isMain(), Err.TradeOnlyMainAccount());

        address root = account.root();
        address token = _MARKET_HUB.tokenIdToAddress(tokenId);
        IERC20(token).safeTransferFrom(root, address(this), amount);

        _MARKET_HUB.vaultPayTreasury(root, tokenId, amount);
    }

    function requestVaultWithdrawal(TokenId tokenId, uint256 amount) external setNonAuth {
        Account account = _account();
        require(account.isMain(), Err.TradeOnlyMainAccount());

        address root = account.root();

        _MARKET_HUB.requestVaultWithdrawal(root, tokenId, amount);
    }

    function cancelVaultWithdrawal(TokenId tokenId) external setNonAuth {
        Account account = _account();
        require(account.isMain(), Err.TradeOnlyMainAccount());

        address root = account.root();

        _MARKET_HUB.cancelVaultWithdrawal(root, tokenId);
    }

    function subaccountTransfer(
        uint8 accountId,
        TokenId tokenId,
        MarketId marketId,
        uint256 amount,
        bool isDeposit
    ) external setNonAuth {
        Account account = _account();
        require(account.isMain(), Err.TradeOnlyMainAccount());

        MarketAcc subaccount = AccountLib.from(account.root(), accountId, tokenId, marketId);

        int256 signedAmount = isDeposit ? amount.Int() : amount.neg();
        _MARKET_HUB.cashTransfer(account.toCross(tokenId), subaccount, signedAmount);
    }

    // --- Agent signed txn ---

    // * Cash transfer is only used for isolated margin funding
    function cashTransfer(CashTransferReq memory req) external setNonAuth {
        MarketCache memory cache = _getMarketCache(req.marketId);
        MarketAcc user = _account().toIsolated(cache.tokenId, req.marketId);
        _MARKET_HUB.cashTransfer(user.toCross(), user, req.signedAmount);
    }

    function ammCashTransfer(AMMCashTransferReq memory req) external setNonAuth {
        Account account = _account();
        require(account.isAMM(), Err.TradeOnlyAMMAccount());

        MarketCache memory cache = _getMarketCache(req.marketId);
        MarketAcc mainCross = account.root().toMainCross(cache.tokenId);
        MarketAcc ammIsolated = account.root().toAmmAcc(cache.tokenId, req.marketId);

        if (req.cashIn != 0) {
            _MARKET_HUB.cashTransfer(mainCross, ammIsolated, req.cashIn.Int());
        }

        if (req.cashTransferAll) {
            _MARKET_HUB.cashTransferAll(ammIsolated, mainCross);
        }
    }

    function payTreasury(PayTreasuryReq memory req) external setNonAuth {
        MarketCache memory cache = _getMarketCache(req.marketId);
        MarketAcc user = _account().toMarketAcc(req.cross, cache.tokenId, req.marketId);
        _MARKET_HUB.payTreasury(user, req.amount);
    }

    /*
     * Mostly used for UI, allowing users to bundle several actions together
     */
    function placeSingleOrder(
        SingleOrderReq memory req
    ) external setNonAuth returns (Trade matched, uint256 takerOtcFee, int256 cashWithdrawn) {
        OrderReq memory order = req.order;
        MarketId marketId = order.marketId;

        MarketCache memory cache = _getMarketCache(marketId);

        MarketAcc user = _account().toMarketAcc(order.cross, cache.tokenId, marketId);

        if (req.isolated_cashIn != 0) {
            require(order.cross == false, Err.TradeOnlyForIsolated());
            _MARKET_HUB.cashTransfer(user.toCross(), user, req.isolated_cashIn.Int());
        }

        if (req.enterMarket) {
            _MARKET_HUB.enterMarket(user, marketId);
        }

        (matched, takerOtcFee) = _executeSingleOrder(cache, user, order, req.idToStrictCancel, req.desiredMatchRate);

        if (req.exitMarket) {
            _MARKET_HUB.exitMarket(user, marketId);
        }

        if (req.isolated_cashTransferAll) {
            require(order.cross == false, Err.TradeOnlyForIsolated());
            cashWithdrawn = _MARKET_HUB.cashTransferAll(user, user.toCross());
        }

        emit SingleOrderExecuted(user, marketId, order.ammId, order.tif, matched, takerOtcFee);
    }

    function bulkCancels(BulkCancels memory req) external setNonAuth {
        MarketCache memory cache = _getMarketCache(req.marketId);
        MarketAcc user = _account().toMarketAcc(req.cross, cache.tokenId, req.marketId);

        CancelData memory cancelData = CancelData({ids: req.orderIds, isAll: req.cancelAll, isStrict: false});

        _MARKET_HUB.cancel(req.marketId, user, cancelData);
    }

    // * Used almost exclusively for market makers, and doesn't involve any swaps with AMMs
    function bulkOrders(BulkOrdersReq memory req) external setNonAuth returns (BulkOrderResult[] memory results) {
        require(req.bulks.length > 0, Err.InvalidLength());
        require(req.bulks.length == req.desiredMatchRates.length, Err.InvalidLength());

        MarketId firstMarketId = req.bulks[0].marketId;
        MarketCache memory cache = _getMarketCache(firstMarketId);
        MarketAcc user = _account().toMarketAcc(req.cross, cache.tokenId, firstMarketId);

        results = _MARKET_HUB.bulkOrders(user, req.bulks);
        for (uint256 i = 0; i < req.bulks.length; ++i) {
            results[i].matched.requireDesiredSideAndRate(req.bulks[i].orders.side, req.desiredMatchRates[i]);
            emit BulkOrdersExecuted(
                user,
                req.bulks[i].marketId,
                req.bulks[i].orders.tif,
                results[i].matched,
                results[i].takerFee
            );
        }
    }

    // * Allow entering & exiting multiple markets at once
    function enterExitMarkets(EnterExitMarketsReq memory req) external setNonAuth {
        Account account = _account();
        for (uint256 i = 0; i < req.marketIds.length; i++) {
            MarketId marketId = req.marketIds[i];
            MarketCache memory cache = _getMarketCache(marketId);

            MarketAcc user = account.toMarketAcc(req.cross, cache.tokenId, marketId);
            if (req.isEnter) {
                _MARKET_HUB.enterMarket(user, marketId);
            } else {
                _MARKET_HUB.exitMarket(user, marketId);
            }
        }
    }
}
