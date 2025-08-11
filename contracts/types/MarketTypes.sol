// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {PMath} from "../lib/math/PMath.sol";
import {MarketAcc} from "./Account.sol";
import {OrderId, Side, TimeInForce} from "./Order.sol";
import {Trade, TradeLib, Fill} from "./Trade.sol";

enum MarginType {
    IM,
    MM
}

enum GetRequest {
    IM,
    MM,
    ZERO
}

struct BulkOrder {
    MarketId marketId;
    LongShort orders;
    CancelData cancelData;
}

struct BulkOrderResult {
    Trade matched;
    uint256 takerFee;
}

struct LongShort {
    TimeInForce tif;
    Side side;
    uint256[] sizes;
    int16[] limitTicks;
}

struct CancelData {
    OrderId[] ids;
    bool isAll;
    bool isStrict;
}

struct OTCTrade {
    MarketAcc counter;
    Trade trade;
    int256 cashToCounter;
}

struct UserResult {
    PayFee settle;
    PayFee payment;
    //
    OrderId[] removedIds;
    //
    Trade bookMatched;
    MarketAcc partialMaker;
    PayFee partialPayFee;
    //
    bool isStrictIM;
    VMResult finalVM; // finalVM is IM if isStrictIM is true, otherwise it's MM
}

struct OTCResult {
    PayFee settle;
    PayFee payment;
    bool isStrictIM;
    VMResult finalVM; // finalVM is IM if isStrictIM is true, otherwise it's MM
}

struct LiqResult {
    bool isStrictIMLiq;
    VMResult finalVMLiq;
    //
    PayFee liqSettle;
    PayFee liqPayment;
    PayFee vioSettle;
    PayFee vioPayment;
    //
    Trade liqTrade;
}

struct DelevResult {
    PayFee winSettle;
    PayFee winPayment;
    PayFee loseSettle;
    PayFee losePayment;
    //
    Trade delevTrade;
}

struct TickInfo {
    // every info are packed here to be read/written all at once
    // see `TickInfoLib.write` and `TickInfoLib.read`
    uint256 packed;
    // Some info that are too big will be stored here.
    // They are expected to not be read/written often.
    uint40 unpackedNumActive;
    uint40 unpackedActiveNonceOffset;
}

struct SweptF {
    FTag fTag;
    Fill __fill;
}

struct PartialData {
    uint128 sumLongSize;
    uint128 sumLongPM;
    uint128 sumShortSize;
    uint128 sumShortPM;
    FTag fTag;
    int128 sumCost;
}

struct PMDataMem {
    uint256 sumLongSize;
    uint256 sumLongPM;
    uint256 sumShortSize;
    uint256 sumShortPM;
}

type FIndex is bytes26;
type FTag is uint32;
type MatchEvent is uint72;
type TickNonceData is uint256;
type NodeData is uint256;
type PayFee is uint256;
type VMResult is uint256;
type TokenId is uint16;
type MarketId is uint24;
type AMMId is uint24;
type AccountData2 is uint192;

using PayFeeLib for PayFee global;
using TickInfoLib for TickInfo global;
using NodeDataLib for NodeData global;
using MatchEventLib for MatchEvent global;
using TickNonceDataLib for TickNonceData global;
using VMResultLib for VMResult global;
using OrdersLib for LongShort global;
using MarketIdLib for MarketId global;
using AMMIdLib for AMMId global;
using PartialDataLib for PartialData global;
using AccountData2Lib for AccountData2 global;
using FIndexLib for FIndex global;
using PMDataMemLib for PMDataMem global;
using FTagLib for FTag global;
using SweptFLib for SweptF global;

