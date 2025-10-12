// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

// Generated
import {GeneratedStorageSlots} from "../../../generated/slots.sol";

// Libraries
import {ArrayLib, LowLevelArrayLib} from "../../../lib/ArrayLib.sol";
import {Err} from "../../../lib/Errors.sol";
import {PMath} from "../../../lib/math/PMath.sol";

// Types
import {OrderId, OrderIdArrayLib, Side, TimeInForce} from "../../../types/Order.sol";
import {LongShort, CancelData} from "../../../types/MarketTypes.sol";
import {Trade} from "../../../types/Trade.sol";
import {OrderIdBoolMapping} from "../../../types/TransientOrderIdMapping.sol";

// Market components
import {OrderBookUtils} from "../orderbook/OrderBookUtils.sol";
import {PendingOIPureUtils} from "../settle/PendingOIPureUtils.sol";
import {RateUtils} from "./RateUtils.sol";

abstract contract CoreOrderUtils is OrderBookUtils, PendingOIPureUtils, RateUtils {
    using PMath for uint256;
    using ArrayLib for OrderId[];
    using OrderIdArrayLib for OrderId[];
    using LowLevelArrayLib for OrderId[];

    OrderIdBoolMapping private constant _isOrderRemove =
        OrderIdBoolMapping.wrap(GeneratedStorageSlots.CORE_ORDER_IS_ORDER_REMOVE_SLOT);

    // ------------ Add ------------

    function _coreAdd(
        MarketMem memory market,
        UserMem memory user,
        LongShort memory orders,
        Trade prevMatched
    ) internal {
        if (!_shouldPlaceOnBook(orders, prevMatched)) return;

        uint256 nAdd = orders.sizes.length;

        require(
            user.longIds.length + user.shortIds.length + nAdd <= _ctx().maxOpenOrders,
            Err.MarketMaxOrdersExceeded()
        );

        OrderId[] memory ids;
        if (orders.side == Side.LONG) {
            user.longIds = user.longIds.extend(nAdd);
            ids = user.longIds;
        } else {
            user.shortIds = user.shortIds.extend(nAdd);
            ids = user.shortIds;
        }

        uint256 preLen = ids.length - nAdd;
        _bookAdd(user.addr, orders, ids, preLen);

        _updatePMOnAdd(user, market, orders);
        ids.updateBestSameSide(preLen);
    }

    function _shouldPlaceOnBook(
        LongShort memory orders,
        Trade prevMatched
    ) internal pure returns (bool shouldPlaceOnBook) {
        TimeInForce tif = orders.tif;
        bool hasMatchedAll = orders.isEmpty();

        if (tif == TimeInForce.GTC) {
            return !hasMatchedAll;
        } else if (tif == TimeInForce.IOC) {
            return false;
        } else if (tif == TimeInForce.FOK) {
            require(hasMatchedAll, Err.MarketOrderFOKNotFilled());
            return false;
        } else if (tif == TimeInForce.ALO) {
            require(prevMatched.isZero(), Err.MarketOrderALOFilled());
            return !hasMatchedAll;
        } else if (tif == TimeInForce.SOFT_ALO) {
            return !hasMatchedAll;
        } else {
            assert(false);
        }
    }

    // ------------ Remove ------------

    function _coreRemoveAft(
        MarketMem memory market,
        UserMem memory user,
        CancelData memory cancel,
        bool isForced
    ) internal returns (OrderId[] memory /*removedIds*/) {
        if (cancel.isAll) {
            return _coreRemoveAllAft(market, user, isForced);
        }

        uint256[] memory removedSizes = _bookRemove(cancel.ids, cancel.isStrict, isForced);
        OrderId[] memory removedIds = cancel.ids;

        uint256 removeCnt = removedIds.length;
        if (removeCnt == 0) return removedIds;

        // here we set the removed orders to the mapping, then loop through all orders of the user to confirm all the
        // orders just removed is his

        for (uint256 i = 0; i < removeCnt; ++i) {
            _isOrderRemove.set(removedIds[i], true);
        }

        for (uint256 iter = 0; iter < 2; iter++) {
            OrderId[] memory ids = iter == 0 ? user.longIds : user.shortIds;
            uint256 length = ids.length;
            for (uint256 i = 0; i < length && removeCnt > 0; ) {
                OrderId curId = ids[i];
                if (!_isOrderRemove.get(curId)) {
                    i = i.inc();
                    continue;
                }
                removeCnt = removeCnt.dec();
                _isOrderRemove.set(curId, false);
                ids[i] = ids[length.dec()];
                length = length.dec();
            }

            ids.setShorterLength(length);
            ids.updateBestSameSide(0);
        }
        require(removeCnt == 0, Err.MarketOrderNotFound());

        _updatePMOnRemove(user, market, removedIds, removedSizes);

        return removedIds;
    }

    /// @dev isStrict is not used here since all orders in longIds and shortIds are guaranteed not filled, we have swept
    /// & settled the filled
    function _coreRemoveAllAft(
        MarketMem memory market,
        UserMem memory user,
        bool isForced
    ) internal returns (OrderId[] memory removedIds) {
        // Here we pass all the existing orders into bookRemove. The arrays will be modified in place and only contain
        // removed orders. Funnily, since we have settled beforehand, the two arrays will only contain removable orders to
        // begin with, and we will use it to later clear both arrays.
        if (user.longIds.length > 0) {
            uint256[] memory removedSizes = _bookRemove(user.longIds, false, isForced);
            _updatePMOnRemove(user, market, user.longIds, removedSizes);
        }
        if (user.shortIds.length > 0) {
            uint256[] memory removedSizes = _bookRemove(user.shortIds, false, isForced);
            _updatePMOnRemove(user, market, user.shortIds, removedSizes);
        }

        removedIds = user.longIds.concat(user.shortIds);
        user.longIds.setShorterLength(0);
        user.shortIds.setShorterLength(0);
    }
}
