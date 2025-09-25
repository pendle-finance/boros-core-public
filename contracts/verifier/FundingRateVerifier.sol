// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {PendleRolesPlugin} from "../core/roles/PendleRoles.sol";
import {IFIndexOracle} from "../interfaces/IFIndexOracle.sol";
import {IFundingRateVerifier} from "../interfaces/IFundingRateVerifier.sol";
import {ChainlinkVerifierLib} from "./lib/Chainlink.sol";
import {ChaosLabsVerifierLib} from "./lib/ChaosLabs.sol";
import {PendleVerifierLib} from "./lib/Pendle.sol";

contract FundingRateVerifier is IFundingRateVerifier, PendleRolesPlugin {
    struct OracleConfig {
        address fIndexOracle;
        //
        address chainlinkOracle;
        bytes32 chainlinkFeedId;
        //
        address chaosLabsOracle;
        bytes32 chaosLabsUpdateTypeHash;
        address chaosLabsMarket;
        //
        address pendleOracle;
    }

    address public immutable FINDEX_ORACLE;

    address public immutable CHAIN_LINK_ORACLE;
    bytes32 public immutable CHAIN_LINK_FEED_ID;

    address public immutable CHAOS_LABS_ORACLE;
    bytes32 public immutable CHAOS_LABS_UPDATE_TYPE_HASH;
    address public immutable CHAOS_LABS_MARKET;

    address public immutable PENDLE_ORACLE;

    uint256 public maxVerificationFee;
    uint32 public period;

    constructor(
        address permissionController_,
        OracleConfig memory oracleConfig_,
        uint256 maxVerificationFee_,
        uint32 period_
    ) PendleRolesPlugin(permissionController_) {
        FINDEX_ORACLE = oracleConfig_.fIndexOracle;
        CHAIN_LINK_ORACLE = oracleConfig_.chainlinkOracle;
        CHAIN_LINK_FEED_ID = oracleConfig_.chainlinkFeedId;
        CHAOS_LABS_ORACLE = oracleConfig_.chaosLabsOracle;
        CHAOS_LABS_UPDATE_TYPE_HASH = oracleConfig_.chaosLabsUpdateTypeHash;
        CHAOS_LABS_MARKET = oracleConfig_.chaosLabsMarket;
        PENDLE_ORACLE = oracleConfig_.pendleOracle;
        maxVerificationFee = maxVerificationFee_;
        period = period_;
    }

    function updateWithChainlink(bytes memory report) external onlyAuthorized {
        uint32 lastUpdatedTime = IFIndexOracle(FINDEX_ORACLE).getLatestFIndex().fTime();

        (int112 fundingRate, uint32 fundingTimestamp) = ChainlinkVerifierLib.verifyFundingRateReport(
            report,
            CHAIN_LINK_ORACLE,
            CHAIN_LINK_FEED_ID,
            maxVerificationFee,
            period,
            lastUpdatedTime
        );

        IFIndexOracle(FINDEX_ORACLE).updateFloatingIndex(fundingRate, fundingTimestamp);
    }

    function updateWithChaosLabs(uint256 updateId) external onlyAuthorized {
        uint32 lastUpdatedTime = IFIndexOracle(FINDEX_ORACLE).getLatestFIndex().fTime();

        (int112 fundingRate, uint32 fundingTimestamp) = ChaosLabsVerifierLib.verifyFundingRateReport(
            updateId,
            CHAOS_LABS_ORACLE,
            CHAOS_LABS_UPDATE_TYPE_HASH,
            CHAOS_LABS_MARKET,
            period,
            lastUpdatedTime
        );

        IFIndexOracle(FINDEX_ORACLE).updateFloatingIndex(fundingRate, fundingTimestamp);
    }

    function updateWithPendle() external onlyAuthorized {
        uint32 lastUpdatedTime = IFIndexOracle(FINDEX_ORACLE).getLatestFIndex().fTime();

        (int112 fundingRate, uint32 fundingTimestamp) = PendleVerifierLib.verifyFundingRateReport(
            PENDLE_ORACLE,
            period,
            lastUpdatedTime
        );

        IFIndexOracle(FINDEX_ORACLE).updateFloatingIndex(fundingRate, fundingTimestamp);
    }

    function manualUpdate(int112 fundingRate, uint32 fundingTimestamp) external onlyAuthorized {
        IFIndexOracle(FINDEX_ORACLE).updateFloatingIndex(fundingRate, fundingTimestamp);
    }

    function setConfig(uint256 newMaxVerificationFee, uint32 newPeriod) external onlyAuthorized {
        maxVerificationFee = newMaxVerificationFee;
        period = newPeriod;
        emit ConfigUpdated(newMaxVerificationFee, newPeriod);
    }

    function withdraw(address receiver, uint256 amount) external onlyAuthorized {
        (bool success, ) = payable(receiver).call{value: amount}("");
        require(success, "ETH transfer failed");
    }

    receive() external payable {}
}