library OrdersLib {
    function createOrders(
        Side side,
        TimeInForce tif,
        uint256 size,
        int16 limitTick
    ) internal pure returns (LongShort memory res) {
        if (size == 0) return res;
        res.tif = tif;
        res.side = side;
        res.sizes = new uint256[](1);
        res.sizes[0] = size;
        res.limitTicks = new int16[](1);
        res.limitTicks[0] = limitTick;
    }

    function createOrders(TimeInForce tif, int256 size, int16 limitTick) internal pure returns (LongShort memory res) {
        if (size == 0) return res;
        res.tif = tif;
        res.side = size > 0 ? Side.LONG : Side.SHORT;
        res.sizes = new uint256[](1);
        res.sizes[0] = size > 0 ? uint256(size) : uint256(-size);
        res.limitTicks = new int16[](1);
        res.limitTicks[0] = limitTick;
    }

    function createCancel(OrderId idToCancel, bool isStrict) internal pure returns (CancelData memory res) {
        if (idToCancel.isZero()) return res;
        res.ids = new OrderId[](1);
        res.ids[0] = idToCancel;
        res.isAll = false;
        res.isStrict = isStrict;
    }

    function isEmpty(LongShort memory orders) internal pure returns (bool) {
        return orders.sizes.length == 0;
    }
}

library MatchEventLib {
    function from(uint40 _headIndex, FTag _fTag) internal pure returns (MatchEvent) {
        uint72 packed = 0;

        packed = uint72(_headIndex);
        packed = (packed << 32) | _fTag.raw();

        return MatchEvent.wrap(packed);
    }

    function fTag(MatchEvent data) internal pure returns (FTag _fTag) {
        return FTag.wrap(uint32(MatchEvent.unwrap(data)));
    }

    function headIndex(MatchEvent data) internal pure returns (uint40 _headIndex) {
        return uint40(MatchEvent.unwrap(data) >> 32);
    }
}

library TickNonceDataLib {
    function from(
        MatchEvent _lastEvent,
        uint40 _firstEventId,
        uint40 _lastEventId,
        uint40 _nextActiveNonce
    ) internal pure returns (TickNonceData) {
        uint256 packed = 0;

        packed = MatchEvent.unwrap(_lastEvent);
        packed = (packed << 40) | _firstEventId;
        packed = (packed << 40) | _lastEventId;
        packed = (packed << 40) | _nextActiveNonce;

        return TickNonceData.wrap(packed);
    }

    function isZero(TickNonceData data) internal pure returns (bool) {
        return TickNonceData.unwrap(data) == 0;
    }

    function lastEvent(TickNonceData data) internal pure returns (MatchEvent _lastEvent) {
        return MatchEvent.wrap(uint72(TickNonceData.unwrap(data) >> 120));
    }

    function firstEventId(TickNonceData data) internal pure returns (uint40 _firstEventId) {
        return uint40(TickNonceData.unwrap(data) >> 80);
    }

    function lastEventId(TickNonceData data) internal pure returns (uint40 _lastEventId) {
        return uint40(TickNonceData.unwrap(data) >> 40);
    }

    function nextActiveNonce(TickNonceData data) internal pure returns (uint40 _nextActiveNonce) {
        return uint40(TickNonceData.unwrap(data));
    }

    function replaceNextActiveNonce(TickNonceData data, uint40 _nextActiveNonce) internal pure returns (TickNonceData) {
        uint256 packed = TickNonceData.unwrap(data);
        packed >>= 40;
        packed = (packed << 40) | _nextActiveNonce;
        return TickNonceData.wrap(packed);
    }
}

library NodeDataLib {
    NodeData internal constant ZERO = NodeData.wrap(0);

    function from(
        uint128 _orderSize,
        uint40 _makerNonce,
        uint40 _tickNonce,
        uint40 _refTickNonce
    ) internal pure returns (NodeData) {
        uint256 packed = 0;

        packed = uint256(_orderSize);
        packed = (packed << 40) | _makerNonce;
        packed = (packed << 40) | _tickNonce;
        packed = (packed << 40) | _refTickNonce;

        return NodeData.wrap(packed);
    }

    function orderSize(NodeData data) internal pure returns (uint128 _orderSize) {
        return uint128(NodeData.unwrap(data) >> 120);
    }

    function makerNonce(NodeData data) internal pure returns (uint40 _makerNonce) {
        return uint40(NodeData.unwrap(data) >> 80);
    }

    function tickNonce(NodeData data) internal pure returns (uint40 _tickNonce) {
        return uint40(NodeData.unwrap(data) >> 40);
    }

    function refTickNonce(NodeData data) internal pure returns (uint40 _refTickNonce) {
        return uint40(NodeData.unwrap(data));
    }

    function decOrderSize(NodeData data, uint128 amount) internal pure returns (NodeData) {
        // this works because order size is at the most significant part
        uint256 packed = NodeData.unwrap(data);
        uint256 shiftedAmount = uint256(amount) << 120;
        packed -= shiftedAmount;
        return NodeData.wrap(packed);
    }
}

