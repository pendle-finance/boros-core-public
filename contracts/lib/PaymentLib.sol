// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {PMath} from "./math/PMath.sol";
import {FIndex, PayFee, PayFeeLib as PLib, Trade} from "../types/MarketTypes.sol";

library PaymentLib {
    using PMath for uint256;
    using PMath for int256;

    function calcFloatingFee(uint256 absSize, uint256 feeRate, uint32 timeToMat) internal pure returns (uint256) {
        return (absSize * feeRate * timeToMat).rawDivUp(PMath.ONE_MUL_YEAR);
    }

    function calcSettlement(int256 signedSize, FIndex last, FIndex current) internal pure returns (PayFee res) {
        if (last == current) return PLib.ZERO;

        res = PLib.from(
            signedSize.mulFloor(current.floatingIndex() - last.floatingIndex()),
            signedSize.abs().mulUp(current.feeIndex() - last.feeIndex())
        );
    }

    function calcUpfrontFixedCost(int256 cost, uint32 timeToMat) internal pure returns (int256) {
        return (cost * int256(uint256(timeToMat))).rawDivCeil(PMath.IONE_YEAR);
    }

    function toUpfrontFixedCost(Trade trade, uint32 timeToMat) internal pure returns (int256) {
        return calcUpfrontFixedCost(trade.signedCost(), timeToMat);
    }

    function calcPositionValue(int256 signedSize, int256 markRate, uint32 timeToMat) internal pure returns (int256) {
        return (signedSize * markRate * int256(uint256(timeToMat))).rawDivFloor(PMath.IONE_MUL_YEAR);
    }

    function calcNewFeeIndex(uint64 oldFeeIndex, uint256 feeRate, uint32 timePassed) internal pure returns (uint64) {
        return oldFeeIndex + calcFloatingFee(PMath.ONE, feeRate, timePassed).Uint64();
    }
}
