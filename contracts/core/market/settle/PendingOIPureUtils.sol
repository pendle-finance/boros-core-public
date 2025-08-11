// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {PMath} from "../../../lib/math/PMath.sol";
import {LongShort, SweptF} from "../../../types/MarketTypes.sol";
import {OrderId, Side} from "../../../types/Order.sol";
import {Fill} from "../../../types/Trade.sol";
import {MarginViewUtils} from "../margin/MarginViewUtils.sol";

abstract contract PendingOIPureUtils is MarginViewUtils {
    using PMath for int256;
    using PMath for uint256;

    function _updateOIOnUserWrite(UserMem memory user, MarketMem memory market) internal pure {
        if (user.preSettleSize == user.signedSize) return;
        market.OI = market.OI - int256(user.preSettleSize.abs()) + int256(user.signedSize.abs());
    }

    function _updateOIOnNewMatch(MarketMem memory market, uint256 absSize) internal pure {
        market.OI += absSize.Int();
    }

    function _updateOIAndPMOnPartial(
        UserMem memory user,
        MarketMem memory market,
        Side side,
        uint256 absSize,
        uint256 pm
    ) internal pure {
        market.OI -= absSize.Int();
        user.pmData.sub(side, absSize, pm);
    }

    function _updateOIAndPMOnSwept(UserMem memory user, MarketMem memory market, SweptF memory sweptF) internal pure {
        (bool isPurged, Fill fill) = sweptF.getFill();
        uint256 absSize = fill.absSize();
        if (!isPurged) {
            market.OI -= absSize.Int();
        }
        user.pmData.sub(fill.side(), absSize, _calcPMFromFill(market, fill));
    }

    function _updatePMOnAdd(UserMem memory user, MarketMem memory market, LongShort memory orders) internal pure {
        uint256 sizeAdded = 0;
        uint256 pmAdded = 0;
        for (uint256 i = 0; i < orders.sizes.length; ++i) {
            sizeAdded += orders.sizes[i];
            pmAdded += _calcPMFromTick(market, orders.sizes[i], orders.limitTicks[i]);
        }
        user.pmData.add(orders.side, sizeAdded, pmAdded);
    }

    function _updatePMOnRemove(
        UserMem memory user,
        MarketMem memory market,
        OrderId[] memory ids,
        uint256[] memory sizes
    ) internal pure {
        for (uint256 i = 0; i < ids.length; ++i) {
            (Side side, int16 tickIndex, ) = ids[i].unpack();
            uint256 pm = _calcPMFromTick(market, sizes[i], tickIndex);
            user.pmData.sub(side, sizes[i], pm);
        }
    }
}
