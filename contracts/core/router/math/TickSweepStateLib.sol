// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IMarket} from "./../../../interfaces/IMarket.sol";
import {ArrayLib} from "./../../../lib/ArrayLib.sol";
import {PMath} from "./../../../lib/math/PMath.sol";
import {TickMath} from "./../../../lib/math/TickMath.sol";
import {Side, SideLib} from "./../../../types/Order.sol";

enum Stage {
    LOOP_BATCH,
    LOOP_SINGLE,
    BINARY_SEARCH,
    FOUND_STOP,
    SWEPT_ALL
}

struct TickSweepState {
    // iteration state
    Stage stage;
    int16[] ticks;
    uint256[] tickSizes;
    uint256 singleIndex;
    // binary search state
    uint256 bin_min;
    uint256 bin_max;
    // constants
    address market;
    Side side;
    uint16 nTicksToTryAtOnce;
    //
}

using TickSweepStateLib for TickSweepState global;

library TickSweepStateLib {
    using ArrayLib for uint256[];
    using SideLib for uint256;
    using PMath for int256;

    function create(
        address market,
        Side tickSide,
        uint16 nTicksToTryAtOnce
    ) internal view returns (TickSweepState memory res) {
        (int16[] memory ticks, uint256[] memory tickSizes) = IMarket(market).getNextNTicks(
            tickSide,
            tickSide.tickToGetFirstAvail(),
            nTicksToTryAtOnce
        );

        if (ticks.length == 0) {
            res.stage = Stage.SWEPT_ALL;
            return res;
        }

        return
            TickSweepState({
                //
                stage: Stage.LOOP_BATCH,
                ticks: ticks,
                tickSizes: tickSizes,
                singleIndex: 0,
                //
                bin_min: 0,
                bin_max: 0,
                //
                market: market,
                side: tickSide,
                nTicksToTryAtOnce: nTicksToTryAtOnce
            });
    }

    function hasMore(TickSweepState memory $) internal pure returns (bool) {
        return $.stage != Stage.FOUND_STOP && $.stage != Stage.SWEPT_ALL;
    }

    function getLastTick(TickSweepState memory $) internal pure returns (int16 lastTick) {
        if ($.stage == Stage.LOOP_BATCH) return _lastTickArray($);
        if ($.stage == Stage.LOOP_SINGLE || $.stage == Stage.BINARY_SEARCH || $.stage == Stage.FOUND_STOP) {
            return $.ticks[$.singleIndex];
        }
        assert(false);
    }

    function getLastTickAndSumSize(TickSweepState memory $) internal pure returns (int16 lastTick, uint256 sumSize) {
        if ($.stage == Stage.LOOP_BATCH) return (_lastTickArray($), $.tickSizes.sum());
        if ($.stage == Stage.LOOP_SINGLE || $.stage == Stage.FOUND_STOP) {
            return ($.ticks[$.singleIndex], $.tickSizes[$.singleIndex]);
        }
        if ($.stage == Stage.BINARY_SEARCH) {
            return ($.ticks[$.singleIndex], $.tickSizes.sum($.bin_min, $.singleIndex + 1));
        }
        assert(false);
    }

    function getSumCost(TickSweepState memory $, uint8 tickStep) internal pure returns (int256 cost) {
        if ($.stage == Stage.LOOP_BATCH) {
            for (uint256 i = 0; i < $.tickSizes.length; i++) {
                cost += _calculateTickCost($.ticks[i], $.tickSizes[i], $.side, tickStep);
            }
        } else if ($.stage == Stage.LOOP_SINGLE) {
            cost = _calculateTickCost($.ticks[$.singleIndex], $.tickSizes[$.singleIndex], $.side, tickStep);
        } else if ($.stage == Stage.BINARY_SEARCH) {
            for (uint256 i = $.bin_min; i < $.singleIndex + 1; i++) {
                cost += _calculateTickCost($.ticks[i], $.tickSizes[i], $.side, tickStep);
            }
        } else {
            assert(false);
        }
    }

    function _calculateTickCost(int16 tick, uint256 size, Side side, uint8 tickStep) private pure returns (int256) {
        return size.toSignedSize(side).mulDown(TickMath.getRateAtTick(tick, tickStep));
    }

    function transitionUp(TickSweepState memory $) internal view {
        if ($.stage == Stage.LOOP_BATCH) {
            // -> Swept all // So this is only phase where the state is changed
            _transitionUpBatch($);
        } else if ($.stage == Stage.LOOP_SINGLE) {
            // -> up one more index
            _transitionUpSingle($);
        } else if ($.stage == Stage.BINARY_SEARCH) {
            // -> up in binary search
            _transitionUpBinary($);
        } else {
            assert(false);
        }
    }

    function _transitionUpBatch(TickSweepState memory $) private view {
        if ($.ticks.length != $.nTicksToTryAtOnce || _lastTickArray($) == $.side.endTick()) {
            $.stage = Stage.SWEPT_ALL;
            return;
        }

        ($.ticks, $.tickSizes) = IMarket($.market).getNextNTicks($.side, _lastTickArray($), $.nTicksToTryAtOnce);
        if ($.ticks.length == 0) {
            // no more ticks to continue, stop
            $.stage = Stage.SWEPT_ALL;
            return;
        }

        // still has ticks to continue, no change in stage needed
    }

    function _transitionUpSingle(TickSweepState memory $) private pure {
        if (++$.singleIndex == $.ticks.length) assert(false);
    }

    function _transitionUpBinary(TickSweepState memory $) private pure {
        $.bin_min = $.singleIndex + 1;
        if ($.bin_min == $.bin_max) {
            if ($.bin_min == $.ticks.length) assert(false);
            $.singleIndex = $.bin_min;
            $.stage = Stage.FOUND_STOP;
        } else {
            $.singleIndex = PMath.avg($.bin_min, $.bin_max);
        }
    }

    function transitionDown(TickSweepState memory $) internal pure {
        if ($.stage == Stage.LOOP_BATCH) {
            // -> Single or Binary Search
            _transitionDownBatch($);
        } else if ($.stage == Stage.LOOP_SINGLE) {
            $.stage = Stage.FOUND_STOP;
        } else if ($.stage == Stage.BINARY_SEARCH) {
            _transitionDownBinary($);
        } else {
            assert(false);
        }
    }

    function _transitionDownBatch(TickSweepState memory $) private pure {
        if (!_shouldUseBinarySearch($.ticks.length)) {
            $.stage = Stage.LOOP_SINGLE;
            $.singleIndex = 0;
        } else {
            $.stage = Stage.BINARY_SEARCH;
            $.bin_min = 0;
            $.bin_max = $.ticks.length;
            $.singleIndex = PMath.avg($.bin_min, $.bin_max);
        }
    }

    function _transitionDownBinary(TickSweepState memory $) private pure {
        $.bin_max = $.singleIndex;
        if ($.bin_min == $.bin_max) {
            $.stage = Stage.FOUND_STOP;
        } else {
            $.singleIndex = PMath.avg($.bin_min, $.bin_max);
        }
    }

    function _shouldUseBinarySearch(uint256 length) internal pure returns (bool) {
        return length > 4;
    }

    function _lastTickArray(TickSweepState memory $) internal pure returns (int16 lastTick) {
        return $.ticks[$.ticks.length - 1];
    }
}
