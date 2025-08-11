// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {PMath} from "../../lib/math/PMath.sol";

library Common {
    struct Asset {
        address assetAddress;
        uint256 amount;
    }
}

interface IVerifierProxy {
    function verify(
        bytes calldata payload,
        bytes calldata parameterPayload
    ) external payable returns (bytes memory verifierResponse);

    function s_feeManager() external view returns (address);
}

interface IFeeManager {
    function getFeeAndReward(
        address subscriber,
        bytes memory unverifiedReport,
        address quoteAddress
    ) external returns (Common.Asset memory, Common.Asset memory, uint256);

    function i_nativeAddress() external view returns (address);
}

struct ReportFundingRate {
    bytes32 feedId;
    uint32 validFromTimestamp;
    uint32 observationsTimestamp;
    uint192 nativeFee;
    uint192 linkFee;
    uint32 expiresAt;
    int192 fundingRate;
    uint32 fundingTimestamp;
    uint32 epochDuration;
}

library ChainLinkVerifierLib {
    function _verifyReportVersionAndGetFee(
        bytes memory report,
        address chainLink
    ) private returns (bytes memory /*parameterPayload*/, uint256 /*fee*/) {
        (, bytes memory reportData) = abi.decode(report, (bytes32[3], bytes));

        uint16 reportVersion = (uint16(uint8(reportData[0])) << 8) | uint16(uint8(reportData[1]));
        require(reportVersion == 5, "Invalid report version");

        IFeeManager feeManager = IFeeManager(IVerifierProxy(chainLink).s_feeManager());
        if (address(feeManager) == address(0)) {
            return ("", 0);
        }

        address feeTokenAddress = feeManager.i_nativeAddress();
        (Common.Asset memory fee, , ) = feeManager.getFeeAndReward(address(this), reportData, feeTokenAddress);
        return (abi.encode(feeTokenAddress), fee.amount);
    }

    function verifyFundingRateReport(
        bytes memory report,
        address chainLink,
        bytes32 expectedFeedId,
        uint256 maxVerificationFee,
        uint32 lastUpdatedTime,
        uint32 period
    ) internal returns (int112 fundingRate, uint32 fundingTimestamp) {
        (bytes memory parameterPayload, uint256 fee) = _verifyReportVersionAndGetFee(report, chainLink);
        require(fee <= maxVerificationFee, "Verification fee too high");

        bytes memory verifiedReportData = IVerifierProxy(chainLink).verify{value: fee}(report, parameterPayload);
        ReportFundingRate memory verifiedReport = abi.decode(verifiedReportData, (ReportFundingRate));

        require(verifiedReport.feedId == expectedFeedId, "Invalid feed id");

        fundingRate = PMath.Int112(verifiedReport.fundingRate);
        fundingTimestamp = verifiedReport.fundingTimestamp;

        require(verifiedReport.epochDuration == period, "Invalid epoch duration");
        require(lastUpdatedTime + period == fundingTimestamp, "Invalid funding timestamp");
    }
}
