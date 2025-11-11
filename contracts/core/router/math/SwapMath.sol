// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Err} from "./../../../lib/Errors.sol";
import {PMath} from "./../../../lib/math/PMath.sol";
import {TickMath} from "./../../../lib/math/TickMath.sol";
import {MarketAcc} from "./../../../types/Account.sol";
import {Side, SideLib} from "./../../../types/Order.sol";
import {TickSweepState, TickSweepStateLib, Stage} from "./TickSweepStateLib.sol";
import {IMarket} from "./../../../interfaces/IMarket.sol";
import {IAMM} from "./../../../interfaces/IAMM.sol";
import {PaymentLib} from "./../../../lib/PaymentLib.sol";

struct SwapMathParams {
    address market;
    MarketAcc user;
    MarketAcc amm;
    Side userSide;
    uint256 takerFeeRate;
    uint256 ammOtcFeeRate;
    uint256 ammAllInFeeRate;
    uint8 tickStep;
    uint16 nTicksToTryAtOnce;
    uint32 timeToMat;
}

using SwapMathLib for SwapMathParams global;
using SwapMathHighLevelLib for SwapMathParams global;

library SwapMathLib {
    using PMath for uint256;
    using PMath for int256;
    using SideLib for int256;
    using TickMath for int16;

    function create(
        address market_,
        uint8 tickStep,
        uint16 nTicksToTryAtOnce,
        MarketAcc user_,
        MarketAcc amm_,
        Side userSide,
        uint32 timeToMat
    ) internal view returns (SwapMathParams memory params) {
        if (amm_.isZero()) return params;

        require(timeToMat > 0, Err.MarketMatured());

        (uint256 takerFeeRate, uint256 ammOtcFeeRate) = IMarket(market_).getBestFeeRates(user_, amm_);

        return
            SwapMathParams({
                market: market_,
                user: user_,
                amm: amm_,
                userSide: userSide,
                takerFeeRate: takerFeeRate,
                ammOtcFeeRate: ammOtcFeeRate,
                ammAllInFeeRate: ammOtcFeeRate + IAMM(amm_.root()).feeRate(),
                tickStep: tickStep,
                nTicksToTryAtOnce: nTicksToTryAtOnce,
                timeToMat: timeToMat
            });
    }

    /// @notice Swaps as much as possible with AMM as long as its implied rate
    /// is better than the fee-adjusted rate corresponding to bookTick,
    /// pushing AMM rate to (but not necessary ending up at) that adjusted rate.
    /// Returns 0 when AMM is not swappable (e.g. after cutoff, AMM is withdraw-only).
    /// @dev See docs for IAMM.calcSwapSize
    function calcSwapAMMToBookTick(
        SwapMathParams memory self,
        int16 bookTick
    ) internal view returns (int256 /*swapSize*/) {
        int256 baseRate = convertBookTickToBaseRate(self, bookTick);
        int256 ammRate = convertBaseRateToAMMRate(self, baseRate);
        int256 swapSize = IAMM(self.amm.root()).calcSwapSize(ammRate);
        return swapSize.isOfSide(self.userSide) ? swapSize : int256(0);
    }

    function calcAmmOtcFee(SwapMathParams memory self, int256 swapSize) internal pure returns (uint256 /*fee*/) {
        return PaymentLib.calcFloatingFee(swapSize.abs(), self.ammOtcFeeRate, self.timeToMat);
    }

    function calcBookTakerFee(SwapMathParams memory self, int256 swapSize) internal pure returns (uint256 /*fee*/) {
        return PaymentLib.calcFloatingFee(swapSize.abs(), self.takerFeeRate, self.timeToMat);
    }

    function calcSwapAMM(
        SwapMathParams memory self,
        int256 ammSwapSize
    ) internal view returns (int256 netCashIn, int256 netCashToAMM) {
        if (ammSwapSize == 0) return (0, 0);
        int256 ammCost = IAMM(self.amm.root()).swapView(ammSwapSize);
        netCashToAMM = PaymentLib.calcUpfrontFixedCost(ammCost, self.timeToMat);
        netCashIn = netCashToAMM + self.calcAmmOtcFee(ammSwapSize).Int();
    }

    function calcSwapBook(
        SwapMathParams memory self,
        int256 bookSwapSize,
        int256 bookCost
    ) internal pure returns (int256 /*netCashIn*/) {
        return PaymentLib.calcUpfrontFixedCost(bookCost, self.timeToMat) + self.calcBookTakerFee(bookSwapSize).Int();
    }

    function convertBookTickToBaseRate(SwapMathParams memory self, int16 bookTick) internal pure returns (int256) {
        int256 bookRate = bookTick.getRateAtTick(self.tickStep);
        return self.userSide == Side.LONG ? bookRate + int256(self.takerFeeRate) : bookRate - int256(self.takerFeeRate);
    }

    function convertBaseRateToAMMRate(SwapMathParams memory self, int256 baseRate) private pure returns (int256) {
        return
            self.userSide == Side.LONG
                ? baseRate - int256(self.ammAllInFeeRate)
                : baseRate + int256(self.ammAllInFeeRate);
    }
}

