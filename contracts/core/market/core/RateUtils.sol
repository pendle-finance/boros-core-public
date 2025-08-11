// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {TransientSlot} from "@openzeppelin/contracts/utils/TransientSlot.sol";
import {GeneratedStorageSlots} from "../../../generated/slots.sol";
import {IMarkRateOracle} from "../../../interfaces/IMarkRateOracle.sol";
import {PMath} from "../../../lib/math/PMath.sol";
import {MarketInfoAndState} from "./MarketInfoAndState.sol";

abstract contract RateUtils is MarketInfoAndState {
    using PMath for int256;
    using TransientSlot for *;

    function _getMarkRate() internal returns (int256) {
        (int128 markRate, bool needUpdateCache) = _getMarkRateInternal();
        if (needUpdateCache) _writeCacheMarkRate(markRate);
        return markRate;
    }

    function _getMarkRateView() internal view returns (int256 markRate) {
        (markRate, ) = _getMarkRateInternal();
    }

    function _updateImpliedRate(int16 lastMatchedTick, uint8 tickStep) internal {
        uint32 blockTimestamp = uint32(block.timestamp);
        _ctx().impliedRate = _ctx().impliedRate.update(blockTimestamp, lastMatchedTick, tickStep);
    }

    function _getMarkRateInternal() private view returns (int128 markRate, bool needUpdateCache) {
        bool cached;
        (markRate, cached) = _readCacheMarkRate();
        if (cached) return (markRate, false);

        if (_ctx().useImpliedAsMarkRate) {
            (, markRate, , ) = _ctx().impliedRate.getCurrentRate(_ctx().k_tickStep);
        } else {
            address markRateOracle = _ctx().markRateOracle;
            markRate = IMarkRateOracle(markRateOracle).getMarkRate().Int128();
        }
        return (markRate, true);
    }

    function _readCacheMarkRate() private view returns (int128 markRate, bool cached) {
        uint256 packed = GeneratedStorageSlots.MARKET_CACHE_MARK_RATE_SLOT.asUint256().tload();
        cached = (packed & 1) == 1;
        markRate = int128(uint128(packed >> 1));
    }

    function _writeCacheMarkRate(int128 markRate) private {
        uint256 packed = (uint256(uint128(markRate)) << 1) | 1;
        GeneratedStorageSlots.MARKET_CACHE_MARK_RATE_SLOT.asUint256().tstore(packed);
    }
}