library TickInfoLib {
    uint40 internal constant PACKED_NUM_ACTIVE_BITS = 28;
    uint40 internal constant PACKED_NUM_ACTIVE_THRESHOLD = uint40((1 << PACKED_NUM_ACTIVE_BITS) - 1);

    uint40 internal constant PACKED_ACTIVE_NONCE_OFFSET_BITS = 20;
    uint40 internal constant PACKED_ACTIVE_NONCE_OFFSET_THRESHOLD = uint40((1 << PACKED_ACTIVE_NONCE_OFFSET_BITS) - 1);

    function write(
        TickInfo storage self,
        uint128 _tickSum,
        uint40 _headIndex,
        uint40 _tailIndex,
        uint40 _tickNonce,
        uint40 _activeTickNonce
    ) internal {
        uint40 _numActive = _tailIndex - _headIndex;
        uint40 _activeNonceOffset = _tickNonce - _activeTickNonce;

        if (_numActive >= PACKED_NUM_ACTIVE_THRESHOLD) {
            self.unpackedNumActive = _numActive;
            _numActive = PACKED_NUM_ACTIVE_THRESHOLD;
        }

        if (_activeNonceOffset >= PACKED_ACTIVE_NONCE_OFFSET_THRESHOLD) {
            self.unpackedActiveNonceOffset = _activeNonceOffset;
            _activeNonceOffset = PACKED_ACTIVE_NONCE_OFFSET_THRESHOLD;
        }

        uint256 packed = 0;

        packed = _tickSum;
        packed = (packed << 40) | _headIndex;
        packed = (packed << PACKED_NUM_ACTIVE_BITS) | _numActive;
        packed = (packed << 40) | _tickNonce;
        packed = (packed << PACKED_ACTIVE_NONCE_OFFSET_BITS) | _activeNonceOffset;

        self.packed = packed;
    }

    function read(
        TickInfo storage self
    )
        internal
        view
        returns (uint128 _tickSum, uint40 _headIndex, uint40 _tailIndex, uint40 _tickNonce, uint40 _activeTickNonce)
    {
        uint40 _numActive;
        uint40 _activeNonceOffset;

        uint256 packed = self.packed;

        _activeNonceOffset = uint40(packed & PACKED_ACTIVE_NONCE_OFFSET_THRESHOLD);
        packed >>= PACKED_ACTIVE_NONCE_OFFSET_BITS;

        _tickNonce = uint40(packed);
        packed >>= 40;

        _numActive = uint40(packed & PACKED_NUM_ACTIVE_THRESHOLD);
        packed >>= PACKED_NUM_ACTIVE_BITS;

        _headIndex = uint40(packed);
        packed >>= 40;

        _tickSum = uint128(packed);

        if (_activeNonceOffset == PACKED_ACTIVE_NONCE_OFFSET_THRESHOLD)
            _activeNonceOffset = self.unpackedActiveNonceOffset;
        if (_numActive == PACKED_NUM_ACTIVE_THRESHOLD) _numActive = self.unpackedNumActive;

        _activeTickNonce = _tickNonce - _activeNonceOffset;
        _tailIndex = _headIndex + _numActive;
    }

    function tickSum(TickInfo storage self) internal view returns (uint128 _tickSum) {
        return uint128(self.packed >> 128);
    }

    function headIndex(TickInfo storage self) internal view returns (uint40 _headIndex) {
        uint256 SHIFT = 88; // 28 (_numActive) + 40 (_tickNonce) + 20 (_activeNonceOffset)
        return uint40(self.packed >> SHIFT);
    }
}

