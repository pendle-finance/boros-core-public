// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Account, MarketAcc} from "./../types/Account.sol";
import {AMMId, BulkOrder, MarketId, TokenId} from "./../types/MarketTypes.sol";
import {OrderId, Side, TimeInForce} from "./../types/Order.sol";
import {Trade} from "./../types/Trade.sol";

interface IRouterEventsAndTypes {
    event NewAccManagerSet(Account indexed account, address indexed newAccManager);

    event AgentApproved(Account indexed account, address indexed agent, uint64 indexed expiry);

    event AgentRevoked(Account indexed account, address indexed agent);

    event SingleOrderExecuted(
        MarketAcc indexed user,
        MarketId indexed marketId,
        AMMId indexed ammId,
        TimeInForce tif,
        Trade matched,
        uint256 takerOtcFee
    );

    event BulkOrdersExecuted(
        MarketAcc indexed user,
        MarketId indexed marketId,
        TimeInForce tif,
        Trade matched,
        uint256 takerFee
    );

    event SwapWithAmm(
        MarketAcc indexed user,
        MarketId indexed marketId,
        AMMId indexed ammId,
        Trade matched,
        uint256 otcFee
    );

    event AddLiquidityDualToAmm(
        MarketAcc indexed user,
        AMMId indexed ammId,
        int256 exactSizeIn,
        // Output
        uint256 netLpOut,
        int256 netCashIn,
        uint256 netOtcFee
    );

    event AddLiquiditySingleCashToAmm(
        MarketAcc indexed user,
        AMMId indexed ammId,
        // Output
        uint256 netLpOut,
        int256 netCashIn,
        uint256 totalTakerOtcFee,
        // Intermediate data
        int256 swapSizeInterm
    );

    event RemoveLiquidityDualFromAmm(
        MarketAcc indexed user,
        AMMId indexed ammId,
        uint256 lpToRemove,
        // Output
        int256 netCashOut,
        int256 netSizeOut,
        uint256 netOtcFee
    );

    event RemoveLiquiditySingleCashFromAmm(
        MarketAcc indexed user,
        AMMId indexed ammId,
        uint256 lpToRemove,
        // Output
        int256 netCashOut,
        uint256 netTakerOtcFee,
        // Intermediate data
        int256 netSizeInterm
    );

    // ---- messages signed by root ----

    struct VaultDepositMessage {
        address root;
        uint8 accountId;
        TokenId tokenId;
        MarketId marketId;
        uint256 amount;
        uint64 nonce;
    }

    struct VaultPayTreasuryMessage {
        address root;
        TokenId tokenId;
        uint256 amount;
        uint64 nonce;
    }

    struct RequestVaultWithdrawalMessage {
        address root;
        TokenId tokenId;
        uint256 amount;
        uint64 nonce;
    }

    struct CancelVaultWithdrawalMessage {
        address root;
        TokenId tokenId;
        uint64 nonce;
    }

    struct SubaccountTransferMessage {
        address root;
        uint8 accountId;
        TokenId tokenId;
        MarketId marketId;
        uint256 amount;
        bool isDeposit;
        uint64 nonce;
    }

    struct SetAccManagerMessage {
        address root;
        uint8 accountId;
        address accManager;
        uint64 nonce;
    }

    // ---- messages signed by accManager ----

    struct ApproveAgentMessage {
        address root;
        uint8 accountId;
        address agent;
        uint64 expiry;
        uint64 nonce;
    }

    struct RevokeAgentsMessage {
        address root;
        uint8 accountId;
        address[] agents;
        uint64 nonce;
    }

    // ---- messages signed by agent ----

    struct PendleSignTx {
        Account account;
        bytes32 connectionId;
        uint64 nonce;
    }

    struct SwapWithAmmReq {
        bool cross;
        AMMId ammId;
        int256 signedSize;
        int128 desiredSwapRate;
    }

    struct AddLiquidityDualToAmmReq {
        bool cross;
        AMMId ammId;
        int256 maxCashIn;
        int256 exactSizeIn;
        uint256 minLpOut;
    }

    struct AddLiquiditySingleCashToAmmReq {
        bool cross;
        AMMId ammId;
        bool enterMarket;
        int256 netCashIn;
        uint256 minLpOut;
    }

    struct RemoveLiquidityDualFromAmmReq {
        bool cross;
        AMMId ammId;
        uint256 lpToRemove;
        int256 minCashOut;
        int256 minSizeOut;
        int256 maxSizeOut;
    }

    struct RemoveLiquiditySingleCashFromAmmReq {
        bool cross;
        AMMId ammId;
        uint256 lpToRemove;
        int256 minCashOut;
    }

    struct OrderReq {
        bool cross;
        MarketId marketId;
        AMMId ammId;
        Side side; // long
        TimeInForce tif; // type
        uint256 size; // size
        int16 tick; // tick
    }

    struct SingleOrderReq {
        OrderReq order;
        bool enterMarket;
        OrderId idToStrictCancel;
        bool exitMarket;
        // only need to be filled if isolated
        uint256 isolated_cashIn;
        bool isolated_cashTransferAll;
        // slippage
        int128 desiredMatchRate;
    }

    struct BulkOrdersReq {
        bool cross;
        BulkOrder[] bulks;
        // slippage
        int128[] desiredMatchRates;
    }

    struct BulkCancels {
        bool cross;
        MarketId marketId;
        bool cancelAll;
        OrderId[] orderIds;
    }

    struct CashTransferReq {
        MarketId marketId;
        int256 signedAmount;
    }

    struct AMMCashTransferReq {
        MarketId marketId;
        uint256 cashIn;
        bool cashTransferAll;
    }

    struct PayTreasuryReq {
        bool cross;
        MarketId marketId;
        uint256 amount;
    }

    struct EnterExitMarketsReq {
        bool cross;
        bool isEnter;
        MarketId[] marketIds;
    }

    // ---- internal ----

    struct MarketCache {
        address market;
        TokenId tokenId;
        uint32 maturity;
        uint8 tickStep;
    }
}
