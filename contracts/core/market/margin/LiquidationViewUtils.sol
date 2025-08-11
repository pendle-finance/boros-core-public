// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

// Libraries
import {PMath} from "../../../lib/math/PMath.sol";
import {Err} from "../../../lib/Errors.sol";
import {Trade, TradeLib} from "../../../types/Trade.sol";
import {MarginViewUtils} from "./MarginViewUtils.sol";

abstract contract LiquidationViewUtils is MarginViewUtils {
    using PMath for int256;
    using PMath for uint256;

    function _calcLiqTradeAft(
        MarketMem memory market,
        UserMem memory vio,
        int256 sizeToLiq,
        int256 healthRatio
    ) internal view returns (Trade /*liqTrade*/, uint64 /*liqFeeRate*/) {
        require(0 <= healthRatio && healthRatio < PMath.IONE && sizeToLiq != 0, Err.MarketInvalidLiquidation());

        (uint256 incentiveFactor, uint64 liqFeeRate) = _getLiqSettings(healthRatio);

        uint64 kMM = _kMM(vio.addr);
        uint256 deltaMM = _calcMM(market, vio.signedSize, kMM) - _calcMM(market, vio.signedSize - sizeToLiq, kMM);

        uint256 incentive = deltaMM.mulDown(incentiveFactor);
        uint256 annualizedIncentive = (incentive * 365 days) / market.timeToMat;

        return (TradeLib.from(sizeToLiq, sizeToLiq.mulCeil(market.rMark) - annualizedIncentive.Int()), liqFeeRate);
    }

    function _getLiqSettings(
        int256 healthRatio
    ) internal view returns (uint256 /*incentiveFactor*/, uint64 /*liqFeeRate*/) {
        LiqSettings memory liqSettings = _ctx().liqSettings;
        uint256 healthRatioUint = uint256(healthRatio); // 0 <= healthRatio < 1
        uint256 k = liqSettings.base + uint256(liqSettings.slope).mulDown(PMath.ONE - healthRatioUint);
        return (PMath.min(k, healthRatioUint), liqSettings.feeRate);
    }

    function _calcDelevTradeAft(
        MarketMem memory market,
        UserMem memory lose,
        int256 sizeToWin,
        int256 loseValue,
        uint256 alpha
    ) internal pure returns (Trade /*delevTrade*/) {
        require(0 <= alpha && alpha <= PMath.ONE && sizeToWin != 0, Err.MarketInvalidDeleverage());

        if (loseValue >= 0) {
            return TradeLib.from(sizeToWin, sizeToWin.mulCeil(market.rMark));
        }

        int256 lossFactor = (int256(alpha) * sizeToWin).rawDivCeil(lose.signedSize);
        int256 loss = loseValue.mulFloor(lossFactor);
        int256 annualizedLoss = (loss * 365 days).rawDivFloor(int256(uint256(market.timeToMat)));

        return TradeLib.from(sizeToWin, sizeToWin.mulCeil(market.rMark) - annualizedLoss);
    }

    function _isReducedOnly(int256 curSize, int256 newTradeSize) internal pure returns (bool) {
        return newTradeSize.abs() <= curSize.abs() && newTradeSize.sign() * curSize.sign() <= 0;
    }
}