using {_addVMResult as +} for VMResult global;

function _addVMResult(VMResult a, VMResult b) pure returns (VMResult) {
    return a.add(b);
}

library VMResultLib {
    using PMath for int256;
    using PMath for uint256;

    VMResult internal constant ZERO = VMResult.wrap(0);

    function from(int256 _value, uint256 _margin) internal pure returns (VMResult) {
        return from128(_value.Int128(), _margin.Uint128());
    }

    function from128(int128 _value, uint128 _margin) internal pure returns (VMResult) {
        uint256 rawValue = uint128(_value);
        uint256 rawMargin = _margin;
        return VMResult.wrap((rawValue << 128) | rawMargin);
    }

    function unpack(VMResult result) internal pure returns (int128 _value, uint128 _margin) {
        uint256 raw = VMResult.unwrap(result);
        return (int128(uint128(raw >> 128)), uint128(raw));
    }

    function add(VMResult p, VMResult q) internal pure returns (VMResult) {
        (int128 pValue, uint128 pMargin) = unpack(p);
        (int128 qValue, uint128 qMargin) = unpack(q);
        return from128(pValue + qValue, pMargin + qMargin);
    }
}

using {_addPayFee as +} for PayFee global;

function _addPayFee(PayFee a, PayFee b) pure returns (PayFee) {
    return a.add(b);
}

library PayFeeLib {
    using PMath for int256;
    using PMath for uint256;

    PayFee internal constant ZERO = PayFee.wrap(0);

    function from(int256 _payment, uint256 _fees) internal pure returns (PayFee) {
        return from128(_payment.Int128(), _fees.Uint128());
    }

    function from128(int128 _payment, uint128 _fees) internal pure returns (PayFee) {
        return PayFee.wrap((uint256(uint128(_payment)) << 128) | uint256(_fees));
    }

    function unpack(PayFee result) internal pure returns (int128 _payment, uint128 _fees) {
        uint256 raw = PayFee.unwrap(result);
        return (int128(uint128(raw >> 128)), uint128(raw));
    }

    function fee(PayFee result) internal pure returns (uint128) {
        return uint128(PayFee.unwrap(result));
    }

    function add(PayFee p, PayFee q) internal pure returns (PayFee) {
        (int128 pPayment, uint128 pFees) = unpack(p);
        (int128 qPayment, uint128 qFees) = unpack(q);
        return from128(pPayment + qPayment, pFees + qFees);
    }

    function addFee(PayFee p, uint256 _fee) internal pure returns (PayFee) {
        (int128 pPayment, uint128 pFees) = unpack(p);
        return from128(pPayment, pFees + _fee.Uint128());
    }

    function addPayment(PayFee p, int256 _payment) internal pure returns (PayFee) {
        (int128 pPayment, uint128 pFees) = unpack(p);
        return from128(pPayment + _payment.Int128(), pFees);
    }

    function subPayment(PayFee p, int256 _payment) internal pure returns (PayFee) {
        (int128 pPayment, uint128 pFees) = unpack(p);
        return from128(pPayment - _payment.Int128(), pFees);
    }

    function total(PayFee p) internal pure returns (int256) {
        (int128 pPayment, uint128 pFees) = unpack(p);
        return int256(pPayment) - int256(uint256(pFees));
    }
}

function _tokenIdEq(TokenId lhs, TokenId rhs) pure returns (bool) {
    return TokenId.unwrap(lhs) == TokenId.unwrap(rhs);
}

using {_tokenIdEq as ==} for TokenId global;

function _marketIdEq(MarketId lhs, MarketId rhs) pure returns (bool) {
    return MarketId.unwrap(lhs) == MarketId.unwrap(rhs);
}

using {_marketIdEq as ==} for MarketId global;

