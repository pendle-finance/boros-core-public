// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Err} from "./../../lib/Errors.sol";
import {LogExpMath} from "./../../lib/math/LogExpMath.sol";
import {PMath} from "./../../lib/math/PMath.sol";

struct AMMState {
    /// abstract world
    uint256 totalFloatAmount;
    uint256 normFixedAmount;
    /// real world
    uint256 totalLp;
    /// market data
    uint256 latestFTime;
    /// immutable variables
    uint256 maturity;
    uint256 seedTime;
    /// config
    uint256 minAbsRate;
    uint256 maxAbsRate;
    uint256 cutOffTimestamp;
}

struct AMMSeedParams {
    uint256 minAbsRate;
    uint256 maxAbsRate;
    uint256 cutOffTimestamp;
    uint256 initialAbsRate;
    int256 initialSize;
    uint256 flipLiquidity;
    uint256 initialCash;
}

library PositiveAMMMath {
    using PMath for uint256;
    using PMath for int256;
    using LogExpMath for uint256;

    function calcSeedOutput(
        AMMSeedParams memory params,
        uint256 maturity,
        uint256 latestFTime
    ) internal pure returns (AMMState memory initialState) {
        uint256 totalFloatAmount = (params.initialSize + params.flipLiquidity.Int()).Uint();
        uint256 normFixedAmount = totalFloatAmount.mulDown(params.initialAbsRate);
        uint256 liquidity = (totalFloatAmount * normFixedAmount).sqrt();

        uint256 fixedValue = (normFixedAmount * (maturity - latestFTime)) / 365 days;
        require(params.initialCash > fixedValue, Err.AMMInsufficientCashIn());

        initialState = AMMState({
            totalFloatAmount: totalFloatAmount,
            normFixedAmount: normFixedAmount,
            totalLp: liquidity,
            latestFTime: latestFTime,
            maturity: maturity,
            seedTime: latestFTime,
            minAbsRate: params.minAbsRate,
            maxAbsRate: params.maxAbsRate,
            cutOffTimestamp: params.cutOffTimestamp
        });
    }

    function calcMintOutput(
        AMMState memory state,
        int256 markRate,
        int256 totalCash,
        int256 _totalSize,
        int256 maxCashIn,
        int256 exactSizeIn
    ) internal pure returns (int256 netCashIn, uint256 netLpOut) {
        bool isMatured = state.maturity <= state.latestFTime;
        require(!isMatured, Err.MarketMatured());

        assert(totalCash > 0);

        int256 totalSize = _snapSmallSizeTo0(_totalSize);

        // This also applies to sign() == 0
        require(totalSize.sign() == exactSizeIn.sign(), Err.AMMSignMismatch());

        if (totalSize == 0) {
            netLpOut = (state.totalLp * maxCashIn.Uint()) / uint256(totalCash);
            netCashIn = maxCashIn;
        } else {
            uint256 absTotalSize = totalSize.abs();
            uint256 absExactSizeIn = exactSizeIn.abs();

            bool isPositionValuePositive = totalSize.sign() == markRate.sign();
            if (isPositionValuePositive) {
                netLpOut = (state.totalLp * absExactSizeIn) / absTotalSize;
            } else {
                netLpOut = (state.totalLp * absExactSizeIn).rawDivUp(absTotalSize);
            }

            netCashIn = (uint256(totalCash) * netLpOut).rawDivUp(state.totalLp).Int();

            require(netCashIn <= maxCashIn, Err.AMMInsufficientCashIn());
        }

        state.totalFloatAmount += (state.totalFloatAmount * netLpOut) / state.totalLp;
        state.normFixedAmount += (state.normFixedAmount * netLpOut) / state.totalLp;
        state.totalLp += netLpOut;
    }

    function calcBurnOutput(
        AMMState memory state,
        int256 markRate,
        int256 totalCash,
        int256 _totalSize,
        uint256 lpToBurn
    ) internal pure returns (int256 netCashOut, int256 netSizeOut, bool isMatured) {
        netCashOut = (totalCash * lpToBurn.Int()) / state.totalLp.Int();

        isMatured = state.maturity <= state.latestFTime;
        if (isMatured) {
            return (netCashOut, 0, isMatured);
        }

        int256 totalSize = _snapSmallSizeTo0(_totalSize);
        uint256 absSizeOut;
        bool isPositionValuePositive = totalSize.sign() == markRate.sign();
        if (isPositionValuePositive) {
            absSizeOut = (totalSize.abs() * lpToBurn) / state.totalLp;
        } else {
            absSizeOut = (totalSize.abs() * lpToBurn).rawDivUp(state.totalLp);
        }
        netSizeOut = absSizeOut.Int() * totalSize.sign();

        state.totalFloatAmount -= (state.totalFloatAmount * lpToBurn) / state.totalLp;
        state.normFixedAmount -= (state.normFixedAmount * lpToBurn) / state.totalLp;
        state.totalLp -= lpToBurn;
    }

    function calcSwapOutput(AMMState memory state, int256 floatOut) internal pure returns (int256 fixedIn) {
        uint256 normalizedTime = calcNormalizedTime(state);

        uint256 newTotalFloatAmount;
        uint256 floatOutAbs = floatOut.abs();
        if (floatOut > 0) {
            // totalFloatAmount.pow(normalizedTime) does not work when totalFloatAmount = 1
            require(state.totalFloatAmount > floatOutAbs + 1, Err.AMMInsufficientLiquidity());
            unchecked {
                newTotalFloatAmount = state.totalFloatAmount - floatOutAbs;
            }
        } else {
            newTotalFloatAmount = state.totalFloatAmount + floatOutAbs;
        }

        uint256 liquidity = state.totalFloatAmount.pow(normalizedTime).mulDown(state.normFixedAmount);
        uint256 newNormFixedAmount = liquidity.divDown(newTotalFloatAmount.pow(normalizedTime));
        require(
            newNormFixedAmount * PMath.ONE >= state.minAbsRate * newTotalFloatAmount,
            Err.AMMInsufficientLiquidity()
        );
        require(
            newNormFixedAmount * PMath.ONE <= state.maxAbsRate * newTotalFloatAmount,
            Err.AMMInsufficientLiquidity()
        );
        int256 normFixedIn = newNormFixedAmount.Int() - state.normFixedAmount.Int();

        state.totalFloatAmount = newTotalFloatAmount;
        state.normFixedAmount = newNormFixedAmount;

        return normFixedIn.divDown(normalizedTime.Int());
    }

    function calcSwapSize(AMMState memory state, int256 targetRateInt) internal pure returns (int256 swapSize) {
        uint256 targetRate = clampRate(state, targetRateInt).Uint();
        uint256 normalizedTime = calcNormalizedTime(state);
        uint256 normalizedTimePlusOne = normalizedTime + PMath.ONE;
        uint256 liquidityMul1E18 = state.totalFloatAmount.pow(normalizedTime) * state.normFixedAmount;
        uint256 newTotalFloatAmount = (liquidityMul1E18 / targetRate).pow(PMath.ONE.divDown(normalizedTimePlusOne)).max(
            2
        );
        swapSize = state.totalFloatAmount.Int() - newTotalFloatAmount.Int();
    }

    function clampRate(AMMState memory state, int256 rate) internal pure returns (int256) {
        (uint256 adjustedMinAbsRate, uint256 adjustedMaxAbsRate) = tweakRate(state.minAbsRate, state.maxAbsRate);
        return rate.max(adjustedMinAbsRate.Int()).min(adjustedMaxAbsRate.Int());
    }

    uint256 internal constant RATE_TWEAK_FACTOR = 1e8;
    function tweakRate(
        uint256 minAbsRate,
        uint256 maxAbsRate
    ) internal pure returns (uint256 adjustedMinAbsRate, uint256 adjustedMaxAbsRate) {
        adjustedMinAbsRate = minAbsRate.tweakUp(RATE_TWEAK_FACTOR);
        adjustedMaxAbsRate = maxAbsRate.tweakDown(RATE_TWEAK_FACTOR);
    }

    function calcImpliedRate(uint256 totalFloatAmount, uint256 normFixedAmount) internal pure returns (int256) {
        return normFixedAmount.divDown(totalFloatAmount).Int();
    }

    function calcNormalizedTime(AMMState memory state) internal pure returns (uint256) {
        require(state.latestFTime < state.cutOffTimestamp, Err.AMMCutOffReached());
        return (state.maturity - state.latestFTime).divDown(state.maturity - state.seedTime);
    }

    function _snapSmallSizeTo0(int256 size) internal pure returns (int256) {
        return size.abs() < 1e3 ? int256(0) : size;
    }
}
