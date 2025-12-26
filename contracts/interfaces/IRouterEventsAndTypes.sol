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

    event ConditionalOrderExecuted(
        MarketAcc indexed user,
        bytes32 orderHash,
        MarketId marketId,
        AMMId ammId,
        TimeInForce tif,
        Trade matched,
        uint256 takerOtcFee
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

    event DepositFromBox(
        address indexed root,
        uint32 boxId,
        address tokenSpent,
        uint256 amountSpent,
        uint8 accountId,
        TokenId tokenId,
        MarketId marketId,
        uint256 depositAmount,
        uint256 payTreasuryAmount
    );

    event WithdrawFromBox(address indexed root, uint32 boxId, address token, uint256 amount);

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

    struct DepositFromBoxMessage {
        address root;
        uint32 boxId;
        address tokenSpent;
        uint256 maxAmountSpent;
        //
        uint8 accountId;
        TokenId tokenId;
        MarketId marketId;
        uint256 minDepositAmount;
        uint256 payTreasuryAmount;
        //
        address swapExtRouter;
        address swapApprove;
        bytes swapCalldata;
        //
        uint64 expiry;
        uint256 salt;
    }

    struct WithdrawFromBoxMessage {
        address root;
        uint32 boxId;
        address token;
        uint256 amount;
        //
        uint64 expiry;
        uint256 salt;
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

    // ---- requests sent by accManager ----

    struct ApproveAgentReq {
        address root;
        uint8 accountId;
        address agent;
        uint64 expiry;
    }

    struct RevokeAgentsReq {
        address root;
        uint8 accountId;
        address[] agents;
    }

    // ---- messages signed by agent ----

    struct PendleSignTx {
        Account account;
        bytes32 connectionId;
        uint64 nonce;
    }

    struct PlaceConditionalActionMessage {
        bytes32 actionHash;
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
        Side desiredSwapSide;
        int128 desiredSwapRate;
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
        Side desiredSwapSide;
        int128 desiredSwapRate;
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

    struct ConditionalOrder {
        Account account;
        bool cross;
        MarketId marketId;
        Side side;
        TimeInForce tif;
        uint256 size;
        int16 tick;
        bool reduceOnly;
        uint256 salt;
        uint64 expiry;
        bytes32 hashedOffchainCondition;
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

    // ---- messages signed by validator ----

    struct ExecuteConditionalOrderMessage {
        bytes32 orderHash;
        bytes execParams;
        uint64 expiry;
    }

    struct ExecuteConditionalOrderReq {
        ConditionalOrder order;
        bytes execParams;
        //
        address agent;
        bytes placeSig;
        //
        address validator;
        uint64 execMsgExpiry;
        bytes execSig;
    }

    // ---- internal ----

    struct MarketCache {
        address market;
        TokenId tokenId;
        uint32 maturity;
        uint8 tickStep;
    }
}