library MarketIdLib {
    MarketId internal constant CROSS = MarketId.wrap(type(uint24).max);
    MarketId internal constant ZERO = MarketId.wrap(0);

    function isCross(MarketId self) internal pure returns (bool) {
        return self == CROSS;
    }
}

function _ammIdEq(AMMId lhs, AMMId rhs) pure returns (bool) {
    return AMMId.unwrap(lhs) == AMMId.unwrap(rhs);
}

using {_ammIdEq as ==} for AMMId global;

library AMMIdLib {
    AMMId internal constant ZERO = AMMId.wrap(0);

    function isZero(AMMId self) internal pure returns (bool) {
        return self == ZERO;
    }
}

library PMDataMemLib {
    function add(PMDataMem memory self, Side side, uint256 _size, uint256 _pm) internal pure {
        if (side == Side.LONG) {
            self.sumLongSize += _size;
            self.sumLongPM += _pm;
        } else {
            self.sumShortSize += _size;
            self.sumShortPM += _pm;
        }
    }

    function sub(PMDataMem memory self, Side side, uint256 _size, uint256 _pm) internal pure {
        if (side == Side.LONG) {
            self.sumLongSize -= _size;
            self.sumLongPM -= _pm;
        } else {
            self.sumShortSize -= _size;
            self.sumShortPM -= _pm;
        }
    }
}

library PartialDataLib {
    using PMath for int128;

    function getTrade(PartialData memory data) internal pure returns (Trade) {
        return TradeLib.from(int256(uint256(data.sumLongSize)) - int256(uint256(data.sumShortSize)), data.sumCost);
    }

    function isZero(PartialData memory data) internal pure returns (bool) {
        return data.fTag.isZero();
    }

    function isZeroStorage(PartialData storage data) internal view returns (bool) {
        return data.fTag.isZero();
    }

    function copyFromStorageAndClear(PartialData memory mem, PartialData storage sto) internal {
        if (sto.fTag.isZero()) return;
        mem.sumLongSize = sto.sumLongSize;
        mem.sumLongPM = sto.sumLongPM;
        mem.sumShortSize = sto.sumShortSize;
        mem.sumShortPM = sto.sumShortPM;
        mem.fTag = sto.fTag;
        mem.sumCost = sto.sumCost;
        sto.fTag = FTagLib.ZERO;
    }

    function addToStorageIfAllowed(
        PartialData storage sto,
        FTag fTag,
        Fill _partialFill,
        uint128 partialPM
    ) internal returns (bool) {
        Trade trade = _partialFill.toTrade();
        Side side = trade.side();
        (int128 signedSize, int128 signedCost) = trade.unpack();
        uint128 absSize = uint128(signedSize.abs());

        if (sto.fTag.isZero()) {
            sto.fTag = fTag;
            sto.sumCost = signedCost;
            if (side == Side.LONG) {
                sto.sumLongSize = absSize;
                sto.sumLongPM = partialPM;
                sto.sumShortSize = 0;
                sto.sumShortPM = 0;
            } else {
                sto.sumLongSize = 0;
                sto.sumLongPM = 0;
                sto.sumShortSize = absSize;
                sto.sumShortPM = partialPM;
            }

            return true;
        } else if (sto.fTag == fTag) {
            sto.sumCost += signedCost;
            if (side == Side.LONG) {
                sto.sumLongSize += absSize;
                sto.sumLongPM += partialPM;
            } else {
                sto.sumShortSize += absSize;
                sto.sumShortPM += partialPM;
            }
            return true;
        }
        return false;
    }
}

library AccountData2Lib {
    function from(
        int128 _signedSize,
        FTag _fTag,
        uint16 _nLongOrders,
        uint16 _nShortOrders
    ) internal pure returns (AccountData2) {
        uint192 packed = 0;
        packed = uint192(uint128(_signedSize));
        packed = (packed << 32) | _fTag.raw();
        packed = (packed << 16) | _nLongOrders;
        packed = (packed << 16) | _nShortOrders;
        return AccountData2.wrap(packed);
    }

    function unpack(
        AccountData2 data
    ) internal pure returns (int128 _signedSize, FTag _fTag, uint16 _nLongOrders, uint16 _nShortOrders) {
        uint192 packed = AccountData2.unwrap(data);

        _nShortOrders = uint16(packed);
        packed >>= 16;

        _nLongOrders = uint16(packed);
        packed >>= 16;

        _fTag = FTag.wrap(uint32(packed));
        packed >>= 32;

        _signedSize = int128(uint128(packed));
    }
}

