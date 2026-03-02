// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

import {GeneratedStorageSlots} from "../../../generated/slots.sol";
import {IOTCModule} from "../../../interfaces/IOTCModule.sol";
import {ArrayLib} from "../../../lib/ArrayLib.sol";
import {Err} from "../../../lib/Errors.sol";
import {Account, AccountLib, MarketAcc} from "../../../types/Account.sol";
import {CancelData, LongShort, MarketId, OTCTrade} from "../../../types/MarketTypes.sol";
import {Trade, TradeLib} from "../../../types/Trade.sol";
import {PendleRolesPlugin} from "../../roles/PendleRoles.sol";
import {AuthBase} from "../auth-base/AuthBase.sol";
import {TradeStorage} from "../trade-base/TradeStorage.sol";

contract OTCModule is IOTCModule, AuthBase, TradeStorage, PendleRolesPlugin {
    using ArrayLib for MarketId[];

    struct OTCModuleStorage {
        address validator;
        mapping(bytes32 tradeHash => bool) isTradeExecuted;
    }

    constructor(
        address permissionController_,
        address marketHub_
    ) PendleRolesPlugin(permissionController_) TradeStorage(marketHub_) {}

    function _OMS() internal pure returns (OTCModuleStorage storage $) {
        bytes32 slot = GeneratedStorageSlots.ROUTER_OTC_MODULE_STORAGE_LOCATION;
        assembly {
            $.slot := slot
        }
    }

    function executeOTCTrade(ExecuteOTCTradeReq memory req) external onlyRelayer {
        // --- VERIFY SIGNATURES ---
        _verifyAgentSig(req.trade.maker, req.trade, req.makerData);
        _verifyAgentSig(req.trade.taker, req.trade, req.takerData);
        _verifyValidatorSig(req);
        // check Trade execution is done in markTradeExecuted

        // --- LOAD DATA ---
        (MarketId marketId, MarketAcc maker, MarketAcc taker) = _getMarketAccs(req);
        Trade trade = TradeLib.fromSizeAndRate(req.trade.signedSize, req.trade.rate);

        // --- EXECUTE ---
        _enterMarket(maker, marketId);
        _enterMarket(taker, marketId);
        uint256 otcFee = _otc(marketId, maker, taker, trade);

        _markTradeExecuted(req.trade);
        emit OTCTradeExecuted(maker, taker, marketId, trade, otcFee);
    }

    function setOTCTradeValidator(address validator) external onlyAuthorized {
        _OMS().validator = validator;
        emit OTCTradeValidatorUpdated(validator);
    }

    function otcTradeValidator() external view returns (address) {
        return _OMS().validator;
    }

    function isOTCTradeExecuted(bytes32 tradeHash) external view returns (bool) {
        return _OMS().isTradeExecuted[tradeHash];
    }

    /// @dev valid agent is a loose check since BE & Validator should already check this twice
    function _verifyAgentSig(address party, OTCTradeReq memory trade, AcceptOTCPartialData memory data) internal view {
        require(data.expiry > block.timestamp, Err.OTCMessageExpired());

        Account account = AccountLib.from(party, data.accountId);
        require(_AMS().agentExpiry[account][data.agent] > 0, Err.OTCInvalidAgent());
        require(
            SignatureChecker.isValidSignatureNow(data.agent, _getAcceptOTCFullMsgHash(trade, data), data.signature),
            Err.AuthInvalidMessage()
        );
    }

    function _verifyValidatorSig(ExecuteOTCTradeReq memory req) internal view {
        require(req.execMsgExpiry > block.timestamp, Err.OTCMessageExpired());

        ExecuteOTCTradeMessage memory execMsg = ExecuteOTCTradeMessage({
            makerMsgHash: _getAcceptOTCFullMsgHash(req.trade, req.makerData),
            takerMsgHash: _getAcceptOTCFullMsgHash(req.trade, req.takerData),
            expiry: req.execMsgExpiry
        });

        require(
            SignatureChecker.isValidSignatureNow(_OMS().validator, _hashExecuteOTCTradeMessage(execMsg), req.execSig),
            Err.AuthInvalidMessage()
        );
    }

    function _getAcceptOTCFullMsgHash(
        OTCTradeReq memory trade,
        AcceptOTCPartialData memory data
    ) internal view returns (bytes32) {
        return
            _hashAcceptOTCFullMessage(
                AcceptOTCFullMessage({trade: trade, accountId: data.accountId, cross: data.cross, expiry: data.expiry})
            );
    }

    function _getMarketAccs(
        ExecuteOTCTradeReq memory req
    ) internal returns (MarketId marketId, MarketAcc maker, MarketAcc taker) {
        marketId = req.trade.marketId;
        MarketCache memory cache = _getMarketCache(marketId);
        maker = AccountLib.from(req.trade.maker, req.makerData.accountId).toMarketAcc(
            req.makerData.cross,
            cache.tokenId,
            marketId
        );
        taker = AccountLib.from(req.trade.taker, req.takerData.accountId).toMarketAcc(
            req.takerData.cross,
            cache.tokenId,
            marketId
        );
    }

    function _enterMarket(MarketAcc user, MarketId marketId) internal {
        MarketId[] memory enteredMarkets = _MARKET_HUB.getEnteredMarkets(user);
        if (!enteredMarkets.include(marketId)) {
            _MARKET_HUB.enterMarket(user, marketId);
        }
    }

    function _otc(MarketId marketId, MarketAcc maker, MarketAcc taker, Trade trade) internal returns (uint256 otcFee) {
        LongShort memory emptyOrders;
        CancelData memory emptyCancels;

        OTCTrade[] memory OTCs = new OTCTrade[](1);
        OTCs[0] = OTCTrade({counter: maker, trade: trade.opposite(), cashToCounter: 0});

        (, otcFee) = _MARKET_HUB.orderAndOtc(marketId, taker, emptyOrders, emptyCancels, OTCs);
    }

    function _markTradeExecuted(OTCTradeReq memory trade) internal {
        bytes32 tradeHash = _hashOTCTradeReq(trade);
        require(!_OMS().isTradeExecuted[tradeHash], Err.OTCRequestExecuted());
        _OMS().isTradeExecuted[tradeHash] = true;
    }
}
