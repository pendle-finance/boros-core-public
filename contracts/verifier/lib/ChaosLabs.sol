// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {PMath} from "../../lib/math/PMath.sol";

interface IRiskOracle {
    struct RiskParameterUpdate {
        uint256 timestamp; // Timestamp of the update
        bytes newValue; // Encoded parameters, flexible for various data types
        string referenceId; // External reference, potentially linking to a document or off-chain data
        bytes previousValue; // Previous value of the parameter for historical comparison
        string updateType; // Classification of the update for validation purposes
        uint256 updateId; // Unique identifier for this specific update
        address market; // Address for market of the parameter update
        bytes additionalData; // Additional data for the update
    }

    function getUpdateById(uint256 updateId) external view returns (RiskParameterUpdate memory);
}

library ChaosLabsVerifierLib {
    function verifyFundingRateReport(
        uint256 updateId,
        address riskOracle,
        bytes32 expectedUpdateTypeHash,
        address expectedMarket,
        uint32 period,
        uint32 lastUpdatedTime
    ) internal view returns (int112 fundingRate, uint32 fundingTimestamp) {
        IRiskOracle.RiskParameterUpdate memory update = IRiskOracle(riskOracle).getUpdateById(updateId);

        require(keccak256(bytes(update.updateType)) == expectedUpdateTypeHash, "Invalid update type");
        require(update.market == expectedMarket, "Invalid market");

        (
            ,
            ,
            int256 rawFundingRate,
            uint256 fundingRateExponent,
            uint256 rawFundingTimeMs,
            uint256 rawEpochDurationMs
        ) = abi.decode(update.newValue, (string, string, int256, uint256, uint256, uint256));

        fundingRate = PMath.Int112(rawFundingRate * int256(10 ** (18 - fundingRateExponent)));
        fundingTimestamp = PMath.Uint32(rawFundingTimeMs / 1000);
        uint256 epochDuration = rawEpochDurationMs / 1000;

        require(epochDuration == period, "Invalid epoch duration");
        require(lastUpdatedTime + period == fundingTimestamp, "Invalid funding timestamp");
    }
}