using {_eqFIndex as ==, _neqFIndex as !=} for FIndex global;

function _eqFIndex(FIndex a, FIndex b) pure returns (bool) {
    return FIndex.unwrap(a) == FIndex.unwrap(b);
}

function _neqFIndex(FIndex a, FIndex b) pure returns (bool) {
    return FIndex.unwrap(a) != FIndex.unwrap(b);
}

library FIndexLib {
    FIndex internal constant ZERO = FIndex.wrap(0);

    function from(uint32 _fTime, int112 _floatingIndex, uint64 _feeIndex) internal pure returns (FIndex) {
        uint208 rawValue = (uint208(_fTime) << 176) | (uint208(uint112(_floatingIndex)) << 64) | uint208(_feeIndex);
        return FIndex.wrap(bytes26(rawValue));
    }

    function fTime(FIndex index) internal pure returns (uint32) {
        uint208 rawValue = uint208(FIndex.unwrap(index));
        return uint32(rawValue >> 176);
    }

    function floatingIndex(FIndex index) internal pure returns (int112) {
        uint208 rawValue = uint208(FIndex.unwrap(index));
        return int112(uint112(rawValue >> 64));
    }

    function feeIndex(FIndex index) internal pure returns (uint64) {
        uint208 rawValue = uint208(FIndex.unwrap(index));
        return uint64(rawValue);
    }

    function isZero(FIndex index) internal pure returns (bool) {
        return FIndex.unwrap(index) == 0;
    }
}

using {_eqFTag as ==, _neqFTag as !=} for FTag global;

function _eqFTag(FTag a, FTag b) pure returns (bool) {
    return FTag.unwrap(a) == FTag.unwrap(b);
}

function _neqFTag(FTag a, FTag b) pure returns (bool) {
    return FTag.unwrap(a) != FTag.unwrap(b);
}

library FTagLib {
    FTag internal constant ZERO = FTag.wrap(0);

    function raw(FTag tag) internal pure returns (uint32) {
        return FTag.unwrap(tag);
    }

    function isZero(FTag tag) internal pure returns (bool) {
        return FTag.unwrap(tag) == 0;
    }

    // @notice This function will NOT do zero check.
    function isPurge(FTag tag) internal pure returns (bool) {
        return tag.raw() % 2 == 0;
    }

    // @notice This function will NOT do zero check.
    function isFIndexUpdate(FTag tag) internal pure returns (bool) {
        return tag.raw() % 2 == 1;
    }

    function nextPurgeTag(FTag tag) internal pure returns (FTag) {
        tag = _inc(tag);
        if (!tag.isPurge()) {
            tag = _inc(tag);
        }
        return tag;
    }

    function nextFIndexUpdateTag(FTag tag) internal pure returns (FTag) {
        tag = _inc(tag);
        if (!tag.isFIndexUpdate()) {
            tag = _inc(tag);
        }
        return tag;
    }

    function _inc(FTag tag) private pure returns (FTag) {
        return FTag.wrap(tag.raw() + 1);
    }

    function min(FTag a, FTag b) internal pure returns (FTag) {
        return a.raw() < b.raw() ? a : b;
    }
}

library SweptFLib {
    function assign(SweptF memory sweptF, FTag fTag, Fill fill) internal pure {
        sweptF.fTag = fTag;
        sweptF.__fill = fill;
    }

    function getFill(SweptF memory sweptF) internal pure returns (bool isPurge, Fill fill) {
        return (sweptF.fTag.isPurge(), sweptF.__fill);
    }
}
