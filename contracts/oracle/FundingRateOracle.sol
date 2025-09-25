// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IFundingRateOracle} from "../interfaces/IFundingRateOracle.sol";

contract FundingRateOracle is IFundingRateOracle, Ownable {
    error FundingRateOutOfBound();
    error FundingTimestampNotIncreasing();

    string public name;
    int112 public immutable minFundingRate;
    int112 public immutable maxFundingRate;

    FundingRateUpdate public latestUpdate;

    constructor(
        address initialOwner,
        string memory name_,
        int112 minFundingRate_,
        int112 maxFundingRate_
    ) Ownable(initialOwner) {
        name = name_;
        minFundingRate = minFundingRate_;
        maxFundingRate = maxFundingRate_;
    }

    function updateFundingRate(int112 fundingRate, uint32 fundingTimestamp, uint32 epochDuration) external onlyOwner {
        require(fundingRate >= minFundingRate && fundingRate <= maxFundingRate, FundingRateOutOfBound());
        require(fundingTimestamp > latestUpdate.fundingTimestamp, FundingTimestampNotIncreasing());

        FundingRateUpdate memory newUpdate = FundingRateUpdate({
            fundingRate: fundingRate,
            fundingTimestamp: fundingTimestamp,
            epochDuration: epochDuration,
            updatedAt: block.timestamp
        });
        latestUpdate = newUpdate;

        emit FundingRateUpdated(newUpdate);
    }
}
