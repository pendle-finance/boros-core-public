// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

import {GeneratedStorageSlots} from "../../../generated/slots.sol";
import {IConditionalModule} from "../../../interfaces/IConditionalModule.sol";
import {Err} from "../../../lib/Errors.sol";
import {PMath} from "../../../lib/math/PMath.sol";
import {Account, MarketAcc} from "../../../types/Account.sol";
import {AMMId, GetRequest, MarketId} from "../../../types/MarketTypes.sol";
import {Trade} from "../../../types/Trade.sol";
import {SideLib, TimeInForce, OrderIdLib} from "../../../types/Order.sol";
import {PendleRolesPlugin} from "../../roles/PendleRoles.sol";
import {AuthBase} from "../auth-base/AuthBase.sol";
import {ExecuteConditionalOrderParamsLib as DecodeLib} from "../lib/ExecuteParamsLib.sol";
import {BookAmmSwapBase} from "../trade-base/BookAmmSwapBase.sol";

contract ConditionalModule is IConditionalModule, AuthBase, BookAmmSwapBase, PendleRolesPlugin {
    using PMath for int256;
    using SideLib for int256;

    struct ConditionalModuleStorage {
        mapping(address validator => bool) isValidator;
        mapping(bytes32 actionHash => bool) isActionExecuted;
    }

    constructor(
        address permissionController_,
        address marketHub_
    ) PendleRolesPlugin(permissionController_) BookAmmSwapBase(marketHub_) {}

    function _CMS() internal pure returns (ConditionalModuleStorage storage $) {
        bytes32 slot = GeneratedStorageSlots.ROUTER_CONDITIONAL_MODULE_STORAGE_LOCATION;
        assembly {
            $.slot := slot
        }
    }

    /// @notice no setAuth needed because this function is called solely by the relayer, without agent signatures on
    /// the payload
    function executeConditionalOrder(ExecuteConditionalOrderReq memory req) external onlyRelayer {
        // --- LOAD DATA ---
        ConditionalOrder memory order = req.order;
        MarketCache memory cache = _getMarketCache(order.marketId);
        MarketAcc user = order.account.toMarketAcc(order.cross, cache.tokenId, order.marketId);

        // --- VERIFY SIGNATURES ---
        (bytes32 orderHash, bytes32 placeMsgHash, bytes32 execMsgHash) = _getHashes(req);
        _verifyAgentSig(order.account, req.agent, placeMsgHash, req.placeSig);
        _verifyValidatorSig(req.validator, execMsgHash, req.execMsgExpiry, req.execSig);

        // --- EXECUTE ORDER ---
        _checkOrderExpiry(order);
        (bool enterMarket, AMMId ammId, int128 desiredMatchRate) = _decodeOrderExecParams(req.execParams);
        OrderReq memory orderReq = _enforceReduceOnlyAndBuildOrder(order, user, ammId);
        if (enterMarket) {
            _enterMarket(user, order.marketId);
        }
        (Trade matched, uint256 takerOtcFee) = _executeSingleOrder(
            cache,
            user,
            orderReq,
            OrderIdLib.ZERO,
            desiredMatchRate
        );
        _markOrderExecuted(orderHash);

        emit ConditionalOrderExecuted(user, orderHash, order.marketId, ammId, orderReq.tif, matched, takerOtcFee);
    }

    function setConditionalValidator(address validator, bool isValidator) external onlyAuthorized {
        _CMS().isValidator[validator] = isValidator;
        emit ConditionalValidatorUpdated(validator, isValidator);
    }

    function isConditionalValidator(address validator) external view returns (bool) {
        return _CMS().isValidator[validator];
    }

    function isActionExecuted(bytes32 actionHash) external view returns (bool) {
        return _CMS().isActionExecuted[actionHash];
    }

    /// @dev valid agent is a loose check since BE & Validator should already check this twice
    function _verifyAgentSig(
        Account account,
        address agent,
        bytes32 messageHash,
        bytes memory signature
    ) internal view {
        require(_AMS().agentExpiry[account][agent] > 0, Err.ConditionalInvalidAgent());
        require(SignatureChecker.isValidSignatureNow(agent, messageHash, signature), Err.AuthInvalidMessage());
    }

    function _verifyValidatorSig(
        address validator,
        bytes32 messageHash,
        uint64 expiry,
        bytes memory signature
    ) internal view {
        require(_CMS().isValidator[validator], Err.ConditionalInvalidValidator());
        require(expiry > block.timestamp, Err.ConditionalMessageExpired());
        require(SignatureChecker.isValidSignatureNow(validator, messageHash, signature), Err.AuthInvalidMessage());
    }

    function _getHashes(
        ExecuteConditionalOrderReq memory req
    ) internal view returns (bytes32 orderHash, bytes32 placeMsgHash, bytes32 execMsgHash) {
        orderHash = keccak256(abi.encode(req.order));

        /// @dev orderHash is also used as actionHash
        PlaceConditionalActionMessage memory placeMsg = PlaceConditionalActionMessage({actionHash: orderHash});
        placeMsgHash = _hashPlaceConditionalActionMessage(placeMsg);

        ExecuteConditionalOrderMessage memory execMsg = ExecuteConditionalOrderMessage({
            orderHash: orderHash,
            execParams: req.execParams,
            expiry: req.execMsgExpiry
        });
        execMsgHash = _hashExecuteConditionalOrderMessage(execMsg);
    }

    function _checkOrderExpiry(ConditionalOrder memory order) internal view {
        require(order.expiry > block.timestamp, Err.ConditionalOrderExpired());
    }

    function _decodeOrderExecParams(
        bytes memory params
    ) internal pure returns (bool enterMarket, AMMId ammId, int128 desiredMatchRate) {
        uint256 version = DecodeLib.decodeVersion(params);
        if (version == DecodeLib.VERSION_1) {
            (enterMarket, ammId, desiredMatchRate) = DecodeLib.decodeBodyV1(params);
        } else {
            revert Err.ConditionalInvalidParams();
        }
    }

    function _enforceReduceOnlyAndBuildOrder(
        ConditionalOrder memory order,
        MarketAcc user,
        AMMId ammId
    ) internal returns (OrderReq memory) {
        if (!order.reduceOnly) {
            return _toOrderReq(order, ammId, order.size);
        }

        (, , int256 signedSize) = _MARKET_HUB.settleAllAndGet(user, GetRequest.ZERO, order.marketId);
        require(order.tif == TimeInForce.IOC || order.tif == TimeInForce.FOK, Err.ConditionalOrderNotReduceOnly());
        require(signedSize.isOfSide(order.side.opposite()), Err.ConditionalOrderNotReduceOnly());

        return _toOrderReq(order, ammId, PMath.min(order.size, signedSize.abs()));
    }

    function _enterMarket(MarketAcc user, MarketId marketId) internal {
        _MARKET_HUB.enterMarket(user, marketId);
    }

    /// @dev orderHash is also used as actionHash
    function _markOrderExecuted(bytes32 orderHash) internal {
        require(!_CMS().isActionExecuted[orderHash], Err.ConditionalActionExecuted());
        _CMS().isActionExecuted[orderHash] = true;
    }

    function _toOrderReq(
        ConditionalOrder memory order,
        AMMId ammId,
        uint256 size
    ) internal pure returns (OrderReq memory) {
        return
            OrderReq({
                cross: order.cross,
                marketId: order.marketId,
                ammId: ammId,
                side: order.side,
                tif: order.tif,
                size: size,
                tick: order.tick
            });
    }
}
