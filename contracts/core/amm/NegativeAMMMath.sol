// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {PMath} from "./../../lib/math/PMath.sol";

import {AMMState, AMMSeedParams, PositiveAMMMath} from "./PositiveAMMMath.sol";

library NegativeAMMMath {
    using PMath for int256;

    function calcSeedOutput(
        AMMSeedParams memory params,
        uint256 maturity,
        uint256 latestFTime
    ) internal pure returns (AMMState memory /*initialState*/) {
        params.initialSize = -params.initialSize;
        return PositiveAMMMath.calcSeedOutput(params, maturity, latestFTime);
    }

    function calcMintOutput(
        AMMState memory state,
        int256 markRate,
        int256 totalCash,
        int256 totalSize,
        int256 maxCashIn,
        int256 exactSizeIn
    ) internal pure returns (int256 /*netCashIn*/, uint256 /*netLpOut*/) {
        return PositiveAMMMath.calcMintOutput(state, -markRate, totalCash, -totalSize, maxCashIn, -exactSizeIn);
    }

    function calcBurnOutput(
        AMMState memory state,
        int256 markRate,
        int256 totalCash,
        int256 totalSize,
        uint256 lpToBurn
    ) internal pure returns (int256 netCashOut, int256 netSizeOut, bool isMatured) {
        (netCashOut, netSizeOut, isMatured) = PositiveAMMMath.calcBurnOutput(
            state,
            -markRate,
            totalCash,
            -totalSize,
            lpToBurn
        );
        netSizeOut = -netSizeOut;
    }

    function calcSwapOutput(AMMState memory state, int256 floatOut) internal pure returns (int256 fixedIn) {
        fixedIn = PositiveAMMMath.calcSwapOutput(state, -floatOut);
    }

    function calcSwapSize(AMMState memory state, int256 targetRateInt) internal pure returns (int256 swapSize) {
        swapSize = -PositiveAMMMath.calcSwapSize(state, -targetRateInt);
    }

    function calcImpliedRate(uint256 totalFloatAmount, uint256 normFixedAmount) internal pure returns (int256) {
        return -PositiveAMMMath.calcImpliedRate(totalFloatAmount, normFixedAmount);
    }
}
