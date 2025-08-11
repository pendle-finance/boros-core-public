// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {PMath} from "../../../lib/math/PMath.sol";
import {TickMath} from "./../../../lib/math/TickMath.sol";
import {Side, SideLib} from "../../../types/Order.sol";
import {TickSweepState, TickSweepStateLib, Stage} from "./TickSweepStateLib.sol";
import {SwapMathParams} from "./SwapMath.sol";

struct LiquidityMathParams {
    SwapMathParams _core;
    uint256 maxIteration;
    uint256 eps;
    int256 ammCash;
    int256 ammSize;
    int256 totalCashIn;
}

using LiquidityMathLib for LiquidityMathParams global;

// * Note that for LiquidityMathLib, userSide == ammSide since users are swapping to add liquidity to amm
library LiquidityMathLib {
    using PMath for int256;
    using PMath for uint256;
    using SideLib for uint256;
    using TickMath for int16;

    enum State {
        SWAP_LESS_SIZE,
        SWAP_MORE_SIZE,
        SATISFIED
    }

    /**
     * sweepState starts with either swept_all or loop_batch
     * it breaks when either swept_all or found_stop
     * For transition up, single & binary moves the iterator, batch to either swept_all or found_stop or continue batch
     * For transition down, single & binary moves the iterator, batch to either swept_all or found_stop or continue batch
     */
    function approxSwapToAddLiquidity(
        LiquidityMathParams memory $
    ) internal view returns (int256 withBook, int256 withAMM) {
        if ($.ammSize == 0) return (0, 0);

        SwapMathParams memory core = $._core;

        TickSweepState memory sweep = TickSweepStateLib.create(
            core.market,
            core.userSide.opposite(),
            core.nTicksToTryAtOnce
        );

        int256 sumBookCost = 0;
        while (sweep.hasMore()) {
            (int16 lastTick, uint256 sumTickSize) = sweep.getLastTickAndSumSize();
            int256 tmpWithAMM = core.calcSwapAMMToBookTick(lastTick);
            int256 tmpWithBook = withBook + sumTickSize.toSignedSize(core.userSide);
            int256 tmpBookCost = sumBookCost - sweep.getSumCost(core.tickStep); // subtract since getSumCost returns cost of opposite side

            State res = _trySwap($, tmpWithAMM, tmpWithBook, tmpBookCost);

            if (res == State.SATISFIED) {
                return (tmpWithBook, tmpWithAMM);
            } else if (res == State.SWAP_MORE_SIZE) {
                (withAMM, withBook, sumBookCost) = (tmpWithAMM, tmpWithBook, tmpBookCost);
                sweep.transitionUp();
            } else {
                sweep.transitionDown();
            }
        }

        return _calcFinalLiquidity($, sweep, withBook, withAMM, sumBookCost);
    }

    struct Aux {
        LiquidityMathParams $;
        TickSweepState sweep;
        int256 curWithBook;
        int256 curWithAMM;
        int256 curBookCost;
        int256 bookRate;
        uint256 maxAbsMoreWithAMM;
    }

    function _calcFinalLiquidity(
        LiquidityMathParams memory _$,
        TickSweepState memory _sweep,
        int256 _curWithBook,
        int256 _curWithAMM,
        int256 _curBookCost
    ) private view returns (int256 /*finalWithBook*/, int256 /*finalWithAMM*/) {
        (int256 _bookRate, uint256 _maxAbsMoreWithAMM, uint256 guessMax) = _getBinSearchParams(_$, _sweep, _curWithAMM);

        Aux memory aux = Aux({
            $: _$,
            sweep: _sweep,
            curWithBook: _curWithBook,
            curWithAMM: _curWithAMM,
            curBookCost: _curBookCost,
            bookRate: _bookRate,
            maxAbsMoreWithAMM: _maxAbsMoreWithAMM
        });

        Side _userSide = aux.$.userSide();
        uint256 guessMin = 0;

        for (uint256 i = 0; i < aux.$.maxIteration; i++) {
            uint256 guess = PMath.avg(guessMin, guessMax);

            uint256 absMoreWithAMM = PMath.min(guess, aux.maxAbsMoreWithAMM);
            int256 tmpWithAMM = aux.curWithAMM + absMoreWithAMM.toSignedSize(_userSide);

            int256 moreWithBook = (guess - absMoreWithAMM).toSignedSize(_userSide);
            int256 tmpWithBook = aux.curWithBook + moreWithBook;
            int256 tmpBookCost = aux.curBookCost + moreWithBook.mulDown(aux.bookRate);

            State res = _trySwap(aux.$, tmpWithAMM, tmpWithBook, tmpBookCost);

            if (res == State.SATISFIED) return (tmpWithBook, tmpWithAMM);
            else if (res == State.SWAP_MORE_SIZE) guessMin = guess + 1;
            else guessMax = guess - 1;
        }

        revert("Slippage: APPROX_EXHAUSTED");
    }

    function _getBinSearchParams(
        LiquidityMathParams memory $,
        TickSweepState memory sweep,
        int256 withAMM
    ) private view returns (int256 bookRate, uint256 maxAbsMoreWithAMM, uint256 guessMax) {
        if (sweep.stage == Stage.FOUND_STOP) {
            (int16 lastTick, uint256 tickSize) = sweep.getLastTickAndSumSize();
            bookRate = lastTick.getRateAtTick($._core.tickStep);
            int256 maxWithAMM = $._core.calcSwapAMMToBookTick(lastTick);
            maxAbsMoreWithAMM = maxWithAMM.abs() - withAMM.abs();
            guessMax = maxAbsMoreWithAMM + tickSize;
        } else {
            bookRate = 0; // if this case, then guess <= guessMax <= maxAbsMoreWithAMM => moreWithBook = 0 for all cases
            maxAbsMoreWithAMM = $.ammSize.abs() - withAMM.abs();
            guessMax = maxAbsMoreWithAMM;
        }
    }

    function _trySwap(
        LiquidityMathParams memory $,
        int256 ammSwapSize,
        int256 bookSwapSize,
        int256 bookCost
    ) private view returns (State) {
        if (ammSwapSize.abs() >= $.ammSize.abs()) return State.SWAP_LESS_SIZE;

        int256 netSizeOut = bookSwapSize + ammSwapSize;

        (int256 netCashIn, int256 cashToAMM) = $._core.calcSwapAMM(ammSwapSize); // swap with AMM
        if (bookSwapSize != 0) netCashIn += $._core.calcSwapBook(bookSwapSize, bookCost); // place order on book
        netCashIn += $._core.calcAmmOtcFee(netSizeOut).Int(); // mintOtcFee

        if (netCashIn >= $.totalCashIn) return State.SWAP_LESS_SIZE;

        uint256 sizeNumerator = (netSizeOut * ($.ammCash + cashToAMM)).abs();
        uint256 cashNumerator = (($.totalCashIn - netCashIn) * ($.ammSize - ammSwapSize)).abs();

        // Since we require size to be used completely, sizeNumerator <= cashNumerator is a must. Hence this condition must come first
        if (sizeNumerator > cashNumerator) return State.SWAP_LESS_SIZE;

        if (PMath.isASmallerApproxB(sizeNumerator, cashNumerator, $.eps)) return State.SATISFIED;

        return State.SWAP_MORE_SIZE;
    }

    function userSide(LiquidityMathParams memory $) internal pure returns (Side) {
        return $._core.userSide;
    }

    function timeToMat(LiquidityMathParams memory $) internal pure returns (uint32) {
        return $._core.timeToMat;
    }
}
