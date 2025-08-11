// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

interface IFundingRateAggregator {
    enum OracleType {
        CHAIN_LINK,
        PYTH_LAZER
    }

    event MaxVerificationFeeUpdated(uint256 newMaxVerificationFee);

    event PeriodUpdated(uint32 newPeriod);

    event ThresholdUpdated(uint256 newThreshold);

    function FINDEX_ORACLE() external view returns (address);

    function CHAIN_LINK() external view returns (address);

    function CHAIN_LINK_FEED_ID() external view returns (bytes32);

    function PYTH_LAZER() external view returns (address);

    function PYTH_LAZER_FEED_ID() external view returns (uint32);

    function maxVerificationFee() external view returns (uint256);

    function period() external view returns (uint32);

    function threshold() external view returns (uint256);

    function performUpdate(bytes[] calldata reports, OracleType[] memory oracleTypes) external;

    function manualUpdate(int112 fundingRate, uint32 fundingTimestamp) external;

    function setMaxVerificationFee(uint256 newMaxVerificationFee) external;

    function setPeriod(uint32 newPeriod) external;

    function setThreshold(uint256 newThreshold) external;

    function withdraw(address receiver, uint256 amount) external;
}
