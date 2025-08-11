// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {PendleRolesPlugin} from "../core/roles/PendleRoles.sol";
import {IFIndexOracle} from "../interfaces/IFIndexOracle.sol";
import {IFundingRateAggregator} from "../interfaces/IFundingRateAggregator.sol";
import {Err} from "../lib/Errors.sol";
import {ChainLinkVerifierLib} from "./verifier/ChainLink.sol";
import {PythLazerVerifierLib} from "./verifier/PythLazer.sol";

contract FundingRateAggregator is IFundingRateAggregator, PendleRolesPlugin {
    address public immutable FINDEX_ORACLE;

    address public immutable CHAIN_LINK;
    bytes32 public immutable CHAIN_LINK_FEED_ID;

    address public immutable PYTH_LAZER;
    uint32 public immutable PYTH_LAZER_FEED_ID;

    uint256 public maxVerificationFee;
    uint32 public period;
    uint256 public threshold;

    constructor(
        address permissionController_,
        address fIndexOracle_,
        address chainLink_,
        bytes32 chainLinkFeedId_,
        address pythLazer_,
        uint32 pythLazerFeedId_,
        uint256 maxVerificationFee_,
        uint32 period_,
        uint256 threshold_
    ) PendleRolesPlugin(permissionController_) {
        FINDEX_ORACLE = fIndexOracle_;

        CHAIN_LINK = chainLink_;
        CHAIN_LINK_FEED_ID = chainLinkFeedId_;

        PYTH_LAZER = pythLazer_;
        PYTH_LAZER_FEED_ID = pythLazerFeedId_;

        maxVerificationFee = maxVerificationFee_;
        period = period_;
        threshold = threshold_;
    }

    function performUpdate(bytes[] calldata reports, OracleType[] memory oracleTypes) external onlyAuthorized {
        require(reports.length >= threshold, Err.NotEnoughReports());
        require(reports.length == oracleTypes.length, Err.InvalidLength());

        for (uint256 i = 0; i < oracleTypes.length; ++i) {
            for (uint256 j = i + 1; j < oracleTypes.length; ++j) {
                require(oracleTypes[i] != oracleTypes[j], Err.DuplicateOracleType());
            }
        }

        int112[] memory fundingRates = new int112[](oracleTypes.length);
        uint32[] memory fundingTimestamps = new uint32[](oracleTypes.length);
        uint32 lastUpdatedTime = IFIndexOracle(FINDEX_ORACLE).getLatestFIndex().fTime();

        for (uint256 i = 0; i < oracleTypes.length; ++i) {
            if (oracleTypes[i] == OracleType.CHAIN_LINK) {
                (fundingRates[i], fundingTimestamps[i]) = ChainLinkVerifierLib.verifyFundingRateReport(
                    reports[i],
                    CHAIN_LINK,
                    CHAIN_LINK_FEED_ID,
                    maxVerificationFee,
                    lastUpdatedTime,
                    period
                );
            } else if (oracleTypes[i] == OracleType.PYTH_LAZER) {
                (fundingRates[i], fundingTimestamps[i]) = PythLazerVerifierLib.verifyFundingRateReport(
                    reports[i],
                    PYTH_LAZER,
                    PYTH_LAZER_FEED_ID,
                    maxVerificationFee,
                    lastUpdatedTime,
                    period
                );
            } else {
                assert(false);
            }
        }

        for (uint256 i = 1; i < oracleTypes.length; ++i) {
            require(fundingTimestamps[i] == fundingTimestamps[0], Err.FundingTimestampMismatch());
            require(fundingRates[i] == fundingRates[0], Err.FundingRateMismatch());
        }

        IFIndexOracle(FINDEX_ORACLE).updateFloatingIndex(fundingRates[0], fundingTimestamps[0]);
    }

    function manualUpdate(int112 fundingRate, uint32 fundingTimestamp) external onlyAuthorized {
        IFIndexOracle(FINDEX_ORACLE).updateFloatingIndex(fundingRate, fundingTimestamp);
    }

    function setMaxVerificationFee(uint256 newMaxVerificationFee) external onlyAuthorized {
        maxVerificationFee = newMaxVerificationFee;
        emit MaxVerificationFeeUpdated(newMaxVerificationFee);
    }

    function setPeriod(uint32 newPeriod) external onlyAuthorized {
        period = newPeriod;
        emit PeriodUpdated(newPeriod);
    }

    function setThreshold(uint256 newThreshold) external onlyAuthorized {
        threshold = newThreshold;
        emit ThresholdUpdated(newThreshold);
    }

    function withdraw(address receiver, uint256 amount) external onlyAuthorized {
        (bool success, ) = payable(receiver).call{value: amount}("");
        require(success, "ETH transfer failed");
    }

    receive() external payable {}
}
