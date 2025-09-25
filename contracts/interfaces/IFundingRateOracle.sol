// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

interface IFundingRateOracle {
    struct FundingRateUpdate {
        int112 fundingRate;
        uint32 fundingTimestamp;
        uint32 epochDuration;
        uint256 updatedAt;
    }

    event FundingRateUpdated(FundingRateUpdate);

    function updateFundingRate(int112 fundingRate, uint32 fundingTimestamp, uint32 epochDuration) external;

    function name() external view returns (string memory);

    function minFundingRate() external view returns (int112);

    function maxFundingRate() external view returns (int112);

    function latestUpdate()
        external
        view
        returns (int112 fundingRate, uint32 fundingTimestamp, uint32 epochDuration, uint256 updatedAt);
}
