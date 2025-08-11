// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {MarketAcc} from "./../types/Account.sol";
import {
    BulkOrder,
    BulkOrderResult,
    CancelData,
    LongShort,
    OTCTrade,
    VMResult,
    GetRequest,
    TokenId,
    MarketId
} from "./../types/MarketTypes.sol";
import {Trade} from "./../types/Trade.sol";

interface IMarketHubAllEventsAndTypes {
    struct TokenData {
        address token;
        uint96 scalingFactor;
    }

    struct Withdrawal {
        uint32 start;
        uint224 unscaled;
    }

    struct CashFeeData {
        uint128 treasuryCash;
        uint128 marketEntranceFee;
        //
        uint128 minCashCross;
        uint128 minCashIsolated;
    }

    struct MarketAccData {
        int256 cash;
        mapping(MarketId => bool) hasEnteredMarketBefore;
        MarketId[] enteredMarkets;
    }

    event EnterMarket(MarketAcc user, MarketId marketId, uint256 entranceFee);

    event ExitMarket(MarketAcc user, MarketId marketId);

    event VaultDeposit(MarketAcc acc, uint256 unscaledAmount);

    event VaultWithdrawalRequested(address root, TokenId tokenId, uint32 start, uint256 totalUnscaledAmount);

    event VaultWithdrawalCanceled(address root, TokenId tokenId, uint256 totalUnscaledAmount);

    event VaultWithdrawalFinalized(address root, TokenId tokenId, uint256 totalUnscaledAmount);

    event PersonalCooldownSet(address root, uint32 cooldown);

    event CashTransfer(MarketAcc from, MarketAcc to, int256 amount);

    event PayTreasury(MarketAcc user, uint256 amount);

    event TokenAdded(TokenId indexed tokenId, address indexed tokenAddress);

    event MarketAdded(MarketId indexed marketId, address indexed marketAddress);

    event GlobalCooldownSet(uint32 newCooldown);

    event CollectFee(TokenId indexed tokenId, uint256 amount);

    event CritHRUpdated(int256 newCritHR);

    event RiskyThresHRUpdated(int256 newRiskyThresHR);

    event StrictHealthCheckUpdated(MarketId marketId, bool isEnabled);

    event MinCashCrossAccountsUpdated(TokenId[] tokenIds, uint128[] newMinCash);

    event MinCashIsolatedAccountsUpdated(TokenId[] tokenIds, uint128[] newMinCash);

    event MarketEntranceFeesUpdated(TokenId[] tokenIds, uint128[] entranceFees);
}

interface IMarketHubStorageOnly is IMarketHubAllEventsAndTypes {
    function MARKET_FACTORY() external view returns (address);

    function ROUTER() external view returns (address);

    function TREASURY() external view returns (address);

    function MAX_ENTERED_MARKETS() external view returns (uint256);

    function critHR() external view returns (int128);

    function riskyThresHR() external view returns (int256);

    function globalCooldown() external view returns (uint32);
}

interface IMarketHubSetAndView is IMarketHubAllEventsAndTypes {
    function getEnteredMarkets(MarketAcc user) external view returns (MarketId[] memory);

    function getStrictMarkets() external view returns (MarketId[] memory);

    function marketIdToAddress(MarketId marketId) external view returns (address);

    function tokenIdToAddress(TokenId tokenId) external view returns (address);

    function tokenData(TokenId tokenId) external view returns (TokenData memory);

    function getPersonalCooldown(address userAddr) external view returns (uint32);

    function getUserWithdrawalStatus(address userAddr, TokenId tokenId) external view returns (Withdrawal memory);

    function accCash(MarketAcc user) external view returns (int256);

    function getCashFeeData(TokenId tokenId) external view returns (CashFeeData memory);

    function hasEnteredMarketBefore(MarketAcc user, MarketId marketId) external view returns (bool);

    function registerToken(address token) external returns (TokenId newTokenId);

    function registerMarket(address[] memory markets) external;

    function withdrawTreasury(TokenId[] memory tokenIds) external;

    function setCritHR(int128 newCritHR) external;

    function setRiskyThresHR(int256 newRiskyThresHR) external;

    function setMinCashForAccounts(bool isCross, TokenId[] memory tokenIds, uint128[] memory newMinCash) external;

    function setMarketEntranceFees(TokenId[] memory tokenIds, uint128[] memory entranceFees) external;

    function enableStrictHealthCheck(MarketId marketId) external;

    function disableStrictHealthCheck(MarketId marketId) external;

    function setGlobalCooldown(uint32 newCooldown) external;

    // passed in `cooldown = type(uint32).max` to use default cooldown duration
    function setPersonalCooldown(address root, uint32 cooldown) external;
}

interface IMarketHubEntryOnly {
    function initialize(uint32 globalCooldown) external;

    function enterMarket(MarketAcc user, MarketId marketId) external;

    function exitMarket(MarketAcc user, MarketId marketId) external;

    function vaultDeposit(MarketAcc acc, uint256 unscaledAmount) external;

    function vaultPayTreasury(address root, TokenId tokenId, uint256 unscaled) external;

    function requestVaultWithdrawal(address root, TokenId tokenId, uint256 unscaledAmount) external;

    function cancelVaultWithdrawal(address root, TokenId tokenId) external;

    function finalizeVaultWithdrawal(address root, TokenId tokenId) external;

    function cashTransfer(MarketAcc from, MarketAcc to, int256 amount) external;

    function cashTransferAll(MarketAcc from, MarketAcc to) external returns (int256 amountOut);

    function payTreasury(MarketAcc user, uint256 amount) external;

    function simulateTransfer(MarketAcc acc, int256 amount) external;

    function orderAndOtc(
        MarketId marketId,
        MarketAcc user,
        LongShort memory orders,
        CancelData memory cancelData,
        OTCTrade[] memory OTCs
    ) external returns (Trade bookMatched, uint256 totalTakerOtcFee);

    function bulkOrders(MarketAcc user, BulkOrder[] memory bulks) external returns (BulkOrderResult[] memory results);

    function cancel(MarketId marketId, MarketAcc user, CancelData memory cancelData) external;

    function liquidate(
        MarketId marketId,
        MarketAcc liq,
        MarketAcc vio,
        int256 sizeToLiq
    ) external returns (Trade liqTrade, uint256 liqFee);

    function settleAllAndGet(
        MarketAcc user,
        GetRequest req,
        MarketId marketId
    ) external returns (int256 cash, VMResult totalVM, int256 signedSize);
}

interface IMarketHubRiskManagement {
    function forceCancel(MarketId marketId, MarketAcc user, CancelData memory cancelData) external;

    function forceDeleverage(
        MarketId marketId,
        MarketAcc win,
        MarketAcc lose,
        int256 sizeToWin,
        uint256 alpha
    ) external returns (Trade delevTrade);

    function forcePurgeOobOrders(
        MarketId[] memory marketIds,
        uint256 maxNTicksPurgeOneSide
    ) external returns (uint256 totalTicksPurgedLong, uint256 totalTicksPurgedShort);

    function forceCancelAllRiskyUser(MarketAcc riskyUser, MarketId[] memory marketIds) external;
}

// solhint-disable-next-line no-empty-blocks
interface IMarketHub is IMarketHubStorageOnly, IMarketHubSetAndView, IMarketHubEntryOnly, IMarketHubRiskManagement {}
