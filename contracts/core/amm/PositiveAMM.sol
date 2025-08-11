// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {AMMCreateParams} from "./../../interfaces/IAMMFactory.sol";
import {IMarket} from "./../../interfaces/IMarket.sol";
import {AMMState, PositiveAMMMath} from "./PositiveAMMMath.sol";
import {BaseAMM} from "./BaseAMM.sol";

contract PositiveAMM is BaseAMM {
    using PositiveAMMMath for AMMState;

    constructor(
        AMMCreateParams memory createParams,
        AMMState memory initialState
    ) BaseAMM(createParams, initialState) {}

    function _mint(
        int256 totalCash,
        int256 totalSize,
        int256 maxCashIn,
        int256 exactSizeIn
    ) internal override returns (int256 netCashIn, uint256 netLpOut) {
        AMMState memory state = _readState();
        int256 markRate = IMarket(MARKET).getMarkRate();
        (netCashIn, netLpOut) = state.calcMintOutput(markRate, totalCash, totalSize, maxCashIn, exactSizeIn);
        _writeState(state);
    }

    function _burn(
        int256 totalCash,
        int256 totalSize,
        uint256 lpToBurn
    ) internal override returns (int256 netCashOut, int256 netSizeOut, bool isMatured) {
        AMMState memory state = _readState();
        int256 markRate = IMarket(MARKET).getMarkRate();
        (netCashOut, netSizeOut, isMatured) = state.calcBurnOutput(markRate, totalCash, totalSize, lpToBurn);
        _writeState(state);
    }

    function _swap(int256 sizeOut) internal override returns (int256 costOut) {
        AMMState memory state = _readState();
        costOut = state.calcSwapOutput(sizeOut);
        _writeState(state);
    }

    /// -- View functions --

    function _swapView(int256 sizeOut) internal view override returns (int256 costOut) {
        AMMState memory state = _readState();
        costOut = state.calcSwapOutput(sizeOut);
    }

    function _calcSwapSize(int256 targetRate) internal view override returns (int256) {
        AMMState memory state = _readState();
        return state.calcSwapSize(targetRate);
    }

    function _calcImpliedRate() internal view override returns (int256) {
        return PositiveAMMMath.calcImpliedRate(_storage.totalFloatAmount, _storage.normFixedAmount);
    }
}
