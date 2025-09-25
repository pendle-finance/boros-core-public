// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IFundingRateOracle} from "../../interfaces/IFundingRateOracle.sol";

library PendleVerifierLib {
    function verifyFundingRateReport(
        address oracle,
        uint32 period,
        uint32 lastUpdatedTime
    ) internal view returns (int112 fundingRate, uint32 fundingTimestamp) {
        uint32 epochDuration;
        (fundingRate, fundingTimestamp, epochDuration, ) = IFundingRateOracle(oracle).latestUpdate();

        require(epochDuration == period, "Invalid epoch duration");
        require(lastUpdatedTime + period == fundingTimestamp, "Invalid funding timestamp");
    }
}
