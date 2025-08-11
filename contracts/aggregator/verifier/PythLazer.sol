// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {PMath} from "../../lib/math/PMath.sol";

interface IPythLazer {
    function verification_fee() external view returns (uint256);

    function verifyUpdate(bytes calldata update) external payable returns (bytes calldata payload, address signer);
}

library PythLazerLib {
    enum PriceFeedProperty {
        Price,
        BestBidPrice,
        BestAskPrice,
        PublisherCount,
        Exponent,
        Confidence,
        FundingRate,
        FundingTimestamp
    }

    enum Channel {
        Invalid,
        RealTime,
        FixedRate50,
        FixedRate200
    }

    function parsePayloadHeader(
        bytes memory update
    ) internal pure returns (uint64 timestamp, Channel channel, uint8 feedsLen, uint16 pos) {
        uint32 FORMAT_MAGIC = 2479346549;

        pos = 0;
        uint32 magic = uint32(bytes4(slice(update, pos, pos + 4)));
        pos += 4;
        require(magic == FORMAT_MAGIC, "invalid magic");
        timestamp = uint64(bytes8(slice(update, pos, pos + 8)));
        pos += 8;
        channel = Channel(uint8(update[pos]));
        pos += 1;
        feedsLen = uint8(update[pos]);
        pos += 1;
    }

    function parseFeedHeader(
        bytes memory update,
        uint16 pos
    ) internal pure returns (uint32 feed_id, uint8 num_properties, uint16 new_pos) {
        feed_id = uint32(bytes4(slice(update, pos, pos + 4)));
        pos += 4;
        num_properties = uint8(update[pos]);
        pos += 1;
        new_pos = pos;
    }

    function parseFeedProperty(
        bytes memory update,
        uint16 pos
    ) internal pure returns (PriceFeedProperty property, uint16 new_pos) {
        property = PriceFeedProperty(uint8(update[pos]));
        pos += 1;
        new_pos = pos;
    }

    function parseFeedValueInt16(bytes memory update, uint16 pos) internal pure returns (int16 value, uint16 new_pos) {
        value = int16(uint16(bytes2(slice(update, pos, pos + 2))));
        pos += 2;
        new_pos = pos;
    }

    function parseFeedValueInt64(bytes memory update, uint16 pos) internal pure returns (int64 value, uint16 new_pos) {
        value = int64(uint64(bytes8(slice(update, pos, pos + 8))));
        pos += 8;
        new_pos = pos;
    }

    function parseFeedValueUint64(
        bytes memory update,
        uint16 pos
    ) internal pure returns (uint64 value, uint16 new_pos) {
        value = uint64(bytes8(slice(update, pos, pos + 8)));
        pos += 8;
        new_pos = pos;
    }

    function slice(bytes memory buffer, uint256 start, uint256 end) private pure returns (bytes memory) {
        uint256 length = buffer.length;
        require(start <= end && end <= length, "Invalid slice");

        bytes memory result = new bytes(end - start);
        assembly ("memory-safe") {
            mcopy(add(result, 0x20), add(buffer, add(start, 0x20)), sub(end, start))
        }

        return result;
    }
}

library PythLazerVerifierLib {
    using PMath for int16;
    using PMath for uint64;

    function verifyFundingRateReport(
        bytes memory report,
        address pythLazer,
        uint32 expectedFeedId,
        uint256 maxVerificationFee,
        uint32 lastUpdatedTime,
        uint32 period
    ) internal returns (int112 fundingRate, uint32 fundingTimestamp) {
        uint256 verification_fee = IPythLazer(pythLazer).verification_fee();
        require(verification_fee <= maxVerificationFee, "Verification fee too high");

        (bytes memory payload, ) = IPythLazer(pythLazer).verifyUpdate{value: verification_fee}(report);

        uint16 pos;
        uint8 numProperties;

        {
            uint8 feedsLen;
            (, , feedsLen, pos) = PythLazerLib.parsePayloadHeader(payload);
            require(feedsLen == 1, "Invalid payload");
        }

        {
            uint32 feedId;
            (feedId, numProperties, pos) = PythLazerLib.parseFeedHeader(payload, pos);
            require(feedId == expectedFeedId, "Invalid feed id");
        }

        int16 rawExponent;
        int64 rawFundingRate;
        uint64 rawFundingTimestamp;

        {
            bool hasExponent = false;
            bool hasFundingRate = false;
            bool hasFundingTimestamp = false;
            for (uint256 i = 0; i < numProperties; ++i) {
                PythLazerLib.PriceFeedProperty property;
                (property, pos) = PythLazerLib.parseFeedProperty(payload, pos);
                if (property == PythLazerLib.PriceFeedProperty.Exponent) {
                    hasExponent = true;
                    (rawExponent, pos) = PythLazerLib.parseFeedValueInt16(payload, pos);
                } else if (property == PythLazerLib.PriceFeedProperty.FundingRate) {
                    hasFundingRate = true;
                    require(uint8(payload[pos]) == 1, "Invalid payload");
                    (rawFundingRate, pos) = PythLazerLib.parseFeedValueInt64(payload, pos + 1);
                } else if (property == PythLazerLib.PriceFeedProperty.FundingTimestamp) {
                    hasFundingTimestamp = true;
                    require(uint8(payload[pos]) == 1, "Invalid payload");
                    (rawFundingTimestamp, pos) = PythLazerLib.parseFeedValueUint64(payload, pos + 1);
                } else {
                    revert("Unknown property");
                }
            }
            require(hasExponent && hasFundingRate && hasFundingTimestamp, "Missing properties");
        }

        uint256 exponent = (18 + rawExponent).Uint();
        require(exponent <= 18, "Scaling decimals too large");
        fundingRate = int112(rawFundingRate) * int112(uint112(10 ** exponent));
        fundingTimestamp = (rawFundingTimestamp / 10 ** 6).Uint32();

        require(lastUpdatedTime + period == fundingTimestamp, "Invalid funding timestamp");
    }
}