library SwapMathHighLevelLib {
    using PMath for uint256;
    using PMath for int256;
    using SideLib for uint256;

    /**
     * sweepState starts with either swept_all or loop_batch
     * it breaks when either swept_all or found_stop
     * For transition up, single & binary moves the iterator, batch to either swept_all or found_stop or continue batch
     * For transition down, single & binary moves the iterator, batch to either swept_all or found_stop or continue batch
     */
    function calcSwapAmountBookAMM(
        SwapMathParams memory $,
        int256 totalSize,
        int16 limitTick
    ) internal view returns (int256 withBook, int256 withAMM) {
        if ($.amm.isZero() || totalSize == 0) return (0, 0);

        Side matchingSide = $.userSide.opposite();
        TickSweepState memory sweep = TickSweepStateLib.create($.market, matchingSide, $.nTicksToTryAtOnce);

        while (sweep.hasMore()) {
            (int16 lastTick, uint256 sumTickSize) = sweep.getLastTickAndSumSize();
            if (!matchingSide.canMatch(limitTick, lastTick)) {
                sweep.transitionDown();
                continue;
            }

            int256 tmpWithAMM = $.calcSwapAMMToBookTick(lastTick);
            int256 tmpWithBook = withBook + sumTickSize.toSignedSize($.userSide);
            int256 newTotalSize = tmpWithBook + tmpWithAMM;

            if (newTotalSize == totalSize) return (tmpWithBook, tmpWithAMM);
            if (newTotalSize.abs() > totalSize.abs()) sweep.transitionDown();
            else {
                withBook = tmpWithBook;
                sweep.transitionUp();
            }
        }

        return _calcFinalSwapAmount($, sweep, withBook, totalSize, limitTick);
    }

    function _calcFinalSwapAmount(
        SwapMathParams memory $,
        TickSweepState memory sweepState,
        int256 withBook,
        int256 totalSize,
        int16 limitTick
    ) private view returns (int256, int256) {
        int16 finalTick = _getFinalTick($, sweepState, limitTick);
        int256 maxWithAMM = $.calcSwapAMMToBookTick(finalTick);
        int256 withAMM = PMath.min((totalSize - withBook).abs(), maxWithAMM.abs()).toSignedSize($.userSide);
        return (totalSize - withAMM, withAMM);
    }

    function _getFinalTick(
        SwapMathParams memory $,
        TickSweepState memory sweepState,
        int16 limitTick
    ) private pure returns (int16 finalTick) {
        if (sweepState.stage == Stage.FOUND_STOP) {
            int16 lastTick = sweepState.getLastTick();
            Side matchingSide = $.userSide.opposite();
            return matchingSide.canMatch(limitTick, lastTick) ? lastTick : limitTick;
        } else if (sweepState.stage == Stage.SWEPT_ALL) {
            return limitTick;
        }
        assert(false);
    }
}
