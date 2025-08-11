// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {PMath} from "../lib/math/PMath.sol";
import {Side} from "./Order.sol";
import {Err} from "../lib/Errors.sol";

/**
 * @title Trade
 * @notice Custom type for storing trade (Sum of fills across multiple ticks)
 * @dev Packs exactly 32 bytes (256 bits) from high to low: size(128) | cost(128)
 */
type Trade is uint256;

/**
 * @title Fill
 * @notice Custom type for storing a fill in a single tick. Can be fully casted to Trade, a Fill is also a Trade
 */
type Fill is uint256;

using TradeLib for Trade global;
using FillLib for Fill global;

using {_addTrade as +} for Trade global;

function _addTrade(Trade a, Trade b) pure returns (Trade) {
    return a.add(b);
}

library TradeLib {
    using PMath for int256;
    using PMath for uint256;
    using PMath for uint128;
    using PMath for int128;

    Trade internal constant ZERO = Trade.wrap(0);

    function from(int256 _signedSize, int256 _signedCost) internal pure returns (Trade) {
        return from128(_signedSize.Int128(), _signedCost.Int128());
    }

    function from128(int128 _signedSize, int128 _signedCost) internal pure returns (Trade) {
        uint256 rawSignedSize = uint128(_signedSize);
        uint256 rawSignedCost = uint128(_signedCost);
        return Trade.wrap((rawSignedSize << 128) | rawSignedCost);
    }

    function unpack(Trade trade) internal pure returns (int128 _signedSize, int128 _signedCost) {
        uint256 raw = Trade.unwrap(trade);
        return (int128(uint128(raw >> 128)), int128(uint128(raw)));
    }

    function side(Trade trade) internal pure returns (Side) {
        return signedSize(trade) > 0 ? Side.LONG : Side.SHORT;
    }

    function signedSize(Trade trade) internal pure returns (int128) {
        return int128(uint128(Trade.unwrap(trade) >> 128));
    }

    function absSize(Trade trade) internal pure returns (uint128) {
        // safe cast since signedSize is 128 bit
        return uint128(signedSize(trade).abs());
    }

    function signedCost(Trade trade) internal pure returns (int128) {
        return int128(uint128(Trade.unwrap(trade)));
    }

    function absCost(Trade trade) internal pure returns (uint128) {
        return uint128(signedCost(trade).abs());
    }

    function add(Trade p, Trade q) internal pure returns (Trade) {
        (int128 pSignedSize, int128 pSignedCost) = unpack(p);
        (int128 qSignedSize, int128 qSignedCost) = unpack(q);
        return from128(pSignedSize + qSignedSize, pSignedCost + qSignedCost);
    }

    function opposite(Trade trade) internal pure returns (Trade) {
        (int128 _signedSize, int128 _signedCost) = unpack(trade);
        return from128(-_signedSize, -_signedCost);
    }

    function isZero(Trade trade) internal pure returns (bool) {
        return Trade.unwrap(trade) == 0;
    }

    function fromSizeAndRate(int256 _signedSize, int256 _rate) internal pure returns (Trade) {
        return from(_signedSize, _signedSize.mulDown(_rate));
    }

    function from3(Side _side, uint256 _size, int256 _rate) internal pure returns (Trade) {
        int128 signedSize128 = _size.Int128();
        int128 signedCost128 = PMath.mulDown(signedSize128, _rate).Int128();
        if (_side == Side.LONG) {
            return from128(signedSize128, signedCost128);
        } else {
            return from128(-signedSize128, -signedCost128);
        }
    }

    function requireDesiredSideAndRate(Trade trade, Side _side, int128 desiredRate) internal pure {
        if (trade.signedSize() != 0) {
            require(trade.side() == _side, Err.TradeUndesiredSide());
        }
        trade.requireDesiredRate(desiredRate);
    }

    function requireDesiredRate(Trade trade, int128 desiredRate) internal pure {
        int256 maxCost = trade.signedSize().mulDown(desiredRate);
        require(trade.signedCost() <= maxCost, Err.TradeUndesiredRate());
    }
}

library FillLib {
    using PMath for int128;
    Fill internal constant ZERO = Fill.wrap(0);

    function toTrade(Fill fill) internal pure returns (Trade) {
        return Trade.wrap(Fill.unwrap(fill));
    }

    function from3(Side _side, uint256 _size, int256 _rate) internal pure returns (Fill) {
        return Fill.wrap(Trade.unwrap(TradeLib.from3(_side, _size, _rate)));
    }

    function isZero(Fill fill) internal pure returns (bool) {
        return Fill.unwrap(fill) == 0;
    }

    function side(Fill fill) internal pure returns (Side) {
        return fill.toTrade().side();
    }

    function absSize(Fill fill) internal pure returns (uint128) {
        return fill.toTrade().absSize();
    }

    function absCost(Fill fill) internal pure returns (uint128) {
        return fill.toTrade().absCost();
    }
}
